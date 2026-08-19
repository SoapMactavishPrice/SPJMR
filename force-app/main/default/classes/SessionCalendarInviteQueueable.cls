@SuppressWarnings('PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity,PMD.CognitiveComplexity,PMD.NcssMethodCount')
public class SessionCalendarInviteQueueable implements Queueable, Database.AllowsCallouts {

    private static final String EVENT_TIMEZONE = 'Asia/Kolkata';
    private static final String STATUS_SYNCED    = 'Synced';
    private static final String STATUS_FAILED    = 'Failed';
    private static final String STATUS_CANCELLED = 'Cancelled';

    /** Statuses whose single pre-split event carried faculty only, so its id is the faculty copy. */
    private static final Set<String> LEGACY_FACULTY_ONLY_STATUSES = new Set<String>{ 'Draft' };

    /** Sessions that need both copies pushed: the faculty event and the silent student event. */
    private Set<Id> bothAudienceIds;
    /** Sessions that need the faculty event only (Draft — nobody is enrolled on it yet). */
    private Set<Id> facultyOnlyIds;
    /** Session id → the Google event ids to delete for it (faculty copy, student copy). */
    private Map<Id, List<String>> cancelEventIdsBySession;

    /** The user's No answer: suppresses the FACULTY event's email. Students are always silent. */
    private Boolean suppressNotifications;

    private Boolean patchOnly;

    public SessionCalendarInviteQueueable(Set<Id> bothAudienceIds, Set<Id> facultyOnlyIds) {
        this(bothAudienceIds, facultyOnlyIds, null, false);
    }

    public SessionCalendarInviteQueueable(
        Set<Id> bothAudienceIds,
        Set<Id> facultyOnlyIds,
        Map<Id, List<String>> cancelEventIdsBySession
    ) {
        this(bothAudienceIds, facultyOnlyIds, cancelEventIdsBySession, false);
    }

    public SessionCalendarInviteQueueable(
        Set<Id> bothAudienceIds,
        Set<Id> facultyOnlyIds,
        Map<Id, List<String>> cancelEventIdsBySession,
        Boolean suppressNotifications
    ) {
        this(bothAudienceIds, facultyOnlyIds, cancelEventIdsBySession, suppressNotifications, false);
    }

    /**
     * @description Builds one chunk of Google Calendar work.
     * @param bothAudienceIds Sessions needing the faculty copy and the student copy.
     * @param facultyOnlyIds Sessions needing the faculty copy only.
     * @param cancelEventIdsBySession Event ids to delete, per session.
     * @param suppressNotifications True when the user answered No: the faculty copy is pushed
     *          silently too.
     * @param patchOnly True to update existing events only, never create one.
     */
    public SessionCalendarInviteQueueable(
        Set<Id> bothAudienceIds,
        Set<Id> facultyOnlyIds,
        Map<Id, List<String>> cancelEventIdsBySession,
        Boolean suppressNotifications,
        Boolean patchOnly
    ) {
        this.bothAudienceIds          = (bothAudienceIds != null) ? bothAudienceIds : new Set<Id>();
        this.facultyOnlyIds           = (facultyOnlyIds  != null) ? facultyOnlyIds  : new Set<Id>();
        this.cancelEventIdsBySession  = (cancelEventIdsBySession != null)
            ? cancelEventIdsBySession : new Map<Id, List<String>>();
        this.suppressNotifications    = (suppressNotifications == true);
        this.patchOnly                = (patchOnly == true);
    }

    public void execute(QueueableContext qc) {
        Map<Id, Session__c> toUpdate = new Map<Id, Session__c>();

        processCancellations(toUpdate);
        processCreateOrUpdate(toUpdate);

        writeBack(toUpdate);
    }

    private void processCancellations(Map<Id, Session__c> toUpdate) {
        if (cancelEventIdsBySession.isEmpty()) {
            return;
        }

        Set<Id> existing = new Map<Id, Session__c>([
            SELECT Id FROM Session__c WHERE Id IN :cancelEventIdsBySession.keySet()
        ]).keySet();

        for (Id sessionId : cancelEventIdsBySession.keySet()) {
            List<String> eventIds = cancelEventIdsBySession.get(sessionId);
            if (eventIds == null || eventIds.isEmpty()) {
                continue;
            }
            // Every copy must go, or the faculty keep a session on their calendar that was
            // cancelled. One failure fails the whole session so the error stays visible.
            String failure = null;
            for (String eventId : eventIds) {
                if (String.isBlank(eventId)) {
                    continue;
                }
                try {
                    GoogleCalendarService.GoogleCalendarResponse resp =
                        GoogleCalendarHelper.deleteEventWithStoredCredentials(eventId);
                    if (resp == null || !resp.success) {
                        failure = (resp != null && String.isNotBlank(resp.errorMessage))
                            ? resp.errorMessage : 'Unknown cancel error';
                    }
                } catch (Exception e) {
                    failure = e.getMessage();
                }
            }

            if (!existing.contains(sessionId)) {
                continue;
            }
            Session__c upd = new Session__c(Id = sessionId);
            if (failure == null) {
                upd.Calendar_Sync_Status__c     = STATUS_CANCELLED;
                upd.Calendar_Last_Synced__c     = Datetime.now();
                upd.Google_Event_Id__c          = null;
                upd.Faculty_Google_Event_Id__c  = null;
                upd.Calendar_Sync_Error__c      = null;
            } else {
                upd.Calendar_Sync_Status__c = STATUS_FAILED;
                upd.Calendar_Sync_Error__c  = failure;
            }
            toUpdate.put(sessionId, upd);
        }
    }

    private void processCreateOrUpdate(Map<Id, Session__c> toUpdate) {
        Set<Id> allSessionIds = new Set<Id>();
        allSessionIds.addAll(bothAudienceIds);
        allSessionIds.addAll(facultyOnlyIds);
        if (allSessionIds.isEmpty()) {
            return;
        }

        Map<Id, Session__c> sessions = new Map<Id, Session__c>([
            SELECT Id, Name, Schedule_Type__c, Start_Time__c, End_Time__c,
                   Description__c, Class_Room__c, URL__c, Google_Event_Id__c,
                   Faculty_Google_Event_Id__c,
                   Course_Activity__c, Session_Type__c, Remark__c,
                   Course__r.Name, Course__r.Course_Department__r.Name,
                   Program__r.Program_Code__c, Batch__r.Name,
                   Academic_Year__r.Name, Term__r.Name
            FROM   Session__c
            WHERE  Id IN :allSessionIds
        ]);

        Map<Id, Set<String>> facultyBySession   = resolveFacultyEmails(allSessionIds);
        Map<Id, Set<String>> studentsBySession  = resolveStudentEmails(bothAudienceIds);
        Map<Id, Set<String>> divisionsBySession = resolveDivisionNames(allSessionIds);

        for (Id sessionId : sessions.keySet()) {
            Session__c s = sessions.get(sessionId);

            if (s.Start_Time__c == null || s.End_Time__c == null) {
                toUpdate.put(sessionId, new Session__c(
                    Id = sessionId,
                    Calendar_Sync_Status__c = STATUS_FAILED,
                    Calendar_Sync_Error__c  = 'Session is missing Start_Time__c / End_Time__c.'
                ));
                continue;
            }

            AudienceEmails audience = new AudienceEmails();
            audience.faculty   = facultyBySession.get(sessionId);
            audience.students  = studentsBySession.get(sessionId);
            audience.divisions = divisionsBySession.get(sessionId);

            Session__c upd = pushBothCopies(s, audience);
            if (upd != null) {
                toUpdate.put(sessionId, upd);
            }
        }
    }

    /** @description The guest emails and division names one session's two copies are built from. */
    private class AudienceEmails {
        private Set<String> faculty;
        private Set<String> students;
        private Set<String> divisions;
    }

    /**
     * @description Pushes a session's faculty copy and, once students are enrolled on it, its
     *          student copy — the faculty one notifying unless the user answered No, the student one
     *          always silent.
     * @param s The session to push, mutated by the legacy-id migration.
     * @param audience That session's faculty emails, student emails and division names.
     * @return The pending update to write back, or null when there is nothing to record.
     */
    private Session__c pushBothCopies(Session__c s, AudienceEmails audience) {
        Session__c upd = new Session__c(Id = s.Id);
        Boolean migrated = migrateLegacyEventId(s, upd);
        List<String> errors = new List<String>();

        // patchOnly bars creating an event for a session that was NEVER synced. A session that
        // already has one copy may still gain its missing counterpart: otherwise adding a faculty
        // member to an already-republished session would never reach their calendar, because that
        // save changes no session field and so fires no session-level push.
        Boolean synced = String.isNotBlank(s.Google_Event_Id__c)
            || String.isNotBlank(s.Faculty_Google_Event_Id__c);

        // FACULTY copy. The only push that ever emails anybody, and only when the user said Yes.
        CopyResult facRes = pushCopy(
            s,
            audience.faculty,
            s.Faculty_Google_Event_Id__c,
            suppressNotifications
                ? GoogleCalendarService.SEND_UPDATES_NONE
                : GoogleCalendarService.SEND_UPDATES_ALL,
            audience.divisions,
            synced
        );
        if (facRes.attempted && facRes.success) {
            upd.Faculty_Google_Event_Id__c = facRes.eventId;
        } else if (facRes.attempted) {
            errors.add('Faculty event: ' + facRes.error);
        }

        // STUDENT copy. Only once students are enrolled on the session, and ALWAYS silent —
        // students are told by the one consolidated summary email instead.
        CopyResult stuRes = new CopyResult();
        if (bothAudienceIds.contains(s.Id)) {
            stuRes = pushCopy(
                s, audience.students, s.Google_Event_Id__c,
                GoogleCalendarService.SEND_UPDATES_NONE, audience.divisions, synced
            );
        }
        if (stuRes.attempted && stuRes.success) {
            upd.Google_Event_Id__c = stuRes.eventId;
        } else if (stuRes.attempted) {
            errors.add('Student event: ' + stuRes.error);
        }

        if (!facRes.attempted && !stuRes.attempted) {
            // patchOnly skips are expected (nothing to update yet) and must stay quiet; a genuine
            // push with nobody to invite is worth surfacing, as it was before.
            if (!patchOnly) {
                upd.Calendar_Sync_Status__c = STATUS_FAILED;
                upd.Calendar_Sync_Error__c  =
                    'No attendees with a valid email were found for this session.';
            }
            return (!patchOnly || migrated) ? upd : null;
        }

        stampOutcome(upd, errors);
        return upd;
    }

    /**
     * @description Records the combined outcome of a session's two pushes. Synced only when every
     *          copy that was attempted succeeded; otherwise Failed, naming which copy broke.
     * @param upd The pending update to stamp.
     * @param errors One message per failed copy, empty when all succeeded.
     */
    private void stampOutcome(Session__c upd, List<String> errors) {
        if (errors.isEmpty()) {
            upd.Calendar_Sync_Status__c = STATUS_SYNCED;
            upd.Calendar_Last_Synced__c = Datetime.now();
            upd.Calendar_Sync_Error__c  = null;
        } else {
            upd.Calendar_Sync_Status__c = STATUS_FAILED;
            upd.Calendar_Sync_Error__c  = String.join(errors, ' | ');
        }
    }

    /** @description Outcome of pushing one audience's copy of a session's event. */
    private class CopyResult {
        /** True when a Google callout was actually made for this copy. */
        private Boolean attempted = false;
        private Boolean success = false;
        private String eventId;
        private String error;
    }

    /**
     * @description Creates or updates one audience's copy of the session's Google event.
     * @param s The session being pushed.
     * @param attendees That audience's guest emails; an empty set means there is nothing to push.
     * @param existingEventId The stored event id for this copy, blank when it does not exist yet.
     * @param sendUpdates Google's notification mode for this copy.
     * @param divisionNames Division names that appear in the event text.
     * @param sessionAlreadySynced Whether the session already has at least one copy in Google, which
     *          lets a patchOnly push create the missing counterpart.
     * @return What happened, so the caller can stamp the id or the error.
     */
    private CopyResult pushCopy(
        Session__c s,
        Set<String> attendees,
        String existingEventId,
        String sendUpdates,
        Set<String> divisionNames,
        Boolean sessionAlreadySynced
    ) {
        CopyResult res = new CopyResult();

        Set<String> clean = (attendees != null) ? new Set<String>(attendees) : new Set<String>();
        clean.remove(null);
        clean.remove('');
        if (clean.isEmpty()) {
            return res;
        }

        Boolean isUpdate = String.isNotBlank(existingEventId);
        if (patchOnly && !isUpdate && sessionAlreadySynced != true) {
            return res;
        }

        res.attempted = true;
        GoogleCalendarEvent ev = buildEvent(s, new List<String>(clean), divisionNames);
        try {
            GoogleCalendarService.GoogleCalendarResponse resp = isUpdate
                ? GoogleCalendarHelper.updateEventWithStoredCredentials(existingEventId, ev, sendUpdates)
                : GoogleCalendarHelper.createEventWithStoredCredentials(ev, sendUpdates);

            if (resp != null && resp.success) {
                res.success = true;
                res.eventId = String.isNotBlank(resp.eventId) ? resp.eventId : existingEventId;
            } else {
                res.error = (resp != null && String.isNotBlank(resp.errorMessage))
                    ? resp.errorMessage : 'Unknown sync error';
            }
        } catch (Exception e) {
            res.error = e.getMessage();
        }
        return res;
    }

    /**
     * @description Moves a pre-split Draft's single event id into the faculty field. Before the
     *          split a Draft's only event was faculty-only, so that id IS the faculty copy and
     *          nothing needs to be sent to Google. Published sessions are deliberately left alone:
     *          their shared event keeps the students and their RSVP answers, and the faculty copy is
     *          created fresh alongside it.
     * @param s The session row, mutated so the pushes below use the corrected ids.
     * @param upd The pending update, stamped with the moved ids.
     * @return Whether an id was moved.
     */
    private Boolean migrateLegacyEventId(Session__c s, Session__c upd) {
        Boolean isLegacyDraft = String.isBlank(s.Faculty_Google_Event_Id__c)
            && String.isNotBlank(s.Google_Event_Id__c)
            && LEGACY_FACULTY_ONLY_STATUSES.contains(s.Schedule_Type__c);
        if (!isLegacyDraft) {
            return false;
        }
        s.Faculty_Google_Event_Id__c   = s.Google_Event_Id__c;
        s.Google_Event_Id__c           = null;
        upd.Faculty_Google_Event_Id__c = s.Faculty_Google_Event_Id__c;
        upd.Google_Event_Id__c         = null;
        return true;
    }

    private void writeBack(Map<Id, Session__c> toUpdate) {
        if (toUpdate.isEmpty()) {
            return;
        }
        Boolean prior = SessionCalendarInviteHandler.suppressInvites;
        SessionCalendarInviteHandler.suppressInvites = true;
        try {

            Database.update(toUpdate.values(), false);
        } catch (Exception e) {

            String ignored = e.getMessage();
        } finally {
            SessionCalendarInviteHandler.suppressInvites = prior;
        }
    }

    private GoogleCalendarEvent buildEvent(Session__c s, List<String> attendees, Set<String> divisionNames) {
        GoogleCalendarEvent ev = new GoogleCalendarEvent();

        String courseName  = (s.Course__r != null && String.isNotBlank(s.Course__r.Name)) ? s.Course__r.Name : '';
        String sessionName = String.isNotBlank(s.Name) ? s.Name : '';
        String courseSession;
        if (String.isNotBlank(courseName) && String.isNotBlank(sessionName)) {
            courseSession = courseName + ' - ' + sessionName;
        } else {
            courseSession = String.isNotBlank(courseName) ? courseName : sessionName;
        }

        String programmeCode = (s.Program__r != null) ? s.Program__r.Program_Code__c : null;
        String batchName     = (s.Batch__r != null) ? s.Batch__r.Name : null;

        String batchGroup    = (s.Academic_Year__r != null) ? s.Academic_Year__r.Name : null;
        String termName      = (s.Term__r != null) ? s.Term__r.Name : null;
        String divisionText  = (divisionNames != null && !divisionNames.isEmpty())
            ? String.join(new List<String>(divisionNames), ', ')
            : null;

        String departmentName = (s.Course__r != null && s.Course__r.Course_Department__r != null)
            ? s.Course__r.Course_Department__r.Name
            : null;

        List<String> summaryParts = new List<String>();
        if (String.isNotBlank(programmeCode)) { summaryParts.add(programmeCode); }
        if (String.isNotBlank(batchName))     { summaryParts.add(batchName); }
        if (String.isNotBlank(batchGroup))    { summaryParts.add(batchGroup); }
        if (String.isNotBlank(termName))      { summaryParts.add(termName); }
        if (String.isNotBlank(divisionText))  { summaryParts.add(divisionText); }
        if (String.isNotBlank(courseSession)) { summaryParts.add(courseSession); }
        ev.summary = String.join(summaryParts, ' | ');

        ev.timeZone      = EVENT_TIMEZONE;
        ev.startDateTime = toGoogleTime(s.Start_Time__c);
        ev.endDateTime   = toGoogleTime(s.End_Time__c);

        List<String> locationParts = new List<String>();
        if (String.isNotBlank(s.Class_Room__c)) {
            locationParts.add(s.Class_Room__c);
        }
        if (String.isNotBlank(s.URL__c)) {
            locationParts.add(s.URL__c);
        }
        if (!locationParts.isEmpty()) {
            ev.location = String.join(locationParts, ' | ');
        }

        List<String> detailLines = new List<String>();
        if (String.isNotBlank(s.Schedule_Type__c)) {
            detailLines.add('Status: ' + s.Schedule_Type__c);
        }
        if (String.isNotBlank(programmeCode)) {
            detailLines.add('Programme: ' + programmeCode);
        }
        if (String.isNotBlank(batchName)) {
            detailLines.add('Batch: ' + batchName);
        }
        if (String.isNotBlank(batchGroup)) {
            detailLines.add('Batch Group: ' + batchGroup);
        }
        if (String.isNotBlank(termName)) {
            detailLines.add('Term: ' + termName);
        }
        if (String.isNotBlank(divisionText)) {
            detailLines.add('Division: ' + divisionText);
        }
        if (String.isNotBlank(departmentName)) {
            detailLines.add('Department: ' + departmentName);
        }
        if (String.isNotBlank(courseSession)) {
            detailLines.add('Course: ' + courseSession);
        }
        if (String.isNotBlank(s.Course_Activity__c)) {
            detailLines.add('Course Activity: ' + s.Course_Activity__c);
        }
        if (String.isNotBlank(s.Session_Type__c)) {
            detailLines.add('Session Type: ' + s.Session_Type__c);
        }
        if (String.isNotBlank(s.Class_Room__c)) {
            detailLines.add('Room: ' + s.Class_Room__c);
        }
        if (String.isNotBlank(s.Remark__c)) {
            detailLines.add('Remark: ' + s.Remark__c);
        }

        String descText = String.join(detailLines, '\n');
        if (String.isNotBlank(s.Description__c)) {
            descText += '\n\n' + s.Description__c;
        }
        if (String.isNotBlank(s.URL__c)) {
            descText += '\n\n' + 'Join: ' + s.URL__c;
        }
        ev.description = descText;

        ev.attendees = attendees;
        return ev;
    }

    private Map<Id, Set<String>> resolveDivisionNames(Set<Id> sessionIds) {
        Map<Id, Set<String>> bySession = new Map<Id, Set<String>>();
        if (sessionIds == null || sessionIds.isEmpty()) {
            return bySession;
        }
        for (Session_Division__c sd : [
            SELECT Session__c, Division__r.Division_Name__c
            FROM   Session_Division__c
            WHERE  Session__c IN :sessionIds
              AND  Division__r.Division_Name__c != NULL
        ]) {
            String name = (sd.Division__r != null) ? sd.Division__r.Division_Name__c : null;
            if (String.isBlank(name)) {
                continue;
            }
            if (!bySession.containsKey(sd.Session__c)) {
                bySession.put(sd.Session__c, new Set<String>());
            }
            bySession.get(sd.Session__c).add(name);
        }
        return bySession;
    }

    private Map<String, Object> toGoogleTime(Datetime dt) {
        return new Map<String, Object>{
            'dateTime' => dt.format('yyyy-MM-dd\'T\'HH:mm:ss', EVENT_TIMEZONE),
            'timeZone' => EVENT_TIMEZONE
        };
    }

    private Map<Id, Set<String>> resolveFacultyEmails(Set<Id> sessionIds) {
        Map<Id, Set<String>> bySession = new Map<Id, Set<String>>();
        for (Session_Faculty__c sf : [
            SELECT Session__c, Session_Faculty__r.PersonEmail
            FROM   Session_Faculty__c
            WHERE  Session__c IN :sessionIds
              AND  Session_Faculty__r.PersonEmail != NULL
        ]) {
            String email = (sf.Session_Faculty__r != null) ? sf.Session_Faculty__r.PersonEmail : null;
            if (String.isBlank(email)) {
                continue;
            }
            if (!bySession.containsKey(sf.Session__c)) {
                bySession.put(sf.Session__c, new Set<String>());
            }
            bySession.get(sf.Session__c).add(email);
        }
        return bySession;
    }

    private Map<Id, Set<String>> resolveStudentEmails(Set<Id> sessionIds) {
        Map<Id, Set<String>> bySession = new Map<Id, Set<String>>();
        if (sessionIds.isEmpty()) {
            return bySession;
        }
        for (Session_Enrollment__c se : [
            SELECT Session__c,
                   Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail
            FROM   Session_Enrollment__c
            WHERE  Session__c IN :sessionIds
              AND  Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail != NULL
        ]) {

            String email =
                (se.Division_Enrollment__r != null
                    && se.Division_Enrollment__r.Academic_Term_Enrollment__r != null
                    && se.Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount != null)
                ? se.Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail
                : null;
            if (String.isBlank(email)) {
                continue;
            }
            if (!bySession.containsKey(se.Session__c)) {
                bySession.put(se.Session__c, new Set<String>());
            }
            bySession.get(se.Session__c).add(email);
        }
        return bySession;
    }
}
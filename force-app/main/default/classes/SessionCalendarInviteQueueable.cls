@SuppressWarnings('PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity,PMD.CognitiveComplexity,PMD.NcssMethodCount')
public class SessionCalendarInviteQueueable implements Queueable, Database.AllowsCallouts {

    private static final String EVENT_TIMEZONE = 'Asia/Kolkata';
    private static final String STATUS_SYNCED    = 'Synced';
    private static final String STATUS_FAILED    = 'Failed';
    private static final String STATUS_CANCELLED = 'Cancelled';

    private Set<Id> publishSessionIds;
    private Set<Id> draftSessionIds;
    private Map<Id, String> cancelEventIdsBySession;

    private Boolean suppressNotifications;

    public SessionCalendarInviteQueueable(Set<Id> publishSessionIds, Set<Id> draftSessionIds) {
        this(publishSessionIds, draftSessionIds, null, false);
    }

    public SessionCalendarInviteQueueable(
        Set<Id> publishSessionIds,
        Set<Id> draftSessionIds,
        Map<Id, String> cancelEventIdsBySession
    ) {
        this(publishSessionIds, draftSessionIds, cancelEventIdsBySession, false);
    }

    public SessionCalendarInviteQueueable(
        Set<Id> publishSessionIds,
        Set<Id> draftSessionIds,
        Map<Id, String> cancelEventIdsBySession,
        Boolean suppressNotifications
    ) {
        this.publishSessionIds        = (publishSessionIds != null) ? publishSessionIds : new Set<Id>();
        this.draftSessionIds          = (draftSessionIds   != null) ? draftSessionIds   : new Set<Id>();
        this.cancelEventIdsBySession  = (cancelEventIdsBySession != null)
            ? cancelEventIdsBySession : new Map<Id, String>();
        this.suppressNotifications    = (suppressNotifications == true);
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
            String eventId = cancelEventIdsBySession.get(sessionId);
            if (String.isBlank(eventId)) {
                continue;
            }
            try {
                GoogleCalendarService.GoogleCalendarResponse resp =
                    GoogleCalendarHelper.deleteEventWithStoredCredentials(eventId);

                if (existing.contains(sessionId)) {
                    Session__c upd = new Session__c(Id = sessionId);
                    if (resp != null && resp.success) {
                        upd.Calendar_Sync_Status__c = STATUS_CANCELLED;
                        upd.Calendar_Last_Synced__c = Datetime.now();
                        upd.Google_Event_Id__c      = null;
                        upd.Calendar_Sync_Error__c  = null;
                    } else {
                        upd.Calendar_Sync_Status__c = STATUS_FAILED;
                        upd.Calendar_Sync_Error__c  = (resp != null) ? resp.errorMessage : 'Unknown cancel error';
                    }
                    toUpdate.put(sessionId, upd);
                }
            } catch (Exception e) {
                if (existing.contains(sessionId)) {
                    toUpdate.put(sessionId, new Session__c(
                        Id = sessionId,
                        Calendar_Sync_Status__c = STATUS_FAILED,
                        Calendar_Sync_Error__c  = e.getMessage()
                    ));
                }
            }
        }
    }

    private void processCreateOrUpdate(Map<Id, Session__c> toUpdate) {
        Set<Id> allSessionIds = new Set<Id>();
        allSessionIds.addAll(publishSessionIds);
        allSessionIds.addAll(draftSessionIds);
        if (allSessionIds.isEmpty()) {
            return;
        }

        Map<Id, Session__c> sessions = new Map<Id, Session__c>([
            SELECT Id, Name, Schedule_Type__c, Start_Time__c, End_Time__c,
                   Description__c, Class_Room__c, URL__c, Google_Event_Id__c,
                   Course_Activity__c, Session_Type__c, Remark__c,
                   Course__r.Name, Course__r.Course_Department__r.Name,
                   Program__r.Program_Code__c, Batch__r.Name,
                   Academic_Year__r.Name, Term__r.Name
            FROM   Session__c
            WHERE  Id IN :allSessionIds
        ]);

        Map<Id, Set<String>> facultyBySession   = resolveFacultyEmails(allSessionIds);
        Map<Id, Set<String>> studentsBySession  = resolveStudentEmails(publishSessionIds);
        Map<Id, Set<String>> divisionsBySession = resolveDivisionNames(allSessionIds);

        for (Id sessionId : sessions.keySet()) {
            Session__c s = sessions.get(sessionId);

            Set<String> attendees = new Set<String>();
            if (facultyBySession.containsKey(sessionId)) {
                attendees.addAll(facultyBySession.get(sessionId));
            }
            if (publishSessionIds.contains(sessionId) && studentsBySession.containsKey(sessionId)) {
                attendees.addAll(studentsBySession.get(sessionId));
            }
            attendees.remove(null);
            attendees.remove('');

            if (attendees.isEmpty() || s.Start_Time__c == null || s.End_Time__c == null) {

                String why = (s.Start_Time__c == null || s.End_Time__c == null)
                    ? 'Session is missing Start_Time__c / End_Time__c.'
                    : 'No attendees with a valid email were found for this session.';
                toUpdate.put(sessionId, new Session__c(
                    Id = sessionId,
                    Calendar_Sync_Status__c = STATUS_FAILED,
                    Calendar_Sync_Error__c  = why
                ));
                continue;
            }

            GoogleCalendarEvent ev = buildEvent(s, new List<String>(attendees), divisionsBySession.get(sessionId));

            try {
                Boolean isUpdate = String.isNotBlank(s.Google_Event_Id__c);
                String sendUpdates = suppressNotifications
                    ? GoogleCalendarService.SEND_UPDATES_NONE
                    : GoogleCalendarService.SEND_UPDATES_ALL;
                GoogleCalendarService.GoogleCalendarResponse resp = isUpdate
                    ? GoogleCalendarHelper.updateEventWithStoredCredentials(s.Google_Event_Id__c, ev, sendUpdates)
                    : GoogleCalendarHelper.createEventWithStoredCredentials(ev, sendUpdates);

                Session__c upd = new Session__c(Id = sessionId);
                if (resp != null && resp.success) {

                    upd.Google_Event_Id__c      = String.isNotBlank(resp.eventId)
                        ? resp.eventId : s.Google_Event_Id__c;
                    upd.Calendar_Sync_Status__c = STATUS_SYNCED;
                    upd.Calendar_Last_Synced__c = Datetime.now();
                    upd.Calendar_Sync_Error__c  = null;
                } else {
                    upd.Calendar_Sync_Status__c = STATUS_FAILED;
                    upd.Calendar_Sync_Error__c  = (resp != null) ? resp.errorMessage : 'Unknown sync error';
                }
                toUpdate.put(sessionId, upd);
            } catch (Exception e) {
                toUpdate.put(sessionId, new Session__c(
                    Id = sessionId,
                    Calendar_Sync_Status__c = STATUS_FAILED,
                    Calendar_Sync_Error__c  = e.getMessage()
                ));
            }
        }
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
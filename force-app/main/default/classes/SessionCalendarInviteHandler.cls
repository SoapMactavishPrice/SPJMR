/**
 * @description Routes Session__c changes to the Google Calendar integration. Every session that
 *          reaches a student-facing status carries TWO Google events:
 *
 *          - the FACULTY event (Faculty_Google_Event_Id__c), guests = the assigned faculty. Created
 *            on Draft and kept in step from then on. This is the only event that ever emails
 *            anybody: the user's Yes/No answer decides whether it is pushed with sendUpdates=all
 *            (a real "Updated invitation" showing what changed) or silently.
 *          - the STUDENT event (Google_Event_Id__c), guests = the enrolled students. Created when
 *            the session is published and ALWAYS pushed with sendUpdates=none, so students' entries
 *            stay correct without a per-session email. They are told once, by the consolidated
 *            summary email that TimetableSessionController enqueues.
 *
 *          Google's sendUpdates applies to a whole event, not to individual guests, so one shared
 *          event could never email the faculty without also emailing every student. Splitting the
 *          audiences onto their own events is what makes the two notification rules independent —
 *          on publish, republish and reschedule alike.
 *
 *          Also exposes handleRelatedRecordChange() so that a change on a related
 *          record which feeds the event body or the guest list — Session_Division__c
 *          (division names appear in the summary and description), Session_Faculty__c
 *          (faculty ARE the guest list) and Session_Enrollment__c (students are the
 *          guest list) — re-pushes the existing Google event. That path is PATCH-only:
 *          it never creates an event for a session that was never synced.
 *
 * @note    Notification control: skipUserNotifications is a transaction-scoped flag set by
 *          the caller that performs the DML (see TimetableSessionController). It is the user's No
 *          answer, and it now governs the FACULTY event only — the student event is silent either
 *          way. Cancellation deliberately ignores it: a cancelled session must always notify its
 *          guests, so both events are deleted with notifications on.
 *
 * @note    Google only emails a guest when the event genuinely changed for that guest.
 *          SessionCalendarInviteQueueable.buildEvent therefore includes the schedule state
 *          in the event description, so Draft -> Published is a real change and the faculty
 *          already on the event receive an "Updated invitation" rather than nothing.
 *
 * @note    Legacy sessions synced before the split hold one shared event in Google_Event_Id__c.
 *          The queueable migrates them on the first push: a Draft's event was faculty-only, so its
 *          id simply moves to Faculty_Google_Event_Id__c; a published session's event keeps the
 *          students (and their RSVP answers) and a new faculty event is created alongside, with the
 *          faculty dropping off the student event silently on that same push.
 */
// Sharing declared explicitly as `without sharing`: this is trigger-driven integration code
// that must resolve every session, division, faculty and enrolment involved regardless of
// the acting user's sharing, exactly as it behaved before the declaration was added.
//
// ApexCRUDViolation suppressed: system-context integration routing. The SOQL only reads the
// parent Session__c rows the trigger was already handed, and the only DML stamps the
// integration's own Calendar_Sync_* fields on those same sessions.
// OperationWithLimitsInLoop suppressed: System.enqueueJob inside the chunking loop IS the
// mechanism that keeps each job under the 100-callout limit; the loop is explicitly bounded
// by the available queueable slots and stamps anything it cannot send.
@SuppressWarnings('PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity,PMD.CognitiveComplexity,PMD.NcssMethodCount,PMD.ApexCRUDViolation,PMD.OperationWithLimitsInLoop')
public without sharing class SessionCalendarInviteHandler {

    private static final Set<String> AUDIENCE_ALL     = new Set<String>{ 'Published', 'Republished' };
    private static final Set<String> AUDIENCE_FACULTY = new Set<String>{ 'Draft' };

    private static final Set<String> UPDATE_ONLY      = new Set<String>{ 'Rescheduled' };
    private static final String STATUS_CANCELLED      = 'Cancelled';
    private static final String STATUS_FAILED         = 'Failed';

    private static final Integer MAX_CALLOUTS_PER_JOB = 30;

    /**
     * @description SOQL queries left in reserve for the caller's own transaction before the
     *          related-record re-push stops querying. Protects the caller's DML from failing
     *          because of a secondary calendar sync.
     */
    private static final Integer QUERY_HEADROOM = 15;

    /**
     * @description Maximum SOQL queries the related-record re-push may spend in one transaction.
     *          A bulkified caller inserts its related rows in ONE DML and therefore needs exactly
     *          one query, so this cap is never reached in normal use. It exists to bound callers
     *          that insert related rows one-per-DML inside a loop, where an unbounded query per
     *          invocation would consume the caller's own SOQL budget and fail their save.
     */
    private static final Integer MAX_RELATED_QUERIES = 5;

    /** @description Related-record queries already spent in this transaction. */
    private static Integer relatedQueriesUsed = 0;

    /** @description Re-entry guard: set while the queueable writes its own sync fields back. */
    public static Boolean suppressInvites = false;

    /**
     * @description The user's No answer: when true the faculty event is pushed with
     *          sendUpdates=none, so nobody is emailed. The student event is silent regardless.
     */
    public static Boolean skipUserNotifications = false;

    /**
     * @description The user's Yes answer, set by the same caller that sets skipUserNotifications.
     *          Only the related-record re-push reads it, and only to tell two cases apart that
     *          skipUserNotifications alone cannot: a user save where Yes was chosen (the faculty
     *          SHOULD be emailed, because adding a faculty member to an already-republished session
     *          fires no session-level push of its own) versus a background flow that never asked
     *          anybody — enrolment sync, division auto-assign — where emailing faculty is noise.
     */
    public static Boolean facultyNotifyRequested = false;

    /**
     * @description Transaction-scoped dedupe. A single user action can touch the Session and
     *          its related records in one transaction (removing a division stamps the session
     *          Republished AND deletes Session_Division__c rows), which would otherwise enqueue
     *          two PATCHes and send guests two "Updated invitation" emails for one click.
     */
    private static Set<Id> alreadyEnqueued = new Set<Id>();

    /**
     * @description One unit of Google Calendar push work. Bundled into an object, and populated
     *          by field assignment rather than a constructor, so the chunking method keeps a
     *          short signature as the number of push options grows.
     */
    private class PushRequest {
        /** Sessions needing BOTH events: the faculty copy and the silent student copy. */
        private Set<Id> bothAudienceIds = new Set<Id>();
        /** Sessions needing the faculty event only (Draft — no students are enrolled on it yet). */
        private Set<Id> facultyOnlyIds = new Set<Id>();
        /** Session id → every Google event id to delete for it (faculty copy, student copy). */
        private Map<Id, List<String>> cancelEventIdsBySession = new Map<Id, List<String>>();
        private Boolean suppressNotifications = false;
        private Boolean patchOnly = false;
    }

    /**
     * @description Collects the Google event ids to delete for one session — both copies, skipping
     *          whichever is not populated.
     * @param s The session being cancelled or deleted.
     * @return The event ids, or an empty list when the session was never synced.
     */
    private static List<String> eventIdsOf(Session__c s) {
        List<String> ids = new List<String>();
        if (String.isNotBlank(s.Google_Event_Id__c)) {
            ids.add(s.Google_Event_Id__c);
        }
        if (String.isNotBlank(s.Faculty_Google_Event_Id__c)) {
            ids.add(s.Faculty_Google_Event_Id__c);
        }
        return ids;
    }

    /**
     * @description True when either copy of the session's Google event exists.
     * @param s The session to check.
     * @return Whether this session has ever been pushed to Google.
     */
    private static Boolean hasAnyEvent(Session__c s) {
        return String.isNotBlank(s.Google_Event_Id__c)
            || String.isNotBlank(s.Faculty_Google_Event_Id__c);
    }

    /**
     * @description Classifies Session__c inserts/updates and enqueues the Google Calendar work.
     * @param newMap The trigger's new map.
     * @param oldMap The trigger's old map (null on insert).
     */
    public static void handleSessionCalendarInvites(
        Map<Id, Session__c> newMap,
        Map<Id, Session__c> oldMap
    ) {
        if (suppressInvites || newMap == null || newMap.isEmpty()) {
            return;
        }

        Boolean suppressNotifications = skipUserNotifications;

        Set<Id> bothAudienceIds = new Set<Id>();
        Set<Id> facultyOnlyIds  = new Set<Id>();
        Map<Id, List<String>> cancelEventIdsBySession = new Map<Id, List<String>>();

        for (Session__c s : newMap.values()) {
            Session__c oldRec = (oldMap != null) ? oldMap.get(s.Id) : null;
            String oldStatus  = (oldRec != null) ? oldRec.Schedule_Type__c : null;
            String newStatus  = s.Schedule_Type__c;
            Boolean hasEvent      = hasAnyEvent(s);
            Boolean statusChanged = (newStatus != oldStatus);

            if (newStatus == STATUS_CANCELLED) {
                if (statusChanged && hasEvent) {
                    cancelEventIdsBySession.put(s.Id, eventIdsOf(s));
                }
                continue;
            }

            if (UPDATE_ONLY.contains(newStatus)) {
                if (hasEvent && (statusChanged || detailsChanged(s, oldRec))) {
                    bothAudienceIds.add(s.Id);
                }
                continue;
            }

            Boolean isAll     = AUDIENCE_ALL.contains(newStatus);
            Boolean isFaculty = AUDIENCE_FACULTY.contains(newStatus);
            if (!isAll && !isFaculty) {
                continue;
            }
            if (statusChanged || (hasEvent && detailsChanged(s, oldRec))) {
                if (isAll) {
                    bothAudienceIds.add(s.Id);
                } else {
                    facultyOnlyIds.add(s.Id);
                }
            }
        }

        PushRequest req = new PushRequest();
        req.bothAudienceIds = bothAudienceIds;
        req.facultyOnlyIds = facultyOnlyIds;
        req.cancelEventIdsBySession = cancelEventIdsBySession;
        req.suppressNotifications = suppressNotifications;
        enqueueWork(req);
    }

    /**
     * @description Trigger-friendly overload: collects the parent session ids off a list of
     *          related records and re-pushes their Google events. Keeps the calling triggers to
     *          a single delegating line instead of their own collection loop.
     * @param rows The related records (Session_Division__c / Session_Faculty__c /
     *          Session_Enrollment__c), i.e. Trigger.new or Trigger.old.
     * @param sessionFieldApi API name of the lookup on those records pointing at Session__c.
     */
    public static void handleRelatedRecordChange(List<SObject> rows, String sessionFieldApi) {
        if (rows == null || rows.isEmpty() || String.isBlank(sessionFieldApi)) {
            return;
        }
        Set<Id> sessionIds = new Set<Id>();
        for (SObject row : rows) {
            Id sessionId = (Id) row.get(sessionFieldApi);
            if (sessionId != null) {
                sessionIds.add(sessionId);
            }
        }
        handleRelatedRecordChange(sessionIds);
    }

    /**
     * @description Re-pushes the Google event for sessions whose guest list or event text was
     *          changed by a related record (division / faculty / enrolment). PATCH-only: a
     *          session with no Google_Event_Id__c is skipped, never created, because those
     *          related objects must not be able to publish an unsynced session by side effect.
     *          Cancelled/Complete/Scheduled sessions are skipped too.
     * @param sessionIds The parent Session__c ids whose related records changed.
     */
    public static void handleRelatedRecordChange(Set<Id> sessionIds) {
        if (suppressInvites || sessionIds == null || sessionIds.isEmpty()) {
            return;
        }

        // Only look at sessions this transaction has not already pushed. Doing this BEFORE the
        // SOQL means a bulk operation that touches the same sessions repeatedly costs one query,
        // not one per invocation.
        Set<Id> unseen = new Set<Id>(sessionIds);
        unseen.removeAll(alreadyEnqueued);
        if (unseen.isEmpty()) {
            return;
        }

        // Resource guard. This runs on every Session_Division__c / Session_Faculty__c /
        // Session_Enrollment__c DML, so callers that insert related rows one-per-DML in a loop
        // would otherwise spend the whole transaction's SOQL budget here and break the caller's
        // own save. Bulkified callers (one DML for many rows) never come close to this.
        // Re-pushing the calendar is secondary to the caller's DML succeeding, so when the
        // transaction is nearly out of queries or has no queueable slots left, skip the re-push:
        // the next edit, republish or the on-demand refresh in the UI will pick it up.
        if (relatedQueriesUsed >= MAX_RELATED_QUERIES
                || Limits.getQueries() >= Limits.getLimitQueries() - QUERY_HEADROOM
                || Limits.getLimitQueueableJobs() - Limits.getQueueableJobs() <= 0) {
            return;
        }
        relatedQueriesUsed++;

        Set<Id> bothAudienceIds = new Set<Id>();
        Set<Id> facultyOnlyIds  = new Set<Id>();

        for (Session__c s : [
            SELECT Id, Schedule_Type__c, Google_Event_Id__c, Faculty_Google_Event_Id__c
            FROM   Session__c
            WHERE  Id IN :unseen
              AND  (Google_Event_Id__c != NULL OR Faculty_Google_Event_Id__c != NULL)
        ]) {
            if (AUDIENCE_ALL.contains(s.Schedule_Type__c) || UPDATE_ONLY.contains(s.Schedule_Type__c)) {
                bothAudienceIds.add(s.Id);
            } else if (AUDIENCE_FACULTY.contains(s.Schedule_Type__c)) {
                facultyOnlyIds.add(s.Id);
            }
        }

        PushRequest req = new PushRequest();
        req.bothAudienceIds = bothAudienceIds;
        req.facultyOnlyIds = facultyOnlyIds;
        // Silent unless the user answered Yes in this very transaction. Background flows that move
        // enrolments or auto-assign divisions must not email the faculty an "Updated invitation"
        // per related-record save.
        req.suppressNotifications = (facultyNotifyRequested != true);
        req.patchOnly = true;
        enqueueWork(req);
    }

    /**
     * @description Cancels the Google event of any deleted Session that had one.
     * @param oldMap The trigger's old map.
     */
    public static void handleSessionDeletes(Map<Id, Session__c> oldMap) {
        if (suppressInvites || oldMap == null || oldMap.isEmpty()) {
            return;
        }
        Map<Id, List<String>> cancelEventIdsBySession = new Map<Id, List<String>>();
        for (Session__c s : oldMap.values()) {
            List<String> ids = eventIdsOf(s);
            if (!ids.isEmpty()) {
                cancelEventIdsBySession.put(s.Id, ids);
            }
        }

        PushRequest req = new PushRequest();
        req.cancelEventIdsBySession = cancelEventIdsBySession;
        enqueueWork(req);
    }

    /**
     * @description True when an edit touched any Session__c field that feeds the Google event.
     *          Split into three helpers to stay inside the per-method complexity limit.
     * @param s The new version of the session.
     * @param oldRec The old version of the session.
     * @return Whether the Google event needs to be re-pushed.
     */
    private static Boolean detailsChanged(Session__c s, Session__c oldRec) {
        if (oldRec == null) {
            return false;
        }
        return timingChanged(s, oldRec)
            || contentChanged(s, oldRec)
            || contextChanged(s, oldRec);
    }

    /**
     * @description Compares the fields that drive the event's start/end and location.
     * @param s The new version of the session.
     * @param oldRec The old version of the session.
     * @return Whether any timing or location field changed.
     */
    private static Boolean timingChanged(Session__c s, Session__c oldRec) {
        return s.Start_Time__c   != oldRec.Start_Time__c
            || s.End_Time__c     != oldRec.End_Time__c
            || s.Session_Date__c != oldRec.Session_Date__c
            || s.Class_Room__c   != oldRec.Class_Room__c
            || s.URL__c          != oldRec.URL__c;
    }

    /**
     * @description Compares the fields that drive the event's summary and description text.
     * @param s The new version of the session.
     * @param oldRec The old version of the session.
     * @return Whether any descriptive field changed.
     */
    private static Boolean contentChanged(Session__c s, Session__c oldRec) {
        return s.Name              != oldRec.Name
            || s.Description__c    != oldRec.Description__c
            || s.Course_Activity__c != oldRec.Course_Activity__c
            || s.Session_Type__c   != oldRec.Session_Type__c
            || s.Remark__c         != oldRec.Remark__c
            || s.Course__c         != oldRec.Course__c;
    }

    /**
     * @description Compares the academic-context lookups that appear in the event summary
     *          and the labelled description lines.
     * @param s The new version of the session.
     * @param oldRec The old version of the session.
     * @return Whether any academic-context field changed.
     */
    private static Boolean contextChanged(Session__c s, Session__c oldRec) {
        return s.Program__c          != oldRec.Program__c
            || s.Batch__c            != oldRec.Batch__c
            || s.Term__c             != oldRec.Term__c
            || s.Academic_Year__c    != oldRec.Academic_Year__c
            || s.Is_Joint_Session__c != oldRec.Is_Joint_Session__c;
    }

    /**
     * @description Chunks the work into queueables, each capped at MAX_CALLOUTS_PER_JOB
     *          sessions. Sessions that cannot be enqueued because the transaction ran out of
     *          queueable slots are stamped Failed with a reason instead of being dropped
     *          silently. Create/update pushes are deduped per transaction; cancellations are
     *          never deduped because a cancellation must always reach the guests.
     * @param req The work to enqueue.
     */
    private static void enqueueWork(PushRequest req) {
        Set<Id> bothSet = new Set<Id>(req.bothAudienceIds);
        Set<Id> facSet  = new Set<Id>(req.facultyOnlyIds);
        bothSet.removeAll(alreadyEnqueued);
        facSet.removeAll(alreadyEnqueued);

        if (bothSet.isEmpty() && facSet.isEmpty() && req.cancelEventIdsBySession.isEmpty()) {
            return;
        }

        if (!GoogleCalendarHelper.isActive()) {
            return;
        }

        alreadyEnqueued.addAll(bothSet);
        alreadyEnqueued.addAll(facSet);

        req.bothAudienceIds = bothSet;
        req.facultyOnlyIds = facSet;
        stampDropped(enqueueChunks(req));
    }

    /**
     * @description Fills queueables with up to MAX_CALLOUTS_PER_JOB Google callouts each — two per
     *          student-facing session, one per Draft, one per event copy being cancelled — until the
     *          work is exhausted or the transaction runs out of queueable slots.
     * @param req The deduped work being enqueued.
     * @return The session ids that could not be enqueued (empty when everything was sent).
     */
    private static Set<Id> enqueueChunks(PushRequest req) {
        List<Id> both = new List<Id>(req.bothAudienceIds);
        List<Id> fac  = new List<Id>(req.facultyOnlyIds);
        List<Id> can  = new List<Id>(req.cancelEventIdsBySession.keySet());

        Integer bi = 0;
        Integer fi = 0;
        Integer ci = 0;
        Boolean outOfSlots = false;
        while (bi < both.size() || fi < fac.size() || ci < can.size()) {
            if (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs() <= 0) {
                outOfSlots = true;
                break;
            }

            Set<Id> chunkBoth = new Set<Id>();
            Set<Id> chunkFac  = new Set<Id>();
            Map<Id, List<String>> chunkCan = new Map<Id, List<String>>();

            // Budget counts CALLOUTS, not sessions: a student-facing session pushes two events
            // (faculty copy + student copy) and a cancellation deletes however many copies exist.
            Integer room = MAX_CALLOUTS_PER_JOB;
            while (room >= 2 && bi < both.size()) { chunkBoth.add(both[bi]); bi++; room -= 2; }
            while (room >= 1 && fi < fac.size())  { chunkFac.add(fac[fi]);   fi++; room -= 1; }
            while (ci < can.size()) {
                Integer cost = cancelCost(req, can[ci]);
                if (cost > room && !chunkCan.isEmpty()) {
                    break;
                }
                chunkCan.put(can[ci], req.cancelEventIdsBySession.get(can[ci]));
                ci++;
                room -= cost;
            }

            System.enqueueJob(
                new SessionCalendarInviteQueueable(
                    chunkBoth, chunkFac, chunkCan, req.suppressNotifications, req.patchOnly
                )
            );
        }

        return outOfSlots
            ? remainingFrom(
                new List<List<Id>>{ both, fac, can }, new List<Integer>{ bi, fi, ci })
            : new Set<Id>();
    }

    /**
     * @description Collects the ids each work list still had left when the transaction ran out of
     *          queueable slots, so they can be stamped Failed rather than vanish.
     * @param lists The work lists being drained.
     * @param cursors How far each list got, positionally matching lists.
     * @return Every id not yet enqueued.
     */
    private static Set<Id> remainingFrom(List<List<Id>> lists, List<Integer> cursors) {
        Set<Id> dropped = new Set<Id>();
        for (Integer li = 0; li < lists.size(); li++) {
            List<Id> ids = lists[li];
            for (Integer i = cursors[li]; i < ids.size(); i++) {
                dropped.add(ids[i]);
            }
        }
        return dropped;
    }

    /**
     * @description How many delete callouts one cancelled session costs — one per event copy.
     * @param req The work being chunked.
     * @param sessionId The cancelled session.
     * @return The number of callouts needed.
     */
    private static Integer cancelCost(PushRequest req, Id sessionId) {
        List<String> ids = req.cancelEventIdsBySession.get(sessionId);
        return (ids != null) ? ids.size() : 0;
    }

    /**
     * @description Records a Failed sync status on every session that could not be enqueued,
     *          so a partially-processed bulk operation is visible instead of silent. Writes with
     *          the re-entry guard raised so stamping the session cannot re-trigger this handler.
     * @param dropped The session ids that could not be enqueued.
     */
    private static void stampDropped(Set<Id> dropped) {
        if (dropped == null || dropped.isEmpty()) {
            return;
        }

        List<Session__c> toStamp = new List<Session__c>();
        for (Id sessionId : dropped) {
            toStamp.add(new Session__c(
                Id = sessionId,
                Calendar_Sync_Status__c = STATUS_FAILED,
                Calendar_Sync_Error__c  =
                    'Not sent to Google Calendar: the transaction ran out of queueable jobs. '
                    + 'Re-save or re-publish this session to retry.'
            ));
        }

        Boolean prior = suppressInvites;
        suppressInvites = true;
        try {
            Database.update(toStamp, false);
        } finally {
            suppressInvites = prior;
        }
    }
}
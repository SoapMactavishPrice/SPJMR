/**
 * @description Routes Session__c changes to the Google Calendar integration:
 *          creates a faculty-only event on Draft, patches it to add students on
 *          Publish/Republish, patches it on Rescheduled, and deletes it on Cancel.
 *
 *          Also exposes handleRelatedRecordChange() so that a change on a related
 *          record which feeds the event body or the guest list — Session_Division__c
 *          (division names appear in the summary and description), Session_Faculty__c
 *          (faculty ARE the guest list) and Session_Enrollment__c (students are the
 *          guest list) — re-pushes the existing Google event. That path is PATCH-only:
 *          it never creates an event for a session that was never synced.
 *
 * @note    Notification control: skipUserNotifications is a transaction-scoped flag set by
 *          the caller that performs the DML (see TimetableSessionController). When true the
 *          queueable uses sendUpdates=none so Google updates the event silently. Cancellation
 *          deliberately ignores it — a cancelled session must always notify its guests.
 *
 * @note    Google only emails a guest when the event genuinely changed for that guest.
 *          SessionCalendarInviteQueueable.buildEvent therefore includes the schedule state
 *          in the event description, so Draft -> Published is a real change and the faculty
 *          already on the event receive an "Updated invitation" rather than nothing.
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

    /** @description When true the Google push uses sendUpdates=none (no guest emails). */
    public static Boolean skipUserNotifications = false;

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
        private Set<Id> publishInviteIds = new Set<Id>();
        private Set<Id> draftInviteIds = new Set<Id>();
        private Map<Id, String> cancelEventIdsBySession = new Map<Id, String>();
        private Boolean suppressNotifications = false;
        private Boolean patchOnly = false;
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

        Set<Id> publishInviteIds = new Set<Id>();
        Set<Id> draftInviteIds   = new Set<Id>();
        Map<Id, String> cancelEventIdsBySession = new Map<Id, String>();

        for (Session__c s : newMap.values()) {
            Session__c oldRec = (oldMap != null) ? oldMap.get(s.Id) : null;
            String oldStatus  = (oldRec != null) ? oldRec.Schedule_Type__c : null;
            String newStatus  = s.Schedule_Type__c;
            Boolean hasEvent      = String.isNotBlank(s.Google_Event_Id__c);
            Boolean statusChanged = (newStatus != oldStatus);

            if (newStatus == STATUS_CANCELLED) {
                if (statusChanged && hasEvent) {
                    cancelEventIdsBySession.put(s.Id, s.Google_Event_Id__c);
                }
                continue;
            }

            if (UPDATE_ONLY.contains(newStatus)) {
                if (hasEvent && (statusChanged || detailsChanged(s, oldRec))) {
                    publishInviteIds.add(s.Id);
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
                    publishInviteIds.add(s.Id);
                } else {
                    draftInviteIds.add(s.Id);
                }
            }
        }

        PushRequest req = new PushRequest();
        req.publishInviteIds = publishInviteIds;
        req.draftInviteIds = draftInviteIds;
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

        Set<Id> publishInviteIds = new Set<Id>();
        Set<Id> draftInviteIds   = new Set<Id>();

        for (Session__c s : [
            SELECT Id, Schedule_Type__c, Google_Event_Id__c
            FROM   Session__c
            WHERE  Id IN :unseen
              AND  Google_Event_Id__c != NULL
        ]) {
            if (AUDIENCE_ALL.contains(s.Schedule_Type__c) || UPDATE_ONLY.contains(s.Schedule_Type__c)) {
                publishInviteIds.add(s.Id);
            } else if (AUDIENCE_FACULTY.contains(s.Schedule_Type__c)) {
                draftInviteIds.add(s.Id);
            }
        }

        PushRequest req = new PushRequest();
        req.publishInviteIds = publishInviteIds;
        req.draftInviteIds = draftInviteIds;
        req.suppressNotifications = skipUserNotifications;
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
        Map<Id, String> cancelEventIdsBySession = new Map<Id, String>();
        for (Session__c s : oldMap.values()) {
            if (String.isNotBlank(s.Google_Event_Id__c)) {
                cancelEventIdsBySession.put(s.Id, s.Google_Event_Id__c);
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
        Set<Id> pubSet = new Set<Id>(req.publishInviteIds);
        Set<Id> drfSet = new Set<Id>(req.draftInviteIds);
        pubSet.removeAll(alreadyEnqueued);
        drfSet.removeAll(alreadyEnqueued);

        if (pubSet.isEmpty() && drfSet.isEmpty() && req.cancelEventIdsBySession.isEmpty()) {
            return;
        }

        if (!GoogleCalendarHelper.isActive()) {
            return;
        }

        alreadyEnqueued.addAll(pubSet);
        alreadyEnqueued.addAll(drfSet);

        req.publishInviteIds = pubSet;
        req.draftInviteIds = drfSet;
        stampDropped(enqueueChunks(req));
    }

    /**
     * @description Fills queueables with up to MAX_CALLOUTS_PER_JOB sessions each until the work
     *          is exhausted or the transaction runs out of queueable slots.
     * @param req The deduped work being enqueued.
     * @return The session ids that could not be enqueued (empty when everything was sent).
     */
    private static Set<Id> enqueueChunks(PushRequest req) {
        List<Id> pub = new List<Id>(req.publishInviteIds);
        List<Id> drf = new List<Id>(req.draftInviteIds);
        List<Id> can = new List<Id>(req.cancelEventIdsBySession.keySet());

        Integer pi = 0;
        Integer di = 0;
        Integer ci = 0;
        Boolean outOfSlots = false;
        while (pi < pub.size() || di < drf.size() || ci < can.size()) {
            if (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs() <= 0) {
                outOfSlots = true;
                break;
            }

            Set<Id> chunkPub = new Set<Id>();
            Set<Id> chunkDrf = new Set<Id>();
            Map<Id, String> chunkCan = new Map<Id, String>();
            Integer room = MAX_CALLOUTS_PER_JOB;

            while (room > 0 && pi < pub.size()) { chunkPub.add(pub[pi]); pi++; room--; }
            while (room > 0 && di < drf.size()) { chunkDrf.add(drf[di]); di++; room--; }
            while (room > 0 && ci < can.size()) {
                Id cid = can[ci];
                chunkCan.put(cid, req.cancelEventIdsBySession.get(cid));
                ci++; room--;
            }

            System.enqueueJob(
                new SessionCalendarInviteQueueable(
                    chunkPub, chunkDrf, chunkCan, req.suppressNotifications, req.patchOnly
                )
            );
        }

        Set<Id> dropped = new Set<Id>();
        if (outOfSlots) {
            for (Integer i = pi; i < pub.size(); i++) { dropped.add(pub[i]); }
            for (Integer i = di; i < drf.size(); i++) { dropped.add(drf[i]); }
            for (Integer i = ci; i < can.size(); i++) { dropped.add(can[i]); }
        }
        return dropped;
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
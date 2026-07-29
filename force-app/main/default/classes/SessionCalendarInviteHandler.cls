/**
 * @description SE-1056 — decide, on Session changes, which Google Calendar action to
 *          take and for whom, then hand the callouts to
 *          SessionCalendarInviteQueueable (Database.AllowsCallouts).
 *
 *          Audience (SE-1056, per Ankur Malik's clarification):
 *            - Schedule_Type__c → 'Draft'                  → invite FACULTY only.
 *            - Schedule_Type__c → 'Published'/'Republished'→ invite STUDENTS + faculty.
 *          Update (SE-1047 §5):
 *            - A synced session (has Google_Event_Id__c) whose mapped details change,
 *              or a 'Rescheduled' session, is re-sent → the queueable PATCHes the event.
 *          Cancel (SE-1047 §5, decision D3):
 *            - Schedule_Type__c → 'Cancelled', or the Session is deleted, with a
 *              populated Google_Event_Id__c → the queueable DELETEs the event.
 *
 *          Wire-up: SessionTrigger (after insert, after update, after delete).
 */
// complexity suppressed: working integration logic, refactor out of scope
@SuppressWarnings('PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity,PMD.CognitiveComplexity,PMD.NcssMethodCount')
public class SessionCalendarInviteHandler {

    // Statuses that create/update an event and their audience.
    private static final Set<String> AUDIENCE_ALL     = new Set<String>{ 'Published', 'Republished' };
    private static final Set<String> AUDIENCE_FACULTY = new Set<String>{ 'Draft' };
    // Statuses that only update an already-synced event (never create one).
    private static final Set<String> UPDATE_ONLY      = new Set<String>{ 'Rescheduled' };
    private static final String STATUS_CANCELLED      = 'Cancelled';

    // Apex allows 100 callouts per transaction. Each synced session can cost up to
    // three callouts: auth token + (on PATCH) a GET to read existing attendee RSVPs +
    // the POST/PATCH itself. Chunk well below the limit so a busy publish can't exceed it.
    private static final Integer MAX_CALLOUTS_PER_JOB = 30;

    /** Set by the queueable around its write-back DML to prevent trigger re-entry. */
    public static Boolean suppressInvites = false;

    /**
     * @description Decide and enqueue the Google Calendar action(s) for changed Sessions.
     * @param newMap Trigger.newMap (Session__c)
     * @param oldMap Trigger.oldMap (null on insert)
     */
    public static void handleSessionCalendarInvites(
        Map<Id, Session__c> newMap,
        Map<Id, Session__c> oldMap
    ) {
        if (suppressInvites || newMap == null || newMap.isEmpty()) {
            return;
        }

        Set<Id> publishInviteIds = new Set<Id>(); // students + faculty (create/update)
        Set<Id> draftInviteIds   = new Set<Id>(); // faculty only       (create/update)
        Map<Id, String> cancelEventIdsBySession = new Map<Id, String>(); // → DELETE

        for (Session__c s : newMap.values()) {
            Session__c oldRec = (oldMap != null) ? oldMap.get(s.Id) : null;
            String oldStatus  = (oldRec != null) ? oldRec.Schedule_Type__c : null;
            String newStatus  = s.Schedule_Type__c;
            Boolean hasEvent      = String.isNotBlank(s.Google_Event_Id__c);
            Boolean statusChanged = (newStatus != oldStatus);

            // CANCEL — became Cancelled and there's an event to remove.
            if (newStatus == STATUS_CANCELLED) {
                if (statusChanged && hasEvent) {
                    cancelEventIdsBySession.put(s.Id, s.Google_Event_Id__c);
                }
                continue;
            }

            // UPDATE-ONLY (e.g. Rescheduled) — PATCH an existing event, never create.
            if (UPDATE_ONLY.contains(newStatus)) {
                if (hasEvent && (statusChanged || detailsChanged(s, oldRec))) {
                    publishInviteIds.add(s.Id);
                }
                continue;
            }

            // CREATE or UPDATE — entering an audience status, or editing a synced one.
            Boolean isAll     = AUDIENCE_ALL.contains(newStatus);
            Boolean isFaculty = AUDIENCE_FACULTY.contains(newStatus);
            if (!isAll && !isFaculty) {
                continue; // Scheduled / Complete / etc. — not synced.
            }
            if (statusChanged || (hasEvent && detailsChanged(s, oldRec))) {
                if (isAll) {
                    publishInviteIds.add(s.Id);
                } else {
                    draftInviteIds.add(s.Id);
                }
            }
        }

        enqueueWork(publishInviteIds, draftInviteIds, cancelEventIdsBySession);
    }

    /**
     * @description Cancel Google events for deleted Sessions (decision D3).
     * @param oldMap Trigger.oldMap on after delete.
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
        enqueueWork(new Set<Id>(), new Set<Id>(), cancelEventIdsBySession);
    }

    /**
     * @description True if any SE-1057 mapped source field differs between new and old.
     * @param s the new Session record
     * @param oldRec the prior version of the Session record
     * @return true when a mapped field changed
     */
    private static Boolean detailsChanged(Session__c s, Session__c oldRec) {
        if (oldRec == null) {
            return false;
        }
        return s.Start_Time__c     != oldRec.Start_Time__c
            || s.End_Time__c       != oldRec.End_Time__c
            || s.Class_Room__c     != oldRec.Class_Room__c
            || s.URL__c            != oldRec.URL__c
            || s.Description__c     != oldRec.Description__c
            || s.Course_Activity__c != oldRec.Course_Activity__c
            || s.Session_Type__c   != oldRec.Session_Type__c
            || s.Remark__c         != oldRec.Remark__c
            || s.Course__c         != oldRec.Course__c;
    }

    /**
     * @description Enqueue the work, chunked so no single queueable exceeds
     *              MAX_CALLOUTS_PER_JOB callouts, and only while async slots remain.
     * @param publishInviteIds session ids that need a published invite
     * @param draftInviteIds session ids that need a draft invite
     * @param cancelEventIdsBySession map of session id to Google event id to cancel
     */
    private static void enqueueWork(
        Set<Id> publishInviteIds,
        Set<Id> draftInviteIds,
        Map<Id, String> cancelEventIdsBySession
    ) {
        if (publishInviteIds.isEmpty() && draftInviteIds.isEmpty()
            && cancelEventIdsBySession.isEmpty()) {
            return;
        }

        // Honour the Active__c master switch: when the integration is turned off
        // (or not configured) don't burn async slots only to fail in the queueable.
        if (!GoogleCalendarHelper.isActive()) {
            return;
        }

        List<Id> pub = new List<Id>(publishInviteIds);
        List<Id> drf = new List<Id>(draftInviteIds);
        List<Id> can = new List<Id>(cancelEventIdsBySession.keySet());

        Integer pi = 0, di = 0, ci = 0;
        while (pi < pub.size() || di < drf.size() || ci < can.size()) {
            if (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs() <= 0) {
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
                chunkCan.put(cid, cancelEventIdsBySession.get(cid));
                ci++; room--;
            }

            System.enqueueJob(
                new SessionCalendarInviteQueueable(chunkPub, chunkDrf, chunkCan)
            );
        }
    }
}
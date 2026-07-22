/**
 * @description Decides, on Calendar_Meeting__c changes, which Google Calendar action to
 *          take for a student-scheduled meeting, then hands the callouts to
 *          CalendarMeetingInviteQueueable. Sibling of SessionCalendarInviteHandler.
 *
 *          Scope guard: ONLY meetings with Source__c = 'Salesforce' are pushed. Meetings
 *          with Source__c = 'Google' are inbound-ingested copies (GoogleCalendarInboundService)
 *          and must never be pushed back out — that would create an echo loop.
 *
 *          Actions:
 *            - Scheduled + no Google_Event_Id__c (or re-scheduled) → CREATE (POST).
 *            - Scheduled + has Google_Event_Id__c + mapped details changed → UPDATE (PATCH).
 *            - Cancelled (or record deleted) + has Google_Event_Id__c → CANCEL (DELETE).
 *
 *          Wire-up: CalendarMeetingTrigger (after insert, after update, after delete).
 */
// complexity suppressed: working integration logic mirrored from SessionCalendarInviteHandler.
// OperationWithLimitsInLoop suppressed: the enqueue loop is a DELIBERATE chunking of work
// across queueables (each job caps its own callouts), bounded by the async-slot check.
@SuppressWarnings('PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity,PMD.CognitiveComplexity,PMD.NcssMethodCount,PMD.OperationWithLimitsInLoop')
public with sharing class CalendarMeetingInviteHandler {

    private static final String SOURCE_SALESFORCE = 'Salesforce';
    private static final String STATUS_SCHEDULED  = 'Scheduled';
    private static final String STATUS_CANCELLED  = 'Cancelled';

    // Google Calendar allows ~100 callouts per queueable; chunk below that.
    private static final Integer MAX_CALLOUTS_PER_JOB = 90;

    /** Set by the queueable around its write-back DML to prevent trigger re-entry. */
    public static Boolean suppressInvites = false;

    /**
     * @description Accumulates the classified work for a batch of changed meetings:
     *          ids to create/update, and meeting-id → Google-event-id pairs to cancel.
     */
    private class Work {
        Set<Id> createOrUpdateIds = new Set<Id>();
        Map<Id, String> cancelEventIdsByMeeting = new Map<Id, String>();
    }

    /**
     * @description Decide and enqueue the Google Calendar action(s) for changed meetings.
     * @param newMap Trigger.newMap (Calendar_Meeting__c).
     * @param oldMap Trigger.oldMap (null on insert).
     */
    public static void handleCalendarMeetingInvites(
        Map<Id, Calendar_Meeting__c> newMap,
        Map<Id, Calendar_Meeting__c> oldMap
    ) {
        if (suppressInvites || newMap == null || newMap.isEmpty()) {
            return;
        }

        Work work = new Work();
        for (Calendar_Meeting__c m : newMap.values()) {
            if (!SOURCE_SALESFORCE.equals(m.Source__c)) {
                continue; // never push inbound (Google-originated) meetings
            }
            Calendar_Meeting__c oldRec = (oldMap != null) ? oldMap.get(m.Id) : null;
            classify(m, oldRec, work);
        }

        enqueueWork(work.createOrUpdateIds, work.cancelEventIdsByMeeting);
    }

    /**
     * @description Classifies one meeting into create/update or cancel.
     * @param m The new meeting record.
     * @param oldRec The prior version (null on insert).
     * @param work The accumulator of create/update ids and cancellations.
     */
    private static void classify(Calendar_Meeting__c m, Calendar_Meeting__c oldRec, Work work) {
        String oldStatus = (oldRec != null) ? oldRec.Meeting_Status__c : null;
        String newStatus = m.Meeting_Status__c;
        Boolean hasEvent = String.isNotBlank(m.Google_Event_Id__c);
        Boolean statusChanged = (newStatus != oldStatus);

        if (STATUS_CANCELLED.equals(newStatus)) {
            if (statusChanged && hasEvent) {
                work.cancelEventIdsByMeeting.put(m.Id, m.Google_Event_Id__c);
            }
            return;
        }

        if (STATUS_SCHEDULED.equals(newStatus)) {
            Boolean isNewOrRescheduled = (oldRec == null) || statusChanged;
            if (isNewOrRescheduled || (hasEvent && detailsChanged(m, oldRec))) {
                work.createOrUpdateIds.add(m.Id);
            }
        }
    }

    /**
     * @description Cancel Google events for deleted meetings.
     * @param oldMap Trigger.oldMap on after delete.
     */
    public static void handleCalendarMeetingDeletes(Map<Id, Calendar_Meeting__c> oldMap) {
        if (suppressInvites || oldMap == null || oldMap.isEmpty()) {
            return;
        }
        Map<Id, String> cancelEventIdsByMeeting = new Map<Id, String>();
        for (Calendar_Meeting__c m : oldMap.values()) {
            if (SOURCE_SALESFORCE.equals(m.Source__c) && String.isNotBlank(m.Google_Event_Id__c)) {
                cancelEventIdsByMeeting.put(m.Id, m.Google_Event_Id__c);
            }
        }
        enqueueWork(new Set<Id>(), cancelEventIdsByMeeting);
    }

    /**
     * @description True if any mapped source field differs between new and old.
     * @param m The new meeting record.
     * @param oldRec The prior version of the meeting.
     * @return True when a mapped field changed.
     */
    private static Boolean detailsChanged(Calendar_Meeting__c m, Calendar_Meeting__c oldRec) {
        if (oldRec == null) {
            return false;
        }
        return m.Subject__c        != oldRec.Subject__c
            || m.Start_Time__c     != oldRec.Start_Time__c
            || m.End_Time__c       != oldRec.End_Time__c
            || m.Location__c       != oldRec.Location__c
            || m.Meeting_Link__c   != oldRec.Meeting_Link__c
            || m.Description__c     != oldRec.Description__c
            || m.Attendee_Emails__c != oldRec.Attendee_Emails__c;
    }

    /**
     * @description Enqueue the work, chunked so no single queueable exceeds
     *          MAX_CALLOUTS_PER_JOB callouts, and only while async slots remain.
     * @param createOrUpdateIds Meeting ids that need a create/update push.
     * @param cancelEventIdsByMeeting Map of meeting id to Google event id to cancel.
     */
    private static void enqueueWork(
        Set<Id> createOrUpdateIds,
        Map<Id, String> cancelEventIdsByMeeting
    ) {
        if (createOrUpdateIds.isEmpty() && cancelEventIdsByMeeting.isEmpty()) {
            return;
        }
        // Honour the master switch: when the integration is off, don't burn async slots.
        if (!GoogleCalendarHelper.isActive()) {
            return;
        }

        List<Id> cou = new List<Id>(createOrUpdateIds);
        List<Id> can = new List<Id>(cancelEventIdsByMeeting.keySet());

        Integer ci = 0;
        Integer di = 0;
        while (ci < cou.size() || di < can.size()) {
            if (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs() <= 0) {
                break;
            }
            Set<Id> chunkCou = new Set<Id>();
            Map<Id, String> chunkCan = new Map<Id, String>();
            Integer room = MAX_CALLOUTS_PER_JOB;

            while (room > 0 && ci < cou.size()) {
                chunkCou.add(cou[ci]); ci++; room--;
            }
            while (room > 0 && di < can.size()) {
                Id mid = can[di];
                chunkCan.put(mid, cancelEventIdsByMeeting.get(mid));
                di++; room--;
            }
            System.enqueueJob(new CalendarMeetingInviteQueueable(chunkCou, chunkCan));
        }
    }
}
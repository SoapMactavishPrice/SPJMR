@SuppressWarnings('PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity,PMD.CognitiveComplexity,PMD.NcssMethodCount')
public class SessionCalendarInviteHandler {

    private static final Set<String> AUDIENCE_ALL     = new Set<String>{ 'Published', 'Republished' };
    private static final Set<String> AUDIENCE_FACULTY = new Set<String>{ 'Draft' };

    private static final Set<String> UPDATE_ONLY      = new Set<String>{ 'Rescheduled' };
    private static final String STATUS_CANCELLED      = 'Cancelled';

    private static final Integer MAX_CALLOUTS_PER_JOB = 30;

    public static Boolean suppressInvites = false;

    public static Boolean skipUserNotifications = false;

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

        enqueueWork(publishInviteIds, draftInviteIds, cancelEventIdsBySession, suppressNotifications);
    }

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

        enqueueWork(new Set<Id>(), new Set<Id>(), cancelEventIdsBySession, false);
    }

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

    private static void enqueueWork(
        Set<Id> publishInviteIds,
        Set<Id> draftInviteIds,
        Map<Id, String> cancelEventIdsBySession,
        Boolean suppressNotifications
    ) {
        if (publishInviteIds.isEmpty() && draftInviteIds.isEmpty()
            && cancelEventIdsBySession.isEmpty()) {
            return;
        }

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
                new SessionCalendarInviteQueueable(chunkPub, chunkDrf, chunkCan, suppressNotifications)
            );
        }
    }
}
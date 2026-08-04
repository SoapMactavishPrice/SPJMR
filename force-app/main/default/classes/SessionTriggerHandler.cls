public class SessionTriggerHandler {

    public static void handleSessionDateChanges(
        Map<Id, Session__c> newMap,
        Map<Id, Session__c> oldMap
    ) {
        if (newMap == null || newMap.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Set<Id> rescheduledSessionIds = new Set<Id>();
        for (Session__c sess : newMap.values()) {
            Session__c oldRec = oldMap.get(sess.Id);
            if (oldRec == null) {
                continue;
            }
            if (sess.Start_Time__c != oldRec.Start_Time__c
                || sess.End_Time__c != oldRec.End_Time__c) {
                rescheduledSessionIds.add(sess.Id);
            }
        }

        if (rescheduledSessionIds.isEmpty()) {
            return;
        }
        MissedSessionSyncService.resyncForSessions(rescheduledSessionIds);
    }

    public static void handleScheduleTypePublished(
        Map<Id, Session__c> newMap,
        Map<Id, Session__c> oldMap
    ) {
        Set<Id> publishedSessionIds = new Set<Id>();

        for (Id sessionId : newMap.keySet()) {
            Session__c newSession = newMap.get(sessionId);
            Session__c oldSession = oldMap.get(sessionId);

            if (
                newSession.Schedule_Type__c == 'Published' &&
                oldSession.Schedule_Type__c != 'Published'
            ) {
                publishedSessionIds.add(sessionId);
            }
        }

        if (publishedSessionIds.isEmpty()) return;

 if (!publishedSessionIds.isEmpty()) {
        try {
            System.enqueueJob(
                new SessionPortalNotificationQueueable(publishedSessionIds)
            );
        } catch (Exception e) {
            System.debug('Failed to enqueue notification job: ' + e.getMessage());
        }
    }
}

    public static void handleMakeUpExamNotification(
    Set<Id> publishedSessionIds,
    Map<Id, Session__c> newMap
) {

    Set<Id> makeUpSessionIds = new Set<Id>();
    for (Id sessionId : publishedSessionIds) {
        Session__c session = newMap.get(sessionId);
        if (session.Course_Activity__c == 'Make Up Exam') {
            makeUpSessionIds.add(sessionId);
        }
    }

    if (makeUpSessionIds.isEmpty()) return;

    List<Session_Enrollment__c> makeUpEnrollments = [
        SELECT Session__c,
               Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccountId
        FROM Session_Enrollment__c
        WHERE Session__c IN :makeUpSessionIds
    ];

    if (makeUpEnrollments.isEmpty()) return;

    Map<Id, Set<Id>> sessionToMakeUpLearners = new Map<Id, Set<Id>>();
    for (Session_Enrollment__c enr : makeUpEnrollments) {
        Id learnerId = enr.Division_Enrollment__r
                         .Academic_Term_Enrollment__r
                         .LearnerAccountId;
        if (learnerId == null) continue;
        if (!sessionToMakeUpLearners.containsKey(enr.Session__c)) {
            sessionToMakeUpLearners.put(enr.Session__c, new Set<Id>());
        }
        sessionToMakeUpLearners.get(enr.Session__c).add(learnerId);
    }

    List<Portal_Notification__c> makeUpNotifs = new List<Portal_Notification__c>();
    for (Id sessionId : sessionToMakeUpLearners.keySet()) {
        Session__c session = newMap.get(sessionId);
        for (Id learnerId : sessionToMakeUpLearners.get(sessionId)) {
            makeUpNotifs.add(new Portal_Notification__c(
                Title__c             = 'Make Up Exam Scheduled',
                Body__c              = 'A Make Up Exam "' + session.Name + '" has been scheduled for you.',
                Recipient_Account__c = learnerId,
                Is_Read__c           = false,
                Session__c           = sessionId
            ));
        }
    }

    if (!makeUpNotifs.isEmpty()) {
        insert makeUpNotifs;
    }
}

public static void handleSessionCount(
        List<Session__c> newList,
        List<Session__c> oldList,
        Boolean isInsert,
        Boolean isUpdate,
        Boolean isDelete,
        Boolean isUndelete
    ) {

        Set<Id> courseIds = new Set<Id>();

        if (isInsert || isUpdate || isUndelete) {

            for (Session__c ses : newList) {
                if (ses.Course__c != null) {
                    courseIds.add(ses.Course__c);
                }
            }
        }

        if (isUpdate || isDelete) {

            for (Session__c ses : oldList) {
                if (ses.Course__c != null) {
                    courseIds.add(ses.Course__c);
                }
            }
        }

        if (!courseIds.isEmpty()) {
            updateSessionCount(courseIds);
        }
    }

public static void updateSessionCount(Set<Id> courseIds) {

        Map<Id, Integer> courseSessionCountMap = new Map<Id, Integer>();

        for (AggregateResult ar : [

            SELECT Course__c courseId, COUNT(Id) totalCount
            FROM Session__c
            WHERE Course__c IN :courseIds
            GROUP BY Course__c

        ]) {

            courseSessionCountMap.put(
                (Id) ar.get('courseId'),
                (Integer) ar.get('totalCount')
            );
        }

        List<LearningCourse> coursesToUpdate = new List<LearningCourse>();

        for (Id courseId : courseIds) {

            Integer countValue = 0;

            if (courseSessionCountMap.containsKey(courseId)) {
                countValue = courseSessionCountMap.get(courseId);
            }

            coursesToUpdate.add(
                new LearningCourse(
                    Id = courseId,
                    Session_Count__c = countValue
                )
            );
        }

        if (!coursesToUpdate.isEmpty()) {
            update coursesToUpdate;
        }
    }

  public static void updateSessionCountInProgrameCourse(
        List<Session__c> sessions,
        Map<Id, Session__c> sessionMap
    ) {

        Set<Id> batchIds = new Set<Id>();
        Set<Id> courseIds = new Set<Id>();

        for(Session__c s : sessions){
            if(s.Batch__c != null && s.Course__c != null){
                batchIds.add(s.Batch__c);
                courseIds.add(s.Course__c);
            }
        }

        List<Program_Courses__c> pcs = [
            SELECT Id, Batch__c, Learning_Course__c, Count_of_Sessions__c
            FROM Program_Courses__c
            WHERE Batch__c IN :batchIds
            AND Learning_Course__c IN :courseIds
        ];

        Map<String, Integer> countMap = new Map<String, Integer>();

        for(AggregateResult ar : [
            SELECT Batch__c batchId,
                   Course__c courseId,
                   COUNT(Id) total
            FROM Session__c
            WHERE Batch__c IN :batchIds
            AND Course__c IN :courseIds
            GROUP BY Batch__c, Course__c
        ]){
            String key = ar.get('batchId') + '-' + ar.get('courseId');
            countMap.put(key, (Integer)ar.get('total'));
        }

        List<Program_Courses__c> updates = new List<Program_Courses__c>();

        for(Program_Courses__c pc : pcs){
            String key = pc.Batch__c + '-' + pc.Learning_Course__c;

            pc.Count_of_Sessions__c =
                countMap.containsKey(key)
                ? countMap.get(key)
                : 0;

            updates.add(pc);
        }

        if(!updates.isEmpty()){
            update updates;
        }
    }

}
/**
 * @description Handler class for Session Trigger
 *              to update Session Count on related Courses.
 *              testing testing
 */
public class SessionTriggerHandler {

    public static void handleScheduleTypePublished(
        Map<Id, Session__c> newMap,
        Map<Id, Session__c> oldMap
    ) {
        Set<Id> publishedSessionIds = new Set<Id>();

        // Step 1: Detect sessions changed to "Published"
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

        // Step 2: Get Learner Accounts
        List<Session_Enrollment__c> enrollments = [
            SELECT Session__c,
                   Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccountId
            FROM Session_Enrollment__c
            WHERE Session__c IN :publishedSessionIds AND Session__r.Course_Activity__c != 'Make Up Exam'
        ];

        if (enrollments.isEmpty()) return;

        // Step 3: Map Session → Learner Accounts
        Map<Id, Set<Id>> sessionToLearnerIds = new Map<Id, Set<Id>>();

        for (Session_Enrollment__c enr : enrollments) {
            Id learnerId = enr.Division_Enrollment__r
                             .Academic_Term_Enrollment__r
                             .LearnerAccountId;

            if (learnerId == null) continue;

            if (!sessionToLearnerIds.containsKey(enr.Session__c)) {
                sessionToLearnerIds.put(enr.Session__c, new Set<Id>());
            }

            sessionToLearnerIds.get(enr.Session__c).add(learnerId);
        }

        // Step 4: Create Portal Notifications
        List<Portal_Notification__c> portalNotifs = new List<Portal_Notification__c>();

        for (Id sessionId : sessionToLearnerIds.keySet()) {
            Session__c session = newMap.get(sessionId);

            for (Id learnerId : sessionToLearnerIds.get(sessionId)) {

                portalNotifs.add(new Portal_Notification__c(
                    Title__c             = 'Session Now Available',
                    Body__c              = 'The session "' + session.Name + '" is now published.',
                    Recipient_Account__c = learnerId,
                    Is_Read__c           = false,
                    Session__c           = sessionId
                ));
            }
        }

        // Step 5: Insert in bulk
        if (!portalNotifs.isEmpty()) {
            insert portalNotifs;
        }
        handleMakeUpExamNotification(publishedSessionIds, newMap);
    }
 //SE-520   
    public static void handleMakeUpExamNotification(
    Set<Id> publishedSessionIds,
    Map<Id, Session__c> newMap
) {
    // Only process Make Up Exam sessions
    Set<Id> makeUpSessionIds = new Set<Id>();
    for (Id sessionId : publishedSessionIds) {
        Session__c session = newMap.get(sessionId);
        if (session.Course_Activity__c == 'Make Up Exam') {
            makeUpSessionIds.add(sessionId);
        }
    }

    if (makeUpSessionIds.isEmpty()) return;

    // Get only selected students for Make Up Exam sessions
    List<Session_Enrollment__c> makeUpEnrollments = [
        SELECT Session__c,
               Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccountId
        FROM Session_Enrollment__c
        WHERE Session__c IN :makeUpSessionIds
    ];

    if (makeUpEnrollments.isEmpty()) return;

    // Map Session → Selected Learner Accounts
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

    // Create Portal Notifications for Make Up Exam students
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
} //SE-502
/**
 * @description Collects Course IDs from Session records during
 *              insert, update, delete, and undelete events and
 *              updates the related course session counts.
 */
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
/**
 * @description Updates the Session_Count__c field on related LearningCourse records
 *              based on the total number of Session__c records associated with each course.
 *
 * @param courseIds Set of Course record IDs for which the session count needs to be recalculated.
 */
public static void updateSessionCount(Set<Id> courseIds) {

        // Store counts
        Map<Id, Integer> courseSessionCountMap = new Map<Id, Integer>();

        // Aggregate Query
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

        // Update all related courses
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

        // Query Program Courses
        List<Program_Courses__c> pcs = [
            SELECT Id, Batch__c, Learning_Course__c, Count_of_Sessions__c
            FROM Program_Courses__c
            WHERE Batch__c IN :batchIds
            AND Learning_Course__c IN :courseIds
        ];

        // Aggregate Session Counts
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
    
/**   public static void sendPublishedSessionEmails(
    Map<Id, Session__c> newMap,
    Map<Id, Session__c> oldMap
) {

    Set<Id> publishedSessionIds = new Set<Id>();

    // Identify sessions changed to Published
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

    if (publishedSessionIds.isEmpty()) {
        return;
    }

    Map<Id, Session__c> sessionMap = new Map<Id, Session__c>([
        SELECT Id,
               Name,
               Session_Date__c,
               Term__r.Term_Start_Date__c
        FROM Session__c
        WHERE Id IN :publishedSessionIds
    ]);

    // Get student emails
    List<Session_Enrollment__c> enrollments = [
        SELECT Session__c,
               Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail
        FROM Session_Enrollment__c
        WHERE Session__c IN :publishedSessionIds
    ];

    List<Messaging.SingleEmailMessage> emails =
        new List<Messaging.SingleEmailMessage>();

    for (Session_Enrollment__c enr : enrollments) {

        String email =
            enr.Division_Enrollment__r
               .Academic_Term_Enrollment__r
               .LearnerAccount
               .PersonEmail;

        if (String.isBlank(email)) {
            continue;
        }

        Session__c session = sessionMap.get(enr.Session__c);

        // Calculate week range
        Integer dayOfWeek = session.Session_Date__c.toStartOfWeek().daysBetween(session.Session_Date__c);

        Date fromDate = session.Session_Date__c.addDays(-dayOfWeek + 1);

        Date toDate = fromDate.addDays(6);

        String formattedFromDate = (fromDate.day() < 10 ? '0' : '') + fromDate.day() + '-' +
            					  (fromDate.month() < 10 ? '0' : '') + fromDate.month() + '-' +
            					  String.valueOf(fromDate.year()).substring(2);

        String formattedToDate = (toDate.day() < 10 ? '0' : '') + toDate.day() + '-' +
            					 (toDate.month() < 10 ? '0' : '') + toDate.month() + '-' +
            					 String.valueOf(toDate.year()).substring(2);
        
	   	String htmlBody = '<!DOCTYPE html>' +
						  '<html>' +
						  '<body style="margin:0;padding:30px;background:#f5f5f5;font-family:Arial,Helvetica,sans-serif;">' +
						  '<table align="center" width="650" cellpadding="0" cellspacing="0" ' +
						  'style="background:#ffffff;border:1px solid #dddddd;border-radius:8px;padding:35px;">' +'<tr>' +
						  '<td>' +
           
           				  '<h2 style="' +
						  'color:#5E2A84;' +
						  'border-bottom:3px solid #5E2A84;' +
						  'padding-bottom:10px;' +
						  'margin-top:0;' +
						  'margin-bottom:25px;' +
						  'font-size:24px;' +
						  'font-weight:600;">' +
						  'Weekly Schedule Published' +
						  '</h2>' +
           
						  '<p style="font-size:14px;color:#333;line-height:1.8;margin:0 0 18px 0;">' +
						  'Dear Participant,' +
                          '</p>' +
           
						  '<p style="font-size:14px;color:#444;line-height:1.8;margin:0 0 18px 0;">' +
						  'Sessions have been scheduled from <strong>' +
						  formattedFromDate +'</strong> to <strong>' +
						  formattedToDate +'</strong>.' +
						  '</p>' +

						  '<p style="font-size:14px;color:#444;line-height:1.8;margin:0 0 30px 0;">' +
						  'Please log in to the portal to view your weekly schedule.' +
						  '</p>' +

						  '<p style="font-size:14px;color:#333;line-height:1.6;margin:0;">' +
						  'Regards,<br/>' +
						  '<strong>' + UserInfo.getName() + '</strong>' +
						  '</p>' +

						  '<hr style="border:none;border-top:1px solid #e0e0e0;margin:35px 0 15px 0;">' +

						  '<p style="font-size:12px;color:#777;text-align:center;margin:0;">' +
						  'This is a system-generated email. Please do not reply.' +
						  '</p>' +
           
           				  '</td>' +
						  '</tr>' +
						  '</table>' +
						  '</body>' +
           				  '</html>';
       

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

        mail.setToAddresses(new List<String>{ email });
        mail.setSubject('Weekly Schedule Published');
        mail.setHtmlBody(htmlBody);

        emails.add(mail);
    }

    	// Send all emails
    	if (!emails.isEmpty()) {
        Messaging.sendEmail(emails, false);
    	}
 	}*/
}

// public class SessionTriggerHandler {

//     public static void handleScheduleTypePublished(
//         Map<Id, Session__c> newMap,
//         Map<Id, Session__c> oldMap
//     ) {
//         // Step 1: Collect Session IDs where Schedule_Type__c just changed to "Published"
//         Set<Id> publishedSessionIds = new Set<Id>();

//         for (Id sessionId : newMap.keySet()) {
//             Session__c newSession = newMap.get(sessionId);
//             Session__c oldSession = oldMap.get(sessionId);

//             if (
//                 newSession.Schedule_Type__c == 'Published' &&
//                 oldSession.Schedule_Type__c != 'Published'
//             ) {
//                 publishedSessionIds.add(sessionId);
//             }
//         }

//         if (publishedSessionIds.isEmpty()) return;

//         // Step 2: Query Session Enrollments to get Learner Account IDs
//         List<Session_Enrollment__c> enrollments = [
//             SELECT
//                 Id,
//                 Name,
//                 Session__r.Name,
//                 Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.Name,
//                 Session__r.Schedule_Type__c,
//                 Session__c,
//                 Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccountId
//             FROM Session_Enrollment__c
//             WHERE Session__c IN :publishedSessionIds
//         ];

//         if (enrollments.isEmpty()) return;

//         // Step 3: Build a map of Session ID → Set of Learner Account IDs
//         Map<Id, Set<Id>> sessionToLearnerIds = new Map<Id, Set<Id>>();

//         for (Session_Enrollment__c enr : enrollments) {
//             Id learnerId = enr.Division_Enrollment__r
//                              .Academic_Term_Enrollment__r
//                              .LearnerAccountId;

//             if (learnerId == null) continue;

//             if (!sessionToLearnerIds.containsKey(enr.Session__c)) {
//                 sessionToLearnerIds.put(enr.Session__c, new Set<Id>());
//             }
//             sessionToLearnerIds.get(enr.Session__c).add(learnerId);
//         }

//         // Step 4: Fetch the Custom Notification Type
//         CustomNotificationType notifType;
//         try {
//             notifType = [
//                 SELECT Id, DeveloperName
//                 FROM CustomNotificationType
//                 WHERE DeveloperName = 'Portal_User_Notification'
//                 LIMIT 1
//             ];
//         } catch (QueryException e) {
//             System.debug('Custom Notification Type not found: ' + e.getMessage());
//             return;
//         }

//         // Step 5: Send one notification per session to its enrolled learners
//         for (Id sessionId : sessionToLearnerIds.keySet()) {
//             Set<Id> learnerIds = sessionToLearnerIds.get(sessionId);

//             if (learnerIds.isEmpty()) continue;

//             Session__c session = newMap.get(sessionId);

//             Messaging.CustomNotification notification = new Messaging.CustomNotification();
//             notification.setNotificationTypeId(notifType.Id);
//             notification.setTitle('Session Now Available');
//             notification.setBody(
//                 'The session "' + session.Name + '" has been published and is now available.'
//             );

//             // Target page — links user to the session record when tapped
//             notification.setTargetPageRef(
//                 '{"type":"standard__recordPage","attributes":{"recordId":"' +
//                 sessionId +
//                 '","actionName":"view"}}'
//             );

//             // Convert Set<Id> to Set<String> — required by send()
//             Set<String> recipientIds = new Set<String>();
//             for (Id learnerId : learnerIds) {
//                 recipientIds.add(String.valueOf(learnerId));
//             }

//             try {
//                 notification.send(recipientIds);
//             } catch (Exception e) {
//                 System.debug('Notification send failed for session ' + sessionId + ': ' + e.getMessage());
//             }
//         }

//         // Step 6: Insert Portal_Notification__c records so the portal LWC bell can display them
//         List<Portal_Notification__c> portalNotifs = new List<Portal_Notification__c>();
//         for (Id sessionId : sessionToLearnerIds.keySet()) {
//             Session__c session = newMap.get(sessionId);
//             for (Id learnerId : sessionToLearnerIds.get(sessionId)) {
//                 portalNotifs.add(new Portal_Notification__c(
//                     Title__c              = 'Session Now Available',
//                     Body__c               = 'The session "' + session.Name + '" has been published and is now available.',
//                     Recipient_Account__c  = learnerId,
//                     Is_Read__c            = false,
//                     Session__c            = sessionId
//                 ));
//             }
//         }
//         if (!portalNotifs.isEmpty()) {
//             try {
//                 insert portalNotifs;
//             } catch (Exception e) {
//                 System.debug('Portal_Notification__c insert failed: ' + e.getMessage());
//             }
//         }
//     }
// }
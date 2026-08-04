public class SessionPortalNotificationQueueable implements Queueable {

    private Set<Id> publishedSessionIds;

    public SessionPortalNotificationQueueable(Set<Id> publishedSessionIds) {
        this.publishedSessionIds = publishedSessionIds;
    }

    public void execute(QueueableContext context) {

        // Query Sessions
        Map<Id, Session__c> sessionMap = new Map<Id, Session__c>([
            SELECT Id,
                   Name,
                   Course_Activity__c
            FROM Session__c
            WHERE Id IN :publishedSessionIds
        ]);
        
  System.debug('Session Count: ' + sessionMap.size());
        
        // Query Enrollments
        List<Session_Enrollment__c> enrollments = [
            SELECT Session__c,
                   Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccountId
            FROM Session_Enrollment__c
            WHERE Session__c IN :publishedSessionIds
        ];
System.debug('Enrollment Count: ' + enrollments.size());
        if (enrollments.isEmpty()) {
            return;
        }

        Map<Id, Set<Id>> sessionToLearnerIds = new Map<Id, Set<Id>>();

        for (Session_Enrollment__c enr : enrollments) {

            Session__c session = sessionMap.get(enr.Session__c);

      /*      // Skip Make Up Exam sessions
            if (session == null || session.Course_Activity__c == 'Make Up Exam') {
                continue;
            }*/
            
            if (session == null) {
    continue;
}

            Id learnerId = enr.Division_Enrollment__r
                .Academic_Term_Enrollment__r
                .LearnerAccountId;

            if (learnerId == null) {
                continue;
            }

            if (!sessionToLearnerIds.containsKey(enr.Session__c)) {
                sessionToLearnerIds.put(enr.Session__c, new Set<Id>());
            }

            sessionToLearnerIds.get(enr.Session__c).add(learnerId);
        }

        List<Portal_Notification__c> portalNotifs = new List<Portal_Notification__c>();

        for (Id sessionId : sessionToLearnerIds.keySet()) {

            Session__c session = sessionMap.get(sessionId);

            for (Id learnerId : sessionToLearnerIds.get(sessionId)) {

                portalNotifs.add(new Portal_Notification__c(
                    Title__c = 'Session Now Available',
                    Body__c = 'The session "' + session.Name + '" is now published.',
                    Recipient_Account__c = learnerId,
                    Is_Read__c = false,
                    Session__c = sessionId
                ));
            }
        }
		if (!portalNotifs.isEmpty()) {
    	Database.insert(portalNotifs, AccessLevel.SYSTEM_MODE);
		}
    }
}
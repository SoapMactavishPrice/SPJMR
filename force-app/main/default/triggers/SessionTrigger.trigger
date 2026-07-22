trigger SessionTrigger on Session__c (before insert, before update, after update,after insert, after delete,after undelete) { // NOPMD complexity suppressed: shared trigger, refactor out of scope
   SessionTriggerHandler.handleSessionCount(
        Trigger.new,
        Trigger.old,
        Trigger.isInsert,
        Trigger.isUpdate,
        Trigger.isDelete,
        Trigger.isUndelete
    );
   
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        SPJIMR_ProgramCodeCopyHandler.syncSession(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        SessionTriggerHandler.handleScheduleTypePublished(
            (Map<Id, Session__c>) Trigger.newMap,
            (Map<Id, Session__c>) Trigger.oldMap
        );

  // SessionEmailNotificationHandler.sendPublishedSessionEmails(Trigger.newMap,Trigger.oldMap);

        // POC SE-1056/1057/1047: Google Calendar invites on publish (students+faculty) / draft (faculty)
        SessionCalendarInviteHandler.handleSessionCalendarInvites(
            (Map<Id, Session__c>) Trigger.newMap,
            (Map<Id, Session__c>) Trigger.oldMap
        );
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        // A session created directly as Draft → faculty invite
        SessionCalendarInviteHandler.handleSessionCalendarInvites(
            (Map<Id, Session__c>) Trigger.newMap,
            null
        );
    }
    if (Trigger.isAfter && Trigger.isDelete) {
        // SE-1047 D3: cancel the Google event for any deleted Session that had one.
        SessionCalendarInviteHandler.handleSessionDeletes(
            (Map<Id, Session__c>) Trigger.oldMap
        );
    }
    
     // New logic for Program Course Session Count
    if (Trigger.isAfter) {

        if (Trigger.isInsert || Trigger.isUndelete) {

            SessionTriggerHandler.updateSessionCountInProgrameCourse(
                Trigger.new,
                Trigger.newMap
            );
        }

        if (Trigger.isDelete) {

            SessionTriggerHandler.updateSessionCountInProgrameCourse(
                Trigger.old,
                Trigger.oldMap
            );
        }

        if (Trigger.isUpdate) {

            List<Session__c> affectedSessions = new List<Session__c>();

            for (Session__c newRec : Trigger.new) {

                Session__c oldRec = Trigger.oldMap.get(newRec.Id);

                if (newRec.Batch__c != oldRec.Batch__c ||
                    newRec.Course__c != oldRec.Course__c) {

                    affectedSessions.add(newRec);
                    affectedSessions.add(oldRec);
                }
            }

            if (!affectedSessions.isEmpty()) {

                SessionTriggerHandler.updateSessionCountInProgrameCourse(
                    affectedSessions,
                    Trigger.newMap
                );
            }
        }
    }

    Set<Id> courseIds = new Set<Id>();

    // INSERT & UNDELETE
    if (Trigger.isInsert || Trigger.isUndelete) {

        for (Session__c ses : Trigger.new) {

            if (ses.Course__c != null) {
                courseIds.add(ses.Course__c);
            }
        }
    }

    // UPDATE
    if (Trigger.isUpdate) {

        // New Course
        for (Session__c ses : Trigger.new) {

            if (ses.Course__c != null) {
                courseIds.add(ses.Course__c);
            }
        }

        // Old Course
        for (Session__c ses : Trigger.old) {

            if (ses.Course__c != null) {
                courseIds.add(ses.Course__c);
            }
        }
    }

    // DELETE
    if (Trigger.isDelete) {

        for (Session__c ses : Trigger.old) {

            if (ses.Course__c != null) {
                courseIds.add(ses.Course__c);
            }
        }
    }

    // Call Handler
    if (!courseIds.isEmpty()) {
        SessionTriggerHandler.updateSessionCount(courseIds);
    }
    
}
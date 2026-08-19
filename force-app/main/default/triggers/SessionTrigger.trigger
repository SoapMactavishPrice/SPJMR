trigger SessionTrigger on Session__c (before insert, before update, after update,after insert, before delete, after delete,after undelete) { // NOPMD complexity suppressed: shared trigger, refactor out of scope
    // Missed Sessions cleanup: deleting a Session cascade-deletes its Session_Enrollment__c
    // records WITHOUT firing their delete trigger, which nulls the Missed_Sessions__c lookup
    // and leaves the row stranded on the Leave Application. Capture the affected leaves here,
    // while the links are still walkable, and resync them in the after-delete block below.
    // Returns immediately: nothing else in this trigger is written for a before-delete context.
    if (Trigger.isBefore && Trigger.isDelete) {
        MissedSessionSyncService.capturePendingLeaves(null, Trigger.oldMap.keySet());
        return;
    }

   SessionTriggerHandler.handleSessionCount(
        Trigger.new,
        Trigger.old,
        Trigger.isInsert,
        Trigger.isUpdate,
        Trigger.isDelete,
        Trigger.isUndelete
    );
   

    if (Trigger.isAfter && Trigger.isUpdate) {

         SessionTriggerHandler.handleScheduleTypePublished(
           (Map<Id, Session__c>) Trigger.newMap,
           (Map<Id, Session__c>) Trigger.oldMap
         );

        // Missed Sessions: a rescheduled or republished session that no longer falls inside
        // a student's leave period must drop off that Leave Application. Calls the service
        // directly — SessionTriggerHandler.handleSessionDateChanges was a duplicate of this
        // same loop, and routing through it drags SE-659's unreleased dependencies along.
        MissedSessionSyncService.handleSessionDateChanges(
            (Map<Id, Session__c>) Trigger.newMap,
            (Map<Id, Session__c>) Trigger.oldMap
        );
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

        MissedSessionSyncService.resyncPendingLeaves();
    }
    
     // New logic for Program Course Session Count
    if (Trigger.isAfter) {


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

        }
    }
    //test
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
    
}
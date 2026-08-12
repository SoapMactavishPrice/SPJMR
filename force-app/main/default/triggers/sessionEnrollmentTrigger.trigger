trigger sessionEnrollmentTrigger on Session_Enrollment__c (before insert, before update, after update, before delete, after delete) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        SPJIMR_ProgramCodeCopyHandler.syncSessionEnrollment(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        SessionEnrollmentTriggerHandler.handleAttendanceChanged(
            (Map<Id, Session_Enrollment__c>) Trigger.newMap,
            (Map<Id, Session_Enrollment__c>) Trigger.oldMap
        );
    }
    // Missed Sessions cleanup: deleting an enrollment nulls the Missed_Sessions__c lookup
    // (deleteConstraint SetNull), so the affected leaves are captured before the delete and
    // resynced after it. Covers a division being removed from a published session.
    if (Trigger.isDelete) {
        if (Trigger.isBefore) {
            MissedSessionSyncService.capturePendingLeaves(Trigger.oldMap.keySet(), null);
        } else {
            MissedSessionSyncService.resyncPendingLeaves();
        }
    }
}
trigger sessionEnrollmentTrigger on Session_Enrollment__c (before insert, before update, after update) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        SPJIMR_ProgramCodeCopyHandler.syncSessionEnrollment(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        SessionEnrollmentTriggerHandler.handleAttendanceChanged(
            (Map<Id, Session_Enrollment__c>) Trigger.newMap,
            (Map<Id, Session_Enrollment__c>) Trigger.oldMap
        );
    }
}
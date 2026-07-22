trigger DivisionEnrollmentTrigger on Division_Enrollment__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        DivisionEnrollmentTriggerHandler.handleAfterInsert(Trigger.new);
    }
}
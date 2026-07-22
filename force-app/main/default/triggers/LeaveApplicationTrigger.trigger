trigger LeaveApplicationTrigger on Leave_Application__c (before insert, after insert, after update) {

    if (Trigger.isBefore && Trigger.isInsert) {
        LeaveApplicationTriggerHandler.beforeInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        LeaveApplicationTriggerHandler.afterInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        LeaveApplicationTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}
trigger LeaveApplicationTrigger on Leave_Application__c (before insert, after insert, after update) {
    //trigger
    if (Trigger.isBefore && Trigger.isInsert) {
        LeaveApplicationTriggerHandler.beforeInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        LeaveApplicationTriggerHandler.afterInsert(Trigger.new);
    }
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {

        Map<Id, String> newCodes = new Map<Id, String>();
        Map<Id, String> oldCodes = new Map<Id, String>();

        for (Leave_Application__c record : Trigger.new) {
            newCodes.put(
                record.Id,
                record.Programme_Code__c
            );
        }

        if (Trigger.isUpdate) {
            for (Leave_Application__c record : Trigger.old) {
                oldCodes.put(
                    record.Id,
                    record.Programme_Code__c
                );
            }
        }

        ProgrammeSharingService.shareRecords(
            'Leave_Application__c',
            newCodes,
            Trigger.isUpdate ? oldCodes : null
        );
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        LeaveApplicationTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}
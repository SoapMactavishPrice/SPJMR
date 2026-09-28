trigger AccountTrigger on Account (before insert, before update, after insert,after update) {

    if (Trigger.isAfter && Trigger.isInsert) {
        AccountTriggerHelper.createPortalUserForStudent(Trigger.new);
    }

    if (Trigger.isBefore && Trigger.isInsert) {
        AccountTriggerHandler.checkDuplicateStudents(Trigger.new);
        AccountTriggerHandler.checkDuplicateFacultyCode(Trigger.new, null);
    }

    if (Trigger.isBefore && Trigger.isUpdate) {
        AccountTriggerHandler.checkDuplicateFacultyCode(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {

        Map<Id, String> newCodes = new Map<Id, String>();
        Map<Id, String> oldCodes = new Map<Id, String>();

        for (Account record : Trigger.new) {
            newCodes.put(
                record.Id,
                record.Programme_Code__c
            );
        }

        if (Trigger.isUpdate) {
            for (Account record : Trigger.old) {
                oldCodes.put(
                    record.Id,
                    record.Programme_Code__c
                );
            }
        }

        ProgrammeSharingService.shareRecords(
            'Account',
            newCodes,
            Trigger.isUpdate ? oldCodes : null
        );
    }
}
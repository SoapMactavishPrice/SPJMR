trigger AccountTrigger on Account (before insert, before update, after insert) {

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
}
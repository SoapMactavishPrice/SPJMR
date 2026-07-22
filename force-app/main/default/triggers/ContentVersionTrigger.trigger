trigger ContentVersionTrigger on ContentVersion (before insert) {
if (Trigger.isBefore && Trigger.isInsert) {
        ContentVersionTriggerHandler.setFilePrefix(Trigger.new);
    }
}
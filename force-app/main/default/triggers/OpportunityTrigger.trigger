trigger OpportunityTrigger on Opportunity (before insert, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        OpportunityTriggerHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        OpportunityTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
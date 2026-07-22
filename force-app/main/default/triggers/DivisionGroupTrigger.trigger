trigger DivisionGroupTrigger on Division_Group__c (before delete) {
    if (Trigger.isBefore && Trigger.isDelete) {
        DivisionGroupHandler.beforeDelete(Trigger.old);
    }
}
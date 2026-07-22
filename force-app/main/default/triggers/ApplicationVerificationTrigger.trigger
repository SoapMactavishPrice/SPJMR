trigger ApplicationVerificationTrigger on Application_Verification__c (after update) {
    if(Trigger.isAfter && Trigger.isUpdate){
        ApplicationVerificationTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}
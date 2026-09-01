trigger DefermentRequestTrigger on Deferment_Request__c (after insert,after update){
 if (Trigger.isInsert){
    DefermentRequestTriggerHandler.sendDefermentFormEnabledEmail(
        Trigger.new
    );
    }
    if (Trigger.isUpdate) {
        DefermentRequestTriggerHandler.sendDefermentProcessCompleteEmail(
            Trigger.new,
            Trigger.oldMap
        );
    }
}
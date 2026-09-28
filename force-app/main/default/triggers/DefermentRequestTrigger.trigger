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
      if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {

        Map<Id, String> newCodes = new Map<Id, String>();
        Map<Id, String> oldCodes = new Map<Id, String>();

        for (Deferment_Request__c record : Trigger.new) {
            newCodes.put(
                record.Id,
                record.Programme_Code__c
            );
        }

        if (Trigger.isUpdate) {
            for (Deferment_Request__c record : Trigger.old) {
                oldCodes.put(
                    record.Id,
                    record.Programme_Code__c
                );
            }
        }

        ProgrammeSharingService.shareRecords(
            'Deferment_Request__c',
            newCodes,
            Trigger.isUpdate ? oldCodes : null
        );
    }
}
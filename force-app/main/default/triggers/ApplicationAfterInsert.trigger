trigger ApplicationAfterInsert on Application__c (after insert,after update) {  //after update
    //ApplicationLeadUpdateHandler.updateLeadFromApplication(Trigger.new);
    // if(trigger.isAfter){
    //     if(trigger.isInsert){
    //         SharingOrchestrator.handleRecords('Application__c', Trigger.newMap.Keyset());
    //     }
    //     if(trigger.isUpdate){
    //         SharingOrchestrator.processRecordsToUpdate(Trigger.new,Trigger.oldMap);
    //     }
    // }
}
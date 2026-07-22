trigger ApplicationTrigger on Application__c (After Insert ,After Update ) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        ApplicationTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
    if(Trigger.isAfter) {
        if(Trigger.isInsert) {
            SharingOrchestrator.handleRecords('Application__c', Trigger.newMap.Keyset());
            ApplicationTriggerHandler.handleGMPEmail(
                Trigger.new, null
            );
        }
        if(Trigger.isUpdate) {
            SharingOrchestrator.processRecordsToUpdate(Trigger.new,Trigger.oldMap);
            ApplicationTriggerHandler.handleGMPEmail(
                Trigger.new, Trigger.oldMap
            );
        }
    }
}
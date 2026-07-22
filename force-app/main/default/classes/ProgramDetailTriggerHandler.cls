public class ProgramDetailTriggerHandler {

    public void beforeInsert(List<Program_Detail__c> newList) {
       
    }

    public void beforeUpdate(
        List<Program_Detail__c> newList,
        Map<Id, Program_Detail__c> newMap,
        List<Program_Detail__c> oldList,
        Map<Id, Program_Detail__c> oldMap
    ) {
       
    }

    public void afterInsert(
        List<Program_Detail__c> newList,
        Map<Id, Program_Detail__c> newMap
    ) {
        SharingOrchestrator.handleRecords(
            'Program_Detail__c',
            newMap.keySet()
        );
    }

    public void afterUpdate(
        List<Program_Detail__c> newList,
        Map<Id, Program_Detail__c> newMap,
        List<Program_Detail__c> oldList,
        Map<Id, Program_Detail__c> oldMap
    ) {
        
        
    }

    public void beforeDelete(
        List<Program_Detail__c> oldList,
        Map<Id, Program_Detail__c> oldMap
    ) {
        
    }

    public void afterDelete(
        List<Program_Detail__c> oldList,
        Map<Id, Program_Detail__c> oldMap
    ) {
       
    }
    
    public void afterUndelete(
        List<Program_Detail__c> newList,
        Map<Id, Program_Detail__c> newMap
    ) {

    }
}
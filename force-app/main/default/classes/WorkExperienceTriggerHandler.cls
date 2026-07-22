public class WorkExperienceTriggerHandler {

    public void beforeInsert(List<Work_Experience__c> newList) {
       
    }

    public void beforeUpdate(
        List<Work_Experience__c> newList,
        Map<Id, Work_Experience__c> newMap,
        List<Work_Experience__c> oldList,
        Map<Id, Work_Experience__c> oldMap
    ) {
       
    }

    public void afterInsert(
        List<Work_Experience__c> newList,
        Map<Id, Work_Experience__c> newMap
    ) {
        SharingOrchestrator.handleRecords(
            'Work_Experience__c',
            newMap.keySet()
        );
    }

    public void afterUpdate(
        List<Work_Experience__c> newList,
        Map<Id, Work_Experience__c> newMap,
        List<Work_Experience__c> oldList,
        Map<Id, Work_Experience__c> oldMap
    ) {
        
        
    }

    public void beforeDelete(
        List<Work_Experience__c> oldList,
        Map<Id, Work_Experience__c> oldMap
    ) {
        
    }

    public void afterDelete(
        List<Work_Experience__c> oldList,
        Map<Id, Work_Experience__c> oldMap
    ) {
       
    }
    
    public void afterUndelete(
        List<Work_Experience__c> newList,
        Map<Id, Work_Experience__c> newMap
    ) {

    }
}
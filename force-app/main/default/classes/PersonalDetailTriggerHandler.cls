public class PersonalDetailTriggerHandler {

    public void beforeInsert(List<Personal_Detail__c> newList) {
       
    }

    public void beforeUpdate(
        List<Personal_Detail__c> newList,
        Map<Id, Personal_Detail__c> newMap,
        List<Personal_Detail__c> oldList,
        Map<Id, Personal_Detail__c> oldMap
    ) {
       
    }

    public void afterInsert(
        List<Personal_Detail__c> newList,
        Map<Id, Personal_Detail__c> newMap
    ) {
        SharingOrchestrator.handleRecords(
            'Personal_Detail__c',
            newMap.keySet()
        );
    }

    public void afterUpdate(
        List<Personal_Detail__c> newList,
        Map<Id, Personal_Detail__c> newMap,
        List<Personal_Detail__c> oldList,
        Map<Id, Personal_Detail__c> oldMap
    ) {
        
        
    }

    public void beforeDelete(
        List<Personal_Detail__c> oldList,
        Map<Id, Personal_Detail__c> oldMap
    ) {
        
    }

    public void afterDelete(
        List<Personal_Detail__c> oldList,
        Map<Id, Personal_Detail__c> oldMap
    ) {
       
    }
    
    public void afterUndelete(
        List<Personal_Detail__c> newList,
        Map<Id, Personal_Detail__c> newMap
    ) {

    }
}
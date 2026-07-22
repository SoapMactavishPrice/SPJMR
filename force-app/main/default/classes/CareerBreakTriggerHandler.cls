public class CareerBreakTriggerHandler {

    public void beforeInsert(List<CareerBreak__c> newList) {
       
    }

    public void beforeUpdate(
        List<CareerBreak__c> newList,
        Map<Id, CareerBreak__c> newMap,
        List<CareerBreak__c> oldList,
        Map<Id, CareerBreak__c> oldMap
    ) {
       
    }

    public void afterInsert(
        List<CareerBreak__c> newList,
        Map<Id, CareerBreak__c> newMap
    ) {
        SharingOrchestrator.handleRecords(
            'CareerBreak__c',
            newMap.keySet()
        );
    }

    public void afterUpdate(
        List<CareerBreak__c> newList,
        Map<Id, CareerBreak__c> newMap,
        List<CareerBreak__c> oldList,
        Map<Id, CareerBreak__c> oldMap
    ) {
        
        
    }

    public void beforeDelete(
        List<CareerBreak__c> oldList,
        Map<Id, CareerBreak__c> oldMap
    ) {
        
    }

    public void afterDelete(
        List<CareerBreak__c> oldList,
        Map<Id, CareerBreak__c> oldMap
    ) {
       
    }
    
    public void afterUndelete(
        List<CareerBreak__c> newList,
        Map<Id, CareerBreak__c> newMap
    ) {

    }
}
public class ScoringTemplateTriggerHandler {
    
     public void beforeInsert(List<ScoringTemplate__c> newList) {
       
    }

    public void beforeUpdate(List<ScoringTemplate__c> newList, Map<Id,ScoringTemplate__c> newMap, List<ScoringTemplate__c> oldList, Map<Id,ScoringTemplate__c> oldMap) {
        
    }

    public void afterInsert(List<ScoringTemplate__c> newList, Map<Id,ScoringTemplate__c> newMap) {
       
        SharingOrchestrator.handleRecords('ScoringTemplate__c', newMap.keySet());
        
    }

    public void afterUpdate(List<ScoringTemplate__c> newList, Map<Id,ScoringTemplate__c> newMap, List<ScoringTemplate__c> oldList, Map<Id,ScoringTemplate__c> oldMap) {
        
        
    }

    public void beforeDelete(List<ScoringTemplate__c> oldList, Map<Id,ScoringTemplate__c> oldMap) {
    }

    public void afterDelete(List<ScoringTemplate__c> oldList, Map<Id,ScoringTemplate__c> oldMap) {
    }
    
    public void afterUndelete(List<ScoringTemplate__c> newList, Map<Id,ScoringTemplate__c> newMap) {

    }
     
    
    
}
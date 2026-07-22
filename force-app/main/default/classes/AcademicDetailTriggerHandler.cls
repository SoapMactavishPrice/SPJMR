public class AcademicDetailTriggerHandler {

     public void beforeInsert(List<Academic_Detail__c> newList) {
       
    }

    public void beforeUpdate(List<Academic_Detail__c> newList, Map<Id,Academic_Detail__c> newMap, List<Academic_Detail__c> oldList, Map<Id,Academic_Detail__c> oldMap) {
       
    }

    public void afterInsert(List<Academic_Detail__c> newList, Map<Id,Academic_Detail__c> newMap) {
      SharingOrchestrator.handleRecords('Academic_Detail__c', newMap.keySet());
    }

    public void afterUpdate(List<Academic_Detail__c> newList, Map<Id,Academic_Detail__c> newMap, List<Academic_Detail__c> oldList, Map<Id,Academic_Detail__c> oldMap) {
        
        
    }

    public void beforeDelete(List<Academic_Detail__c> oldList, Map<Id,Academic_Detail__c> oldMap) {
        
    }

    public void afterDelete(List<Academic_Detail__c> oldList, Map<Id,Academic_Detail__c> oldMap) {
       
    }
    
    public void afterUndelete(List<Academic_Detail__c> newList, Map<Id,Academic_Detail__c> newMap) {

    }
}
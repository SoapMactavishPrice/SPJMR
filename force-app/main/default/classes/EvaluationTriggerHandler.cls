public class EvaluationTriggerHandler {

    
     public void beforeInsert(List<Evaluation__c> newList) {
       
    }

    public void beforeUpdate(List<Evaluation__c> newList, Map<Id,Evaluation__c> newMap, List<Evaluation__c> oldList, Map<Id,Evaluation__c> oldMap) {
        
    }

    public void afterInsert(List<Evaluation__c> newList, Map<Id,Evaluation__c> newMap) {
       
		SharingOrchestrator.handleRecords('Evaluation__c', newMap.keySet());        
    }

    public void afterUpdate(List<Evaluation__c> newList, Map<Id,Evaluation__c> newMap, List<Evaluation__c> oldList, Map<Id,Evaluation__c> oldMap) {
      
        
    }

    public void beforeDelete(List<Evaluation__c> oldList, Map<Id,Evaluation__c> oldMap) {

    }

    public void afterDelete(List<Evaluation__c> oldList, Map<Id,Evaluation__c> oldMap) {
       
    }
    
    public void afterUndelete(List<Evaluation__c> newList, Map<Id,Evaluation__c> newMap) {

    }
}
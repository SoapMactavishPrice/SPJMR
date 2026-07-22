public class RoundMasterTriggerHandler {
    
    public void beforeInsert(List<RoundMaster__c> newList) {
       RoundMasterTriggerHelper.checkForSameSequence(newList);
    }

    public void beforeUpdate(List<RoundMaster__c> newList, Map<Id,RoundMaster__c> newMap, List<RoundMaster__c> oldList, Map<Id,RoundMaster__c> oldMap) {
        RoundMasterTriggerHelper.checkForSameSequence(newList);
    }

    public void afterInsert(List<RoundMaster__c> newList, Map<Id,RoundMaster__c> newMap) {
     	SharingOrchestrator.handleRecords('RoundMaster__c', newMap.keySet());
        
    }

    public void afterUpdate(List<RoundMaster__c> newList, Map<Id,RoundMaster__c> newMap, List<RoundMaster__c> oldList, Map<Id,RoundMaster__c> oldMap) {
   
        
    }

    public void beforeDelete(List<RoundMaster__c> oldList, Map<Id,RoundMaster__c> oldMap) {

    }

    public void afterDelete(List<RoundMaster__c> oldList, Map<Id,RoundMaster__c> oldMap) {
       
    }
    
    public void afterUndelete(List<RoundMaster__c> newList, Map<Id,RoundMaster__c> newMap) {

    }

}
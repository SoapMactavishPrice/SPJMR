public class RoundResultTriggerHandler {
    
    public void beforeInsert(List<Round_Result__c> newList) {
       RoundResultTriggerHelper.updateApplicationScore(newList);
    }

    public void beforeUpdate(List<Round_Result__c> newList, Map<Id,Round_Result__c> newMap, List<Round_Result__c> oldList, Map<Id,Round_Result__c> oldMap) {
        RoundResultTriggerHelper.updateApplicationScore(newList);
    }

    public void afterInsert(List<Round_Result__c> newList, Map<Id,Round_Result__c> newMap) {
       
    }

    public void afterUpdate(List<Round_Result__c> newList, Map<Id,Round_Result__c> newMap, List<Round_Result__c> oldList, Map<Id,Round_Result__c> oldMap) {
   
        
    }

    public void beforeDelete(List<Round_Result__c> oldList, Map<Id,Round_Result__c> oldMap) {

    }

    public void afterDelete(List<Round_Result__c> oldList, Map<Id,Round_Result__c> oldMap) {
        
    }
    
    public void afterUndelete(List<Round_Result__c> newList, Map<Id,Round_Result__c> newMap) {

    }
     

}
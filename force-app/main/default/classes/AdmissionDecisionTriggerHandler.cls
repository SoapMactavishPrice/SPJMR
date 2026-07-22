public class AdmissionDecisionTriggerHandler {
    
    public void beforeInsert(List<Admission_Decision__c> newList) {
       AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonInsert(newList);
    }

    public void beforeUpdate(List<Admission_Decision__c> newList, Map<Id,Admission_Decision__c> newMap, List<Admission_Decision__c> oldList, Map<Id,Admission_Decision__c> oldMap) {
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonUpdate(newList,oldMap);
    }

    public void afterInsert(List<Admission_Decision__c> newList, Map<Id,Admission_Decision__c> newMap) {
       AdmissionDecisionTriggerHelper.preventAdditionalRecordCreation(newList);
       SharingOrchestrator.handleRecords('Admission_Decision__c',newMap.keySet());
    }

    public void afterUpdate(List<Admission_Decision__c> newList, Map<Id,Admission_Decision__c> newMap, List<Admission_Decision__c> oldList, Map<Id,Admission_Decision__c> oldMap) {
        
    }

    public void beforeDelete(List<Admission_Decision__c> oldList, Map<Id,Admission_Decision__c> oldMap) {

    }

    public void afterDelete(List<Admission_Decision__c> oldList, Map<Id,Admission_Decision__c> oldMap) {
        
    }
    
    public void afterUndelete(List<Admission_Decision__c> newList, Map<Id,Admission_Decision__c> newMap) {

    }
     

}
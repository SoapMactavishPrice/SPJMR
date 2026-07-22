public with sharing class PanelMasterTriggerHandler {

    private static Boolean hasRun = false;

    public void beforeInsert(List<PanelMaster__c> newList, Map<Id, PanelMaster__c> newMap) {
      
    }

    public void beforeUpdate(List<PanelMaster__c> newList, Map<Id, PanelMaster__c> newMap, List<PanelMaster__c> oldList, Map<Id, PanelMaster__c> oldMap) {

    }

    public void afterInsert(List<PanelMaster__c> newList, Map<Id, PanelMaster__c> newMap) {
        if (hasRun) return;
        hasRun = true;

        // Call the helper to process evaluations
        PanelMasterHelper.processPanelEvaluations(newList, null);
    }

    public void afterUpdate(List<PanelMaster__c> newList, Map<Id, PanelMaster__c> newMap, List<PanelMaster__c> oldList, Map<Id, PanelMaster__c> oldMap) {
        if (hasRun) return;
        hasRun = true;

        // Call the helper to process evaluations
        PanelMasterHelper.processPanelEvaluations(newList, oldMap);
    }

    public void beforeDelete(List<PanelMaster__c> oldList, Map<Id, PanelMaster__c> oldMap) {
       
    }

    public void afterDelete(List<PanelMaster__c> oldList, Map<Id, PanelMaster__c> oldMap) {

    }

    public void afterUndelete(List<PanelMaster__c> newList, Map<Id, PanelMaster__c> newMap) {
     
    }
}
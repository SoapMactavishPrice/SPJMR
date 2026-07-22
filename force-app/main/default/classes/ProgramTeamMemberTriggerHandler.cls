public with sharing class ProgramTeamMemberTriggerHandler {

    private static Boolean hasRun = false;

    public void beforeInsert(List<Program_Team_Members__c> newList, Map<Id, Program_Team_Members__c> newMap) {
        
    }

    public void beforeUpdate(List<Program_Team_Members__c> newList, Map<Id, Program_Team_Members__c> newMap, 
                             List<Program_Team_Members__c> oldList, Map<Id, Program_Team_Members__c> oldMap) {
      
    }

    public void afterInsert(List<Program_Team_Members__c> newList, Map<Id, Program_Team_Members__c> newMap) {
        if (hasRun) return;
        hasRun = true;

        // Call helper to handle insert scenario (new team members)
        ProgramTeamMemberHelper.processTeamMemberChanges(newList, null);
    }

    public void afterUpdate(List<Program_Team_Members__c> newList, Map<Id, Program_Team_Members__c> newMap, 
                            List<Program_Team_Members__c> oldList, Map<Id, Program_Team_Members__c> oldMap) {
        if (hasRun) return;
        hasRun = true;

        ProgramTeamMemberHelper.processTeamMemberChanges(newList, oldMap);
    }

    public void beforeDelete(List<Program_Team_Members__c> oldList, Map<Id, Program_Team_Members__c> oldMap) {
     
    }

    public void afterDelete(List<Program_Team_Members__c> oldList, Map<Id, Program_Team_Members__c> oldMap) {
           }

    public void afterUndelete(List<Program_Team_Members__c> newList, Map<Id, Program_Team_Members__c> newMap) {
    
    }
}
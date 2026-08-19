public with sharing class ApplicationSlotBookingTriggerHandler {
    private static Boolean hasRun = false;

    public void beforeInsert(List<ApplicationSlotBooking__c> newList) {
       
    }

    public void beforeUpdate(List<ApplicationSlotBooking__c> newList, Map<Id,ApplicationSlotBooking__c> newMap, List<ApplicationSlotBooking__c> oldList, Map<Id,ApplicationSlotBooking__c> oldMap) {
        
    }

    public void afterInsert(List<ApplicationSlotBooking__c> newList, Map<Id,ApplicationSlotBooking__c> newMap) {
        ApplicationSlotBookingTriggerHelper.updateSlotBookedCapacity(newMap);
        ApplicationSlotBookingTriggerHelper.updateApplicationStateManagement(newList);
        //SharingOrchestrator.handleRecords('ApplicationSlotBooking__c', newMap.keySet());
       // ApplicationSlotBookingTriggerHelper.checkForDuplicateRounds(newList,newMap);
     //    ApplicationSlotBookingTriggerHelper.processEvaluations(newList, null);
        
    }

    public void afterUpdate(List<ApplicationSlotBooking__c> newList, Map<Id,ApplicationSlotBooking__c> newMap, List<ApplicationSlotBooking__c> oldList, Map<Id,ApplicationSlotBooking__c> oldMap) {
        ApplicationSlotBookingTriggerHelper.updateSlotBookedCapacity(newMap);
    //    ApplicationSlotBookingTriggerHelper.processEvaluations(newList, oldMap);
        
    }

    public void beforeDelete(List<ApplicationSlotBooking__c> oldList, Map<Id,ApplicationSlotBooking__c> oldMap) {
        ApplicationSlotBookingTriggerHelper.deleteEvaluationsRecords(oldList);
    }

    public void afterDelete(List<ApplicationSlotBooking__c> oldList, Map<Id,ApplicationSlotBooking__c> oldMap) {
        ApplicationSlotBookingTriggerHelper.updateSlotBookedCapacity(oldMap);
    }
    
    public void afterUndelete(List<ApplicationSlotBooking__c> newList, Map<Id,ApplicationSlotBooking__c> newMap) {

    }
     
    
    
   
   
}
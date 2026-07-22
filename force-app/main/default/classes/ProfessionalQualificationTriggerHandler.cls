public class ProfessionalQualificationTriggerHandler {

    public void beforeInsert(List<Professional_Qualification__c> newList) {
       
    }

    public void beforeUpdate(
        List<Professional_Qualification__c> newList,
        Map<Id, Professional_Qualification__c> newMap,
        List<Professional_Qualification__c> oldList,
        Map<Id, Professional_Qualification__c> oldMap
    ) {
       
    }

    public void afterInsert(
        List<Professional_Qualification__c> newList,
        Map<Id, Professional_Qualification__c> newMap
    ) {
        SharingOrchestrator.handleRecords(
            'Professional_Qualification__c',
            newMap.keySet()
        );
    }

    public void afterUpdate(
        List<Professional_Qualification__c> newList,
        Map<Id, Professional_Qualification__c> newMap,
        List<Professional_Qualification__c> oldList,
        Map<Id, Professional_Qualification__c> oldMap
    ) {
        
        
    }

    public void beforeDelete(
        List<Professional_Qualification__c> oldList,
        Map<Id, Professional_Qualification__c> oldMap
    ) {
        
    }

    public void afterDelete(
        List<Professional_Qualification__c> oldList,
        Map<Id, Professional_Qualification__c> oldMap
    ) {
       
    }
    
    public void afterUndelete(
        List<Professional_Qualification__c> newList,
        Map<Id, Professional_Qualification__c> newMap
    ) {

    }
}
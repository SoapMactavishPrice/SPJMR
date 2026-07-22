public class BasicAcademicDetailTriggerHandler {

    public void beforeInsert(List<BasicAcademicDetail__c> newList) {
       
    }

    public void beforeUpdate(
        List<BasicAcademicDetail__c> newList,
        Map<Id, BasicAcademicDetail__c> newMap,
        List<BasicAcademicDetail__c> oldList,
        Map<Id, BasicAcademicDetail__c> oldMap
    ) {
       
    }

    public void afterInsert(
        List<BasicAcademicDetail__c> newList,
        Map<Id, BasicAcademicDetail__c> newMap
    ) {
        SharingOrchestrator.handleRecords(
            'BasicAcademicDetail__c',
            newMap.keySet()
        );
    }

    public void afterUpdate(
        List<BasicAcademicDetail__c> newList,
        Map<Id, BasicAcademicDetail__c> newMap,
        List<BasicAcademicDetail__c> oldList,
        Map<Id, BasicAcademicDetail__c> oldMap
    ) {
        
        
    }

    public void beforeDelete(
        List<BasicAcademicDetail__c> oldList,
        Map<Id, BasicAcademicDetail__c> oldMap
    ) {
        
    }

    public void afterDelete(
        List<BasicAcademicDetail__c> oldList,
        Map<Id, BasicAcademicDetail__c> oldMap
    ) {
       
    }
    
    public void afterUndelete(
        List<BasicAcademicDetail__c> newList,
        Map<Id, BasicAcademicDetail__c> newMap
    ) {

    }
}
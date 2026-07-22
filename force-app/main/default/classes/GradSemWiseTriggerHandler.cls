public class GradSemWiseTriggerHandler {

    public void beforeInsert(List<Graduation_Details_Semester_wise__c> newList) {
       
    }

    public void beforeUpdate(
        List<Graduation_Details_Semester_wise__c> newList,
        Map<Id, Graduation_Details_Semester_wise__c> newMap,
        List<Graduation_Details_Semester_wise__c> oldList,
        Map<Id, Graduation_Details_Semester_wise__c> oldMap
    ) {
       
    }

    public void afterInsert(
        List<Graduation_Details_Semester_wise__c> newList,
        Map<Id, Graduation_Details_Semester_wise__c> newMap
    ) {
        SharingOrchestrator.handleRecords(
            'Graduation_Details_Semester_wise__c',
            newMap.keySet()
        );
    }

    public void afterUpdate(
        List<Graduation_Details_Semester_wise__c> newList,
        Map<Id, Graduation_Details_Semester_wise__c> newMap,
        List<Graduation_Details_Semester_wise__c> oldList,
        Map<Id, Graduation_Details_Semester_wise__c> oldMap
    ) {
        
        
    }

    public void beforeDelete(
        List<Graduation_Details_Semester_wise__c> oldList,
        Map<Id, Graduation_Details_Semester_wise__c> oldMap
    ) {
        
    }

    public void afterDelete(
        List<Graduation_Details_Semester_wise__c> oldList,
        Map<Id, Graduation_Details_Semester_wise__c> oldMap
    ) {
       
    }
    
    public void afterUndelete(
        List<Graduation_Details_Semester_wise__c> newList,
        Map<Id, Graduation_Details_Semester_wise__c> newMap
    ) {

    }
}
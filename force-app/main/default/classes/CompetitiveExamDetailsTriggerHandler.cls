public class CompetitiveExamDetailsTriggerHandler {

    public void beforeInsert(List<Competitive_Exam_Details__c> newList) {
       
    }

    public void beforeUpdate(
        List<Competitive_Exam_Details__c> newList,
        Map<Id, Competitive_Exam_Details__c> newMap,
        List<Competitive_Exam_Details__c> oldList,
        Map<Id, Competitive_Exam_Details__c> oldMap
    ) {
       
    }

    public void afterInsert(
        List<Competitive_Exam_Details__c> newList,
        Map<Id, Competitive_Exam_Details__c> newMap
    ) {
        SharingOrchestrator.handleRecords(
            'Competitive_Exam_Details__c',
            newMap.keySet()
        );
    }

    public void afterUpdate(
        List<Competitive_Exam_Details__c> newList,
        Map<Id, Competitive_Exam_Details__c> newMap,
        List<Competitive_Exam_Details__c> oldList,
        Map<Id, Competitive_Exam_Details__c> oldMap
    ) {
        
        
    }

    public void beforeDelete(
        List<Competitive_Exam_Details__c> oldList,
        Map<Id, Competitive_Exam_Details__c> oldMap
    ) {
        
    }

    public void afterDelete(
        List<Competitive_Exam_Details__c> oldList,
        Map<Id, Competitive_Exam_Details__c> oldMap
    ) {
       
    }
    
    public void afterUndelete(
        List<Competitive_Exam_Details__c> newList,
        Map<Id, Competitive_Exam_Details__c> newMap
    ) {

    }
}
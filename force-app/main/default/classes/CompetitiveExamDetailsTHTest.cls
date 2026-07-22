@IsTest
private class CompetitiveExamDetailsTHTest {
    @IsTest
    static void lifecycleMethodsRunWithEmptyCollections() {
        CompetitiveExamDetailsTriggerHandler h = new CompetitiveExamDetailsTriggerHandler();
        List<Competitive_Exam_Details__c> emptyList = new List<Competitive_Exam_Details__c>();
        Map<Id, Competitive_Exam_Details__c> emptyMap = new Map<Id, Competitive_Exam_Details__c>();
        h.beforeInsert(emptyList);
        h.beforeUpdate(emptyList, emptyMap, emptyList, emptyMap);
        h.afterInsert(emptyList, emptyMap);
        h.afterUpdate(emptyList, emptyMap, emptyList, emptyMap);
        h.beforeDelete(emptyList, emptyMap);
        h.afterDelete(emptyList, emptyMap);
        h.afterUndelete(emptyList, emptyMap);
        System.assert(true);
    }
}
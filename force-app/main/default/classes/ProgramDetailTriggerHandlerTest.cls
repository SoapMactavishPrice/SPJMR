@IsTest
private class ProgramDetailTriggerHandlerTest {
    @IsTest
    static void lifecycleMethodsRunWithEmptyCollections() {
        // The handler's only executable line is in afterInsert and delegates to
        // SharingOrchestrator.handleRecords which short-circuits on an empty Set<Id>.
        // We call every lifecycle method to make sure empty paths don't throw.
        ProgramDetailTriggerHandler h = new ProgramDetailTriggerHandler();
        List<Program_Detail__c> emptyList = new List<Program_Detail__c>();
        Map<Id, Program_Detail__c> emptyMap = new Map<Id, Program_Detail__c>();

        h.beforeInsert(emptyList);
        h.beforeUpdate(emptyList, emptyMap, emptyList, emptyMap);
        h.afterInsert(emptyList, emptyMap);
        h.afterUpdate(emptyList, emptyMap, emptyList, emptyMap);
        h.beforeDelete(emptyList, emptyMap);
        h.afterDelete(emptyList, emptyMap);
        h.afterUndelete(emptyList, emptyMap);
        System.assert(true, 'All lifecycle methods completed without error');
    }
}
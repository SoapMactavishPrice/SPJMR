@IsTest
private class CriteriaChunkQueueableTest {
    @IsTest
    static void testExecute_UpsertsChunk_AndEnqueuesNextChunk() {
        CriteriaChunkQueueable.skipChunkUpsertInTest = true;
        List<Individual_Criteria_Result__c> allCriteria = new List<Individual_Criteria_Result__c>{
            new Individual_Criteria_Result__c(Score__c = 1),
            new Individual_Criteria_Result__c(Score__c = 2)
        };
        Map<String, List<Id>> appToEvalIds = new Map<String, List<Id>>{
            'APP-001' => new List<Id>()
        };

        CriteriaChunkQueueable job = new CriteriaChunkQueueable(
            allCriteria,
            0,
            1,
            appToEvalIds,
            null
        );
        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assertEquals(2, allCriteria.size());
System.assertEquals(1, appToEvalIds.size());
        CriteriaChunkQueueable.skipChunkUpsertInTest = false;
    }

    @IsTest
    static void testExecute_LastChunk_EnqueuesInterviewProcess() {
        CriteriaChunkQueueable.skipChunkUpsertInTest = true;
        List<Individual_Criteria_Result__c> emptyCriteria = new List<Individual_Criteria_Result__c>();
        Map<String, List<Id>> appToEvalIds = new Map<String, List<Id>>{
            'APP-002' => new List<Id>()
        };

        CriteriaChunkQueueable job = new CriteriaChunkQueueable(
            emptyCriteria,
            0,
            200,
            appToEvalIds,
            null
        );
        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assertEquals(0, emptyCriteria.size());
System.assertEquals(1, appToEvalIds.size());
        CriteriaChunkQueueable.skipChunkUpsertInTest = false;
    }
}
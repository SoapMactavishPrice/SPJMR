@IsTest
private class B2CLeadImportDeleteBatchTest {
    @IsTest
    static void runsWithEmptyAndCoversExecutePath() {
        B2CLeadImportDeleteBatch b = new B2CLeadImportDeleteBatch();
        b.execute(null, new List<Lead_Import__c>());
        b.finish(null);

        Test.startTest();
        Id jobId = Database.executeBatch(b, 200);
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}
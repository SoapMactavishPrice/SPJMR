@IsTest
private class DeleteB2CTestDataBatchTest {
    @IsTest
    static void runsWithEmpty() {
        DeleteB2CTestDataBatch b = new DeleteB2CTestDataBatch();
        b.execute(null, new List<Lead_Import__c>());
        b.finish(null);
        Test.startTest();
        Id jobId = Database.executeBatch(b, 200);
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}
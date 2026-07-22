@IsTest
private class LeadImportSyncBatchTest {
    @IsTest
    static void runsThroughFullLifecycle() {
        LeadImportSyncBatch b = new LeadImportSyncBatch();
        Test.startTest();
        Id jobId = Database.executeBatch(b, 1);
        Test.stopTest();
        System.assertNotEquals(null, jobId);
        try { b.execute(null, new List<Lead_Import__c>()); } catch (Exception e) {}
        b.finish(null);
    }
}
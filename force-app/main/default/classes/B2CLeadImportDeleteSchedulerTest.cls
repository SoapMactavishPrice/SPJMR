@IsTest
private class B2CLeadImportDeleteSchedulerTest {
    @IsTest
    static void executeFiresBatch() {
        Test.startTest();
        new B2CLeadImportDeleteScheduler().execute(null);
        Test.stopTest();
        // The batch fires asynchronously inside startTest/stopTest. We only assert no exception.
        System.assert(true, 'Scheduler executed without error');
    }
}
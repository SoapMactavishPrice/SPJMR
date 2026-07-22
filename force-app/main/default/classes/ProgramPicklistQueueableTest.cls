@IsTest
private class ProgramPicklistQueueableTest {
    @IsTest
    static void executesWithEmptyList() {
        Test.startTest();
        Id jobId = System.enqueueJob(new ProgramPicklistQueueable(new List<Program>()));
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}
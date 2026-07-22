@IsTest
private class ApplicationFormCreateTest {
    @IsTest
    static void canEnqueueAndExecute() {
        Test.startTest();
        Id jobId = System.enqueueJob(new ApplicationFormCreate());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}
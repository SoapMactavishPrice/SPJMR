/**
 * Covers AttendanceBackfillController — the LWC/VF entry point that fires
 * AttendanceBackfillBatch and reports job status.
 *
 *   - runBackfill()  returns the batch job Id
 *   - getJobStatus() returns the job's status after it completes
 *   - runBackfill()  throws when a backfill is already running (duplicate guard)
 */
@IsTest
private class AttendanceBackfillControllerTest {

    @IsTest
    static void runBackfill_returnsJobId() {
        Test.startTest();
        Id jobId = AttendanceBackfillController.runBackfill();
        Test.stopTest();

        System.assertNotEquals(null, jobId,
            'runBackfill should return the AsyncApexJob Id of the queued batch.');
    }

    @IsTest
    static void getJobStatus_returnsCompletedStatus() {
        Test.startTest();
        Id jobId = AttendanceBackfillController.runBackfill();
        Test.stopTest();   // batch runs to completion here

        AttendanceBackfillController.JobStatus s =
            AttendanceBackfillController.getJobStatus(jobId);

        System.assertNotEquals(null, s, 'A JobStatus should be returned.');
        System.assertEquals(true, s.isDone,
            'The job should be complete after Test.stopTest().');
        System.assertNotEquals(null, s.status, 'Status string should be populated.');
    }

    @IsTest
    static void runBackfill_whileRunning_throws() {
        Test.startTest();
        // Pre-queue a backfill so the guard sees an in-flight job.
        Database.executeBatch(new AttendanceBackfillBatch(), 200);

        Boolean threw = false;
        try {
            AttendanceBackfillController.runBackfill();
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw,
            'Starting a second backfill while one is in flight should throw.');
    }
}
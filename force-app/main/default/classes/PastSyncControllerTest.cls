/**
 * Covers PastSyncController — the controller behind the "Past Sync" list-view
 * button on Attendance_Log__c.
 *
 *   - run() success path → isSuccess = true, message reports the job started
 *   - run() error path   → a backfill already running is caught and surfaced
 *                          as a friendly message (isSuccess = false)
 */
@IsTest
private class PastSyncControllerTest {

    @IsTest
    static void run_startsBackfill_success() {
        Test.startTest();
        PastSyncController ctrl = new PastSyncController();
        ctrl.run();
        Test.stopTest();

        System.assertEquals(true, ctrl.isSuccess,
            'run() should succeed and report the backfill started.');
        System.assert(ctrl.resultMessage != null
            && ctrl.resultMessage.contains('Past Sync started'),
            'Success message should confirm Past Sync started. Got: ' + ctrl.resultMessage);
    }

    @IsTest
    static void run_whileRunning_surfacesError() {
        Test.startTest();
        // Pre-queue a backfill so the controller's call hits the duplicate guard.
        Database.executeBatch(new AttendanceBackfillBatch(), 200);

        PastSyncController ctrl = new PastSyncController();
        ctrl.run();
        Test.stopTest();

        System.assertEquals(false, ctrl.isSuccess,
            'run() should report failure when a backfill is already running.');
        System.assert(ctrl.resultMessage != null
            && ctrl.resultMessage.startsWith('Could not start Past Sync'),
            'Error message should explain Past Sync could not start. Got: ' + ctrl.resultMessage);
    }
}
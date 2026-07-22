@IsTest
private class AttendanceSyncSchedulerTest {
    @IsTest
    static void executeFiresBatch() {
        Test.startTest();
        new AttendanceSyncScheduler().execute(null);
        Test.stopTest();
        System.assert(true, 'Scheduler executed without error');
    }
}
@IsTest
private class AttendanceMarkingSchedulerTest {

    @IsTest
    static void executeFiresBatch() {
        Test.startTest();
        new AttendanceMarkingScheduler().execute(null);
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void scheduleAbortAndCheck() {
        Test.startTest();
        AttendanceMarkingScheduler.scheduleAll();
        Integer scheduled = [
            SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Attendance_Marking_%'
        ];
        System.assertEquals(8, scheduled, 'Expected 7 daytime + 1 final job');
        AttendanceMarkingScheduler.checkSchedule();
        AttendanceMarkingScheduler.abortAll();
        Test.stopTest();
        System.assertEquals(
            0,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Attendance_Marking_%']
        );
    }
}
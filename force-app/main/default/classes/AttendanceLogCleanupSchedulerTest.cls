@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class AttendanceLogCleanupSchedulerTest {

    @IsTest
    static void schedulesWeeklyCleanupJob() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            AttendanceLogCleanupScheduler.scheduleAll();
            Test.stopTest();
        }

        List<CronTrigger> jobs = [
            SELECT CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'Attendance_Cleanup_Weekly'
        ];
        System.assertEquals(1, jobs.size(),
            'Weekly cleanup job should be scheduled');
        System.assertEquals('59 59 23 ? * 1', jobs[0].CronExpression,
            'Cron should fire every Sunday at 11:59:59 PM');
    }

    @IsTest
    static void executeEnqueuesCleanupBatch() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            new AttendanceLogCleanupScheduler().execute(null);
            Test.stopTest();
        }

        Integer batchJobs = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'AttendanceLogCleanupBatch'
        ];
        System.assert(batchJobs >= 1,
            'execute() should enqueue the cleanup batch');
    }

    @IsTest
    static void abortAllRemovesScheduledJobs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            AttendanceLogCleanupScheduler.scheduleAll();

            Test.startTest();
            AttendanceLogCleanupScheduler.abortAll();
            Test.stopTest();
        }

        System.assertEquals(0, AttendanceLogCleanupScheduler.checkSchedule().size(),
            'abortAll should remove all Attendance_Cleanup jobs');
    }
}
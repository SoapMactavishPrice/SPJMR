@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class AttendanceLogCleanupSchedulerTest {

    @IsTest
    static void schedulesEvery5DaysCleanupJob() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            AttendanceLogCleanupScheduler.scheduleAll();
            Test.stopTest();
        }

        List<CronTrigger> jobs = [
            SELECT CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'Attendance_Cleanup_Every5Days'
        ];
        System.assertEquals(1, jobs.size(),
            'Every-5-days cleanup job should be scheduled');
        System.assertEquals('59 59 23 1/5 * ?', jobs[0].CronExpression,
            'Cron should fire every 5 days at 11:59:59 PM');
    }

    /**
     * scheduleAll() must leave exactly ONE cleanup job behind, and it must not be
     * a job registered under a previous name. abortAll() matches on the
     * 'Attendance_Cleanup_%' prefix precisely so renaming the job cannot orphan
     * the old one.
     */
    @IsTest
    static void scheduleAllLeavesNoStaleJobBehind() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            AttendanceLogCleanupScheduler.scheduleAll();
            Test.stopTest();
        }

        List<CronTrigger> jobs = AttendanceLogCleanupScheduler.checkSchedule();
        System.assertEquals(1, jobs.size(),
            'exactly one Attendance_Cleanup job should remain');
        System.assertEquals('Attendance_Cleanup_Every5Days',
            jobs[0].CronJobDetail.Name,
            'the surviving job should be the every-5-days one, not an older name');
        System.assertEquals(0,
            [SELECT COUNT() FROM CronTrigger
             WHERE CronJobDetail.Name = 'Attendance_Cleanup_Every2Days'],
            'the previous every-2-days job must not survive scheduleAll()');
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
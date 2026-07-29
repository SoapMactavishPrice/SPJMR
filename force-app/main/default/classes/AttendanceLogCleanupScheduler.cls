/**
 * @description Schedulable that runs the Attendance_Log__c cleanup batch every
 *              other day at 11:59:59 PM, plus helpers to (re)schedule, abort and
 *              inspect the job. CronTrigger queries run against system metadata,
 *              so CRUD/FLS checks are intentionally bypassed.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class AttendanceLogCleanupScheduler implements Schedulable {

    /**
     * Cron expression: every 2 days at 11:59:59 PM. The day-of-month increment
     * (1/2) fires on days 1, 3, 5 ... 31 of each month.
     */
    // private static final String CRON_WEEKLY_SUNDAY = '59 59 23 ? * 1'; // old: every Sunday
    private static final String CRON_EVERY_2_DAYS = '59 59 23 1/2 * ?';

    /** Display name of the scheduled cleanup job. */
    private static final String JOB_NAME = 'Attendance_Cleanup_Every2Days';

    /**
     * @description Scheduler entry point; enqueues the cleanup batch.
     * @param ctx the schedulable context
     */
    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new AttendanceLogCleanupBatch(), 200);
    }

    /**
     * @description Aborts any existing cleanup jobs, then schedules the every-2-days job.
     */
    public static void scheduleAll() {
        abortAll();
        System.schedule(JOB_NAME, CRON_EVERY_2_DAYS, new AttendanceLogCleanupScheduler());
    }

    /**
     * @description Aborts every scheduled job whose name starts with
     *              'Attendance_Cleanup_'.
     */
    public static void abortAll() {
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Attendance_Cleanup_%'
        ]) {
            System.abortJob(ct.Id);
        }
    }

    /**
     * @description Returns the currently scheduled cleanup triggers for inspection.
     * @return list of matching CronTrigger records, ordered by next fire time
     */
    public static List<CronTrigger> checkSchedule() {
        return [
            SELECT CronJobDetail.Name, State, NextFireTime, PreviousFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Attendance_Cleanup_%'
            ORDER BY NextFireTime ASC
        ];
    }
}
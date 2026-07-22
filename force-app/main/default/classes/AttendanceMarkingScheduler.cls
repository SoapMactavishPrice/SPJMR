/**
 * @class   AttendanceMarkingScheduler
 * @purpose Triggers AttendanceMarkingBatch at fixed times.
 *
 *          AttendanceMarkingBatch is session-driven: it picks every
 *          Session_Enrollment__c whose Session has ended and decides
 *          Present (log in window) or Absent (no log in window).
 *
 * Schedule (IST, all 7 days incl. Sunday):
 *          08:10, 10:10, 12:10, 14:10, 16:10, 18:10, 20:10  — every 2 hours
 *          23:49                                            — final daily sweep
 */
public class AttendanceMarkingScheduler implements Schedulable {

    private static final List<Integer> SCHEDULED_HOURS =
        new List<Integer>{ 8, 10, 12, 14, 16, 18, 20 };

    private static final Integer SCHEDULED_MINUTE = 10;

    private static final Integer FINAL_HOUR   = 23;
    private static final Integer FINAL_MINUTE = 49;

    private static final Integer BATCH_SIZE = 200;

    // ─────────────────────────────────────────────────────────────────────────
    // EXECUTE — Fire the marking batch
    // ─────────────────────────────────────────────────────────────────────────
    public void execute(SchedulableContext ctx) {
        System.debug('AttendanceMarkingScheduler | Firing AttendanceMarkingBatch at ' + Datetime.now());
        Database.executeBatch(new AttendanceMarkingBatch(), BATCH_SIZE);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCHEDULE MANAGEMENT
    // ─────────────────────────────────────────────────────────────────────────

    public static void scheduleAll() {
        abortAll();

        // 2-hourly daytime runs
        for (Integer hour : SCHEDULED_HOURS) {
            String hh      = String.valueOf(hour).leftPad(2, '0');
            String jobName = 'Attendance_Marking_' + hh + 'H' + SCHEDULED_MINUTE + 'M';
            // Cron: Sec Min Hour DoM Mon DoW — DoW '*' = every day (incl. Sunday).
            String cron    = '0 ' + SCHEDULED_MINUTE + ' ' + hour + ' ? * *';
            System.schedule(jobName, cron, new AttendanceMarkingScheduler());
            System.debug('Scheduled → ' + jobName + '  Cron: ' + cron);
        }

        // Final nightly sweep
        String finalJob  = 'Attendance_Marking_'
                           + String.valueOf(FINAL_HOUR).leftPad(2, '0')
                           + 'H' + FINAL_MINUTE + 'M_Final';
        String finalCron = '0 ' + FINAL_MINUTE + ' ' + FINAL_HOUR + ' ? * *';
        System.schedule(finalJob, finalCron, new AttendanceMarkingScheduler());
        System.debug('Scheduled → ' + finalJob + '  Cron: ' + finalCron);

        System.debug('AttendanceMarkingScheduler: '
            + (SCHEDULED_HOURS.size() + 1)
            + ' jobs scheduled (all 7 days, incl. Sunday).');
    }

    public static void abortAll() {
        for (CronTrigger ct : [
            SELECT Id, CronJobDetail.Name FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Attendance_Marking_%'
        ]) {
            System.abortJob(ct.Id);
            System.debug('Aborted: ' + ct.CronJobDetail.Name);
        }
    }

    public static void checkSchedule() {
        for (CronTrigger ct : [
            SELECT CronJobDetail.Name, State, NextFireTime, PreviousFireTime
            FROM   CronTrigger
            WHERE  CronJobDetail.Name LIKE 'Attendance_Marking_%'
            ORDER BY NextFireTime ASC
        ]) {
            System.debug(ct.CronJobDetail.Name
                + ' | State: ' + ct.State
                + ' | Next: '  + ct.NextFireTime
                + ' | Last: '  + ct.PreviousFireTime);
        }
    }
}
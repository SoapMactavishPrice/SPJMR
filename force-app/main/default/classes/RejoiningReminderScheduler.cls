/**
 * @description Schedulable that runs RejoiningReminderBatch nightly, plus
 *              helpers to (re)schedule, abort and inspect the job. CronTrigger
 *              queries run against system metadata, so CRUD/FLS checks are
 *              intentionally bypassed.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RejoiningReminderScheduler implements Schedulable {

    /** Cron expression: every night at 1:00 AM. */
    private static final String CRON_NIGHTLY = '0 0 1 * * ?';

    /** Display name of the scheduled job; abortAll() matches on this prefix. */
    private static final String JOB_NAME = 'Rejoining_Reminder_Nightly';

    /**
     * Chunk size. Each request renders up to two templates and the org allows
     * a limited number of e-mails per transaction, so the scope stays small.
     */
    private static final Integer SCOPE_SIZE = 50;

    /**
     * @description Scheduler entry point; enqueues the reminder batch.
     * @param ctx the schedulable context
     */
    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new RejoiningReminderBatch(), SCOPE_SIZE);
    }

    /**
     * @description Aborts any existing reminder job, then schedules the nightly run.
     */
    public static void scheduleAll() {
        abortAll();
        System.schedule(
            JOB_NAME,
            CRON_NIGHTLY,
            new RejoiningReminderScheduler()
        );
    }

    /**
     * @description Aborts every scheduled job registered under JOB_NAME.
     */
    public static void abortAll() {

        for (CronTrigger job : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
        ]) {
            System.abortJob(job.Id);
        }
    }
}
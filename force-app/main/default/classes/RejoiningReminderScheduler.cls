@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class RejoiningReminderScheduler implements Schedulable {

    private static final String CRON_MONDAY_1AM = '0 0 1 ? * MON';

    private static final String JOB_NAME = 'Rejoining_Reminder_Weekly';

    private static final String LEGACY_JOB_NAME = 'Rejoining_Reminder_Nightly';

    private static final Integer SCOPE_SIZE = 50;

    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new RejoiningReminderBatch(), SCOPE_SIZE);
    }

    public static void scheduleAll() {
        abortAll();
        System.schedule(
            JOB_NAME,
            CRON_MONDAY_1AM,
            new RejoiningReminderScheduler()
        );
    }

    public static void abortAll() {

        for (CronTrigger job : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name IN :new List<String>{
                JOB_NAME,
                LEGACY_JOB_NAME
            }
        ]) {
            System.abortJob(job.Id);
        }
    }
}
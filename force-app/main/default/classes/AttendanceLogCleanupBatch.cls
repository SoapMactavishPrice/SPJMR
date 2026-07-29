/**
 * @description Batch job that purges old, already-synced attendance logs.
 *              Deletes every Attendance_Log__c with Status__c = 'Synced' whose
 *              Log_Date_Time__c is older than the retention window (2 days).
 *              Runs in system mode as a scheduled cleanup, so CRUD/FLS checks
 *              are intentionally bypassed.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class AttendanceLogCleanupBatch implements Database.Batchable<SObject> {

    /** Number of days of Synced logs to retain before they are eligible for deletion. */
    // private static final Integer RETENTION_DAYS = 7; // old retention window
    private static final Integer RETENTION_DAYS = 2;

    /**
     * @description Selects Synced logs older than the retention window.
     * @param bc the batch context
     * @return query locator over the Attendance_Log__c records to delete
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Cutoff = start of the day RETENTION_DAYS ago. Anything older is purged.
        Datetime cutoff = Datetime.newInstance(
            Date.today().addDays(-RETENTION_DAYS),
            Time.newInstance(0, 0, 0, 0)
        );

        return Database.getQueryLocator([
            SELECT Id
            FROM Attendance_Log__c
            WHERE Status__c = 'Synced'
            AND Log_Date_Time__c < :cutoff
        ]);
    }

    /**
     * @description Deletes the supplied chunk of logs, tolerating partial failures.
     * @param bc the batch context
     * @param scope the chunk of Attendance_Log__c records to delete
     */
    public void execute(Database.BatchableContext bc, List<Attendance_Log__c> scope) {
        Database.delete(scope, false);
    }

    /**
     * @description Required by Database.Batchable; cleanup needs no post-processing.
     * @param bc the batch context
     */
    @SuppressWarnings('PMD.EmptyStatementBlock')
    public void finish(Database.BatchableContext bc) {
        // No post-processing required for the cleanup job.
    }
}
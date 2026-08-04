/**
 * @description Purges Attendance_Log__c rows older than RETENTION_DAYS, any status.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class AttendanceLogCleanupBatch implements Database.Batchable<SObject> {

    private static final Integer RETENTION_DAYS = 5;

    /**
     * @description Selects logs older than the retention window.
     * @param bc the batch context
     * @return query locator over the Attendance_Log__c records to delete
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime cutoff = Datetime.newInstance(
            Date.today().addDays(-RETENTION_DAYS),
            Time.newInstance(0, 0, 0, 0)
        );

        return Database.getQueryLocator([
            SELECT Id
            FROM Attendance_Log__c
            WHERE Log_Date_Time__c < :cutoff
        ]);
    }

    /**
     * @description Deletes the supplied chunk, tolerating partial failures.
     * @param bc the batch context
     * @param scope the chunk of Attendance_Log__c records to delete
     */
    public void execute(Database.BatchableContext bc, List<Attendance_Log__c> scope) {
        Database.delete(scope, false);
    }

    /**
     * @description Required by Database.Batchable; no post-processing needed.
     * @param bc the batch context
     */
    @SuppressWarnings('PMD.EmptyStatementBlock')
    public void finish(Database.BatchableContext bc) {
    }
}
/**
 * @class   AttendanceBackfillController
 * @purpose Aura/LWC entry point for the "Run Attendance Backfill" button.
 *          Fires AttendanceBackfillBatch and returns the AsyncApexJob Id so the
 *          UI can show / poll status.
 */
public with sharing class AttendanceBackfillController {

    private static final Integer BATCH_SIZE = 200;

    @AuraEnabled
    public static Id runBackfill() {
        // Guard: don't stack duplicate backfill runs.
        Integer running = [
            SELECT COUNT()
            FROM   AsyncApexJob
            WHERE  ApexClass.Name = 'AttendanceBackfillBatch'
              AND  Status IN ('Queued', 'Processing', 'Preparing', 'Holding')
        ];
        if (running > 0) {
            throw new AuraHandledException(
                'An attendance backfill is already running. Please wait for it to finish.');
        }
        return Database.executeBatch(new AttendanceBackfillBatch(), BATCH_SIZE);
    }

    @AuraEnabled(cacheable=false)
    public static JobStatus getJobStatus(Id jobId) {
        AsyncApexJob job = [
            SELECT Id, Status, JobItemsProcessed, TotalJobItems,
                   NumberOfErrors, ExtendedStatus, CompletedDate
            FROM   AsyncApexJob
            WHERE  Id = :jobId
            LIMIT 1
        ];
        JobStatus s = new JobStatus();
        s.status            = job.Status;
        s.itemsProcessed    = job.JobItemsProcessed;
        s.totalItems        = job.TotalJobItems;
        s.numberOfErrors    = job.NumberOfErrors;
        s.extendedStatus    = job.ExtendedStatus;
        s.isDone            = (job.CompletedDate != null);
        return s;
    }

    public class JobStatus {
        @AuraEnabled public String  status;
        @AuraEnabled public Integer itemsProcessed;
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public Integer numberOfErrors;
        @AuraEnabled public String  extendedStatus;
        @AuraEnabled public Boolean isDone;
    }
}
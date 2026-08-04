@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class DaySyncJobTracker {

    private static final String MARK_BATCH_NAME  = 'AttendanceBackfillBatch';
    private static final String FETCH_BATCH_NAME = 'BiometricAttendanceBatch';
    private static final String STATUS_COMPLETED = 'Completed';

    private static final Set<String> JOB_DONE =
        new Set<String>{ 'Completed', 'Failed', 'Aborted' };

    private static final Set<String> JOB_ACTIVE =
        new Set<String>{ 'Queued', 'Processing', 'Preparing', 'Holding' };

    public static AsyncApexJob load(Id jobId) {
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, ExtendedStatus, CompletedDate
            FROM   AsyncApexJob
            WHERE  Id = :jobId
            LIMIT  1
        ];
        return jobs.isEmpty() ? null : jobs[0];
    }

    public static Boolean isDone(AsyncApexJob job) {
        return job != null && JOB_DONE.contains(job.Status);
    }


    public static Boolean isCompleted(AsyncApexJob job) {
        return job != null && STATUS_COMPLETED.equals(job.Status);
    }


    public static Boolean isAnySyncRunning() {
        Integer running = [
            SELECT COUNT()
            FROM   AsyncApexJob
            WHERE  ApexClass.Name IN (:FETCH_BATCH_NAME, :MARK_BATCH_NAME)
              AND  Status IN :JOB_ACTIVE
        ];
        return running > 0;
    }
}
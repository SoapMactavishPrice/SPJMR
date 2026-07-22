/**
 * Handles Division_Enrollment__c after-insert: enqueues asynchronous session assignment so a
 * newly enrolled student is added to the sessions already scheduled for their division.
 *
 * The work is done asynchronously (SessionAssignmentQueueable) to keep it out of the enrollment
 * transaction — this avoids the lock contention that occurs when assignment runs synchronously
 * alongside the session-publish automation, and lets failures retry / surface instead of being
 * silently dropped.
 */
public without sharing class DivisionEnrollmentTriggerHandler {

    /**
     * Enqueues session assignment for the newly inserted division enrollments.
     *
     * @param newEnrollments Trigger.new Division_Enrollment__c records.
     */
    public static void handleAfterInsert(List<Division_Enrollment__c> newEnrollments) {
        if (newEnrollments == null || newEnrollments.isEmpty()) {
            return;
        }
        Set<Id> enrollmentIds = new Set<Id>();
        for (Division_Enrollment__c de : newEnrollments) {
            if (de != null && de.Id != null
                    && de.Division__c != null
                    && de.Academic_Term_Enrollment__c != null) {
                enrollmentIds.add(de.Id);
            }
        }
        if (enrollmentIds.isEmpty()) {
            return;
        }
        // Guard the queueable-per-transaction limit (e.g. when enrollments are inserted from
        // another async/queueable context); skipping is safe — the records simply are not auto-assigned.
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }
        System.enqueueJob(new SessionAssignmentQueueable(enrollmentIds));
    }
}
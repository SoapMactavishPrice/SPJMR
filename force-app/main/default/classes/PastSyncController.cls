/**
 * @class   PastSyncController
 * @purpose Controller for the PastSync Visualforce page, which backs the
 *          "Past Sync" list-view button on Attendance_Log__c.
 *
 *          On page load it fires AttendanceBackfillBatch (via the existing
 *          AttendanceBackfillController.runBackfill guard) to re-evaluate
 *          attendance for the last 15 days from pending biometric logs, then
 *          shows the user a success / error message.
 */
public with sharing class PastSyncController {

    public String  resultMessage { get; private set; }
    public Boolean isSuccess     { get; private set; }

    public PastSyncController() {
        isSuccess = false;
    }

    // Invoked on page load via the <apex:page action="{!run}"> attribute.
    public PageReference run() {
        try {
            Id jobId = AttendanceBackfillController.runBackfill();
            isSuccess     = true;
            resultMessage = 'Past Sync started. Attendance for the last 15 days is being '
                + 're-evaluated from pending biometric logs in the background. (Job Id: '
                + jobId + ')';
        } catch (Exception e) {
            isSuccess     = false;
            resultMessage = 'Could not start Past Sync: ' + e.getMessage();
        }
        return null;
    }
}
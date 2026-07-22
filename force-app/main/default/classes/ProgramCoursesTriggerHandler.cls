/**
 * Keeps {@code LMS_Course__c} in sync with {@code Is_Host_Course__c} on
 * {@code Program_Courses__c}: when host is true, the LMS course lookup is the same
 * (self) record; when host is false, the lookup is cleared.
 */
public with sharing class ProgramCoursesTriggerHandler {
    /**
     * After insert: apply LMS self-lookup for host course rows.
     *
     * @param newRows Trigger.new from {@code after insert}.
     */
    public static void handleAfterInsert(List<Program_Courses__c> newRows) {
        if (newRows == null || newRows.isEmpty()) {
            return;
        }
        processLmsForHost(newRows);
    }

    /**
     * After update: re-apply when host or LMS state still needs correction.
     *
     * @param newRows Trigger.new from {@code after update}.
     */
    public static void handleAfterUpdate(List<Program_Courses__c> newRows) {
        if (newRows == null || newRows.isEmpty()) {
            return;
        }
        processLmsForHost(newRows);
    }

    private static void processLmsForHost(List<Program_Courses__c> newRows) {
        List<Program_Courses__c> toUpdate = new List<Program_Courses__c>();
        for (Program_Courses__c pc : newRows) {
            if (pc == null) {
                continue;
            }
            if (pc.Is_Host_Course__c == true) {
                if (pc.LMS_Course__c != pc.Id) {
                    toUpdate.add(new Program_Courses__c(Id = pc.Id, LMS_Course__c = pc.Id));
                }
            } else {
                if (pc.LMS_Course__c != null) {
                    toUpdate.add(new Program_Courses__c(Id = pc.Id, LMS_Course__c = null));
                }
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
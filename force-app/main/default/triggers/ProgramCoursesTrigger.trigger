/**
 * Synchronises {@code LMS_Course__c} when {@code Is_Host_Course__c} is set.
 */
trigger ProgramCoursesTrigger on Program_Courses__c(after insert, after update, before insert, before update) {
        //SPJIMR_ProgramCodeCopyHandler.syncProgramCourses(Trigger.new, Trigger.oldMap);

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            ProgramCoursesTriggerHandler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            ProgramCoursesTriggerHandler.handleAfterUpdate(Trigger.new);
        }
    }
}
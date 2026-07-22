/**
 * @description Trigger on Program_Courses__c to delegate all logic to the handler class.
 */
trigger SPJIMR_ProgramCourseTrigger on Program_Courses__c (after insert, after update, before insert, before update,before delete) {
    if (Trigger.isAfter && Trigger.isInsert) {
        //ProgramCourseTriggerHandler.createInstructorRecords(Trigger.new);
    }
    if(Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate))
        SPJIMR_ProgramCodeCopyHandler.syncProgramCourses(Trigger.new, Trigger.oldMap);
    
    if(Trigger.isBefore && Trigger.isDelete){
        SPJIMR_ProgramCodeCopyHandler.preventProgramCourseDelete(Trigger.old);  
    }
}
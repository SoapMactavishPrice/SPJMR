trigger ProgramCourseTrigger on Program_Courses__c (before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        ProgramCourseHandler.preventDuplicates(Trigger.new);
    }
}
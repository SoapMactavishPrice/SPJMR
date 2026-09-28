/**
 * @description Trigger on Program_Courses__c to delegate all logic to the handler class.
 */
trigger SPJIMR_ProgramCourseTrigger on Program_Courses__c (after insert, after update, before insert, before update,before delete) {
    if (Trigger.isAfter && Trigger.isInsert) {
        //ProgramCourseTriggerHandler.createInstructorRecords(Trigger.new);
    }
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {

        Map<Id, String> newCodes = new Map<Id, String>();
        Map<Id, String> oldCodes = new Map<Id, String>();

        for (Program_Courses__c record : Trigger.new) {
            newCodes.put(
                record.Id,
                record.Program_Code__c
            );
        }

        if (Trigger.isUpdate) {
            for (Program_Courses__c record : Trigger.old) {
                oldCodes.put(
                    record.Id,
                    record.Program_Code__c
                );
            }
        }

        ProgrammeSharingService.shareRecords(
            'Program_Courses__c',
            newCodes,
            Trigger.isUpdate ? oldCodes : null
        );
    }
    if(Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate))
        SPJIMR_ProgramCodeCopyHandler.syncProgramCourses(Trigger.new, Trigger.oldMap);
    
    if(Trigger.isBefore && Trigger.isDelete){
        SPJIMR_ProgramCodeCopyHandler.preventProgramCourseDelete(Trigger.old);  
    }
}
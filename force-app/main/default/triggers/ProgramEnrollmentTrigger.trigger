trigger ProgramEnrollmentTrigger on ProgramEnrollment (before insert, before update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        ProgramEnrollmentTriggerHandler handler = new ProgramEnrollmentTriggerHandler();  
        handler.beforeInsert(Trigger.new, Trigger.newMap);  
       }
        if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
               SPJIMR_ProgramCodeCopyHandler.syncProgramEnrollment(Trigger.new, Trigger.oldMap);

        }

}
trigger BatchGroupTrigger on AcademicYear (before insert, before update, after insert, before delete) {
    
   if (Trigger.isBefore && Trigger.isInsert) {
    //    BatchGroupCreateHandler.populateOriginalNumber(Trigger.new);
    //   BatchGroupGapFillHandler.BatchGroupTriggerHandler(Trigger.new);
       SPJIMR_AcademicYearTriggerHandler.syncProgramCodeFromProgram(Trigger.new, null);
       BatchGroupTriggerHandler.handleBeforeInsert(Trigger.new);
       BatchGroupTriggerHandler.validateUniqueNames( Trigger.new, null );
       BatchGroupTriggerHandler.setBatchGroupCurrency(Trigger.new);
   }
    
    if (Trigger.isBefore && Trigger.isUpdate) {
        SPJIMR_AcademicYearTriggerHandler.syncProgramCodeFromProgram(Trigger.new, Trigger.oldMap);
        BatchGroupTriggerHandler.validateUniqueNames(Trigger.new, Trigger.oldMap );
    }

        
    if (Trigger.isBefore){
        if (Trigger.isDelete) {
            BatchGroupDeleteHandler.preventDeleteIfTermsExist(Trigger.old);
        }
    }
// if (Trigger.isAfter) {

    //    if (Trigger.isDelete) {
     //       BatchGroupRenumberHandler.renumberAfterDelete(Trigger.old);
     //   }
     
   //  if (Trigger.isAfter && Trigger.isUndelete) {
   //     BatchGroupRenumberHandler.renumberAfterRestore();
   // }
   // }
    
    
}
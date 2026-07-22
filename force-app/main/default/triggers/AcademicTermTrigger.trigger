trigger AcademicTermTrigger on AcademicTerm (
   
    before insert,
    before update,
    after insert,
    after update,
    after delete,
    after undelete
) {
    if (Trigger.isBefore) {

        RollupTriggerHandler.validateTermDateOverlap(
            Trigger.new
        );
    }

    RollupTriggerHandler.updateBatchLevelDataFromTerms(
        Trigger.isDelete ? Trigger.old : Trigger.new
    );
}
trigger ProgramTeamMemberTrigger on Program_Team_Members__c (
   before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {/*
    ProgramTeamMemberTriggerHandler handler = new ProgramTeamMemberTriggerHandler();

    if (Trigger.isAfter) {
        if (Trigger.isInsert) handler.afterInsert(Trigger.new, Trigger.newMap);
        if (Trigger.isUpdate) handler.afterUpdate(Trigger.new, Trigger.newMap, Trigger.old, Trigger.oldMap);
        if (Trigger.isDelete) handler.afterDelete(Trigger.old, Trigger.oldMap);
        if (Trigger.isUndelete) handler.afterInsert(Trigger.new, Trigger.newMap);
    } */

    // ===== Leave Programme Office queue sync (added) =====
    // Keep the "Leave Programme Office" queue membership aligned with users whose
    // Role__c = 'Programme Office', so the approval Step 1 approver list stays dynamic.
    if (Trigger.isAfter) {
        LeaveProgrammeOfficeQueueSync.handle(Trigger.new, Trigger.old);
    }
}
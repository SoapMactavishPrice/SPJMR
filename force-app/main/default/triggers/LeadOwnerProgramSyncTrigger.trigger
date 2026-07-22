trigger LeadOwnerProgramSyncTrigger on Lead (after update) {
    LeadProgramOwnerSyncHandler.syncLeadProgramOwners(Trigger.new, Trigger.oldMap);
}
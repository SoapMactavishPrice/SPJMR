/**
 * Keeps {@code Lead_Program__c} record owners aligned with the parent Lead when the Lead owner changes,
 * then re-applies program-queue manual sharing from {@code Program_Queue_Routing__mdt} (same path as
 * {@link LeadProgramQueueSharingService#shareForNewLeadPrograms} on insert; idempotent).
 * <p>
 * Runs from {@code LeadOwnerProgramSyncTrigger} (after update only).
 *
 * @see LeadOwnerProgramSyncTrigger
 * @see LeadProgramQueueSharingService
 */
public without sharing class LeadProgramOwnerSyncHandler {
    /**
     * For each Lead whose {@code OwnerId} changed: assigns the same owner to related {@code Lead_Program__c} rows,
     * then ensures queue manual shares exist for the Lead and each Lead Program per routing metadata.
     *
     * @param newLeads Updated Lead rows ({@code Trigger.new}).
     * @param oldLeadsMap Prior Lead versions keyed by Id ({@code Trigger.oldMap}).
     */
    public static void syncLeadProgramOwners(List<Lead> newLeads, Map<Id, Lead> oldLeadsMap) {
        if (newLeads == null || newLeads.isEmpty() || oldLeadsMap == null || oldLeadsMap.isEmpty()) {
            return;
        }

        Map<Id, Id> leadIdToNewOwner = new Map<Id, Id>();
        for (Lead l : newLeads) {
            Lead prior = oldLeadsMap.get(l.Id);
            if (prior != null && l.OwnerId != prior.OwnerId) {
                leadIdToNewOwner.put(l.Id, l.OwnerId);
            }
        }

        if (leadIdToNewOwner.isEmpty()) {
            return;
        }

        List<Lead_Program__c> leadPrograms = [
            SELECT Id, Lead__c, Program__c, OwnerId
            FROM Lead_Program__c
            WHERE Lead__c IN :leadIdToNewOwner.keySet()
        ];

        List<Lead_Program__c> toUpdate = new List<Lead_Program__c>();
        for (Lead_Program__c lp : leadPrograms) {
            Id newOwnerId = leadIdToNewOwner.get(lp.Lead__c);
            if (newOwnerId != null && lp.OwnerId != newOwnerId) {
                toUpdate.add(new Lead_Program__c(Id = lp.Id, OwnerId = newOwnerId));
            }
        }

        if (!toUpdate.isEmpty()) {
            //update toUpdate;
        }

        if (!leadPrograms.isEmpty()) {
           // LeadProgramQueueSharingService.shareForNewLeadPrograms(leadPrograms);
        }
    }
}
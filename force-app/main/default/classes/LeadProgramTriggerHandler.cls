/**
 * Entry point for {@code Lead_Program__c} automation: B2C default Lead_Program owner (before insert),
 * {@code Lead_Program__c} round robin (after insert; {@code Lead} owner unchanged by that step),
 * aggregated program codes on Lead,
 * program-queue manual sharing, and verification email (skipped during tests).
 *
 * @see LeadProgramTrigger
 * @see LeadProgramTriggerHelper
 * @see LeadProgramQueueSharingService
 * @see LeadProgramCodesAggregationService (B2C Leads: {@code All_Program_Codes__c})
 */
public class LeadProgramTriggerHandler {

    public void beforeInsert(List<Lead_Program__c> newRows) {
        LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured(newRows);
        LeadProgramTriggerHelper.stampProgramCodeFromProgram(newRows, null);
    }

    /**
     * Keeps {@code Program_Code__c} aligned when {@code Program__c} changes.
     *
     * @param newRows Trigger {@code Trigger.new}.
     * @param oldMap Trigger {@code Trigger.oldMap}.
     */
    public void beforeUpdate(List<Lead_Program__c> newRows, Map<Id, Lead_Program__c> oldMap, Map<Id, Lead_Program__c> newMap) {
        LeadProgramTriggerHelper.stampProgramCodeFromProgram(newRows, oldMap);
        LeadProgramTriggerHelper.shareLeadwithLpOwner(oldMap, newMap);
    }

    /**
     * Runs post-insert processing for the given lead program rows.
     *
     * @param newRows Trigger {@code Trigger.new} list.
     * @param newMap Trigger {@code Trigger.newMap} (reserved for future use / symmetry with other handlers).
     */
    public void afterInsert(List<Lead_Program__c> newRows, Map<Id, Lead_Program__c> newMap) {
        try {
            B2CLeadProgramRoundRobinService.applyAfterLeadProgramInsert(newRows);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'B2CLeadProgramRoundRobinService: ' + e);
        }
        syncB2cLeadProgramCodes(newRows);
        //LeadProgramTriggerHelper.backfillProgramMasterOnB2cLead(newRows);
       // LeadProgramQueueSharingService.shareForNewLeadPrograms(newRows);
        if (!Test.isRunningTest()) {
            LeadProgramTriggerHelper.sendVerificationEmail(newRows);
        }
    }

    /**
     * Refreshes {@code Lead.All_Program_Codes__c} (B2C only) when junction rows change program or lead.
     *
     * @param newRows Updated lead program rows.
     * @param oldMap Prior field values by Id.
     */
    public void afterUpdate(List<Lead_Program__c> newRows, Map<Id, Lead_Program__c> oldMap) {
        Set<Id> leadIds = new Set<Id>();
        for (Lead_Program__c lp : newRows) {
            Lead_Program__c old = oldMap.get(lp.Id);
            if (old == null) {
                continue;
            }
            if (lp.Lead__c != old.Lead__c || lp.Program__c != old.Program__c) {
                if (lp.Lead__c != null) {
                    leadIds.add(lp.Lead__c);
                }
                if (old.Lead__c != null) {
                    leadIds.add(old.Lead__c);
                }
            }
        }
        if (!leadIds.isEmpty()) {
            LeadProgramCodesAggregationService.syncAggregatedProgramCodes(leadIds);
        }
    }

    /**
     * Refreshes {@code Lead.All_Program_Codes__c} (B2C only) after junction deletes.
     *
     * @param oldRows Deleted lead program rows.
     */
    public void afterDelete(List<Lead_Program__c> oldRows) {
        Set<Id> leadIds = new Set<Id>();
        for (Lead_Program__c lp : oldRows) {
            if (lp.Lead__c != null) {
                leadIds.add(lp.Lead__c);
            }
        }
        if (!leadIds.isEmpty()) {
            LeadProgramCodesAggregationService.syncAggregatedProgramCodes(leadIds);
        }
    }

    private static void syncB2cLeadProgramCodes(List<Lead_Program__c> newRows) {
        Set<Id> leadIds = new Set<Id>();
        for (Lead_Program__c lp : newRows) {
            if (lp.Lead__c != null) {
                leadIds.add(lp.Lead__c);
            }
        }
        if (!leadIds.isEmpty()) {
            LeadProgramCodesAggregationService.syncAggregatedProgramCodes(leadIds);
        }
    }
}
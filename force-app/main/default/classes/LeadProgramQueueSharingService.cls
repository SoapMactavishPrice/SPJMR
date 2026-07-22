/**
 * Grants program queues access to B2C leads and specific Lead Program rows via manual sharing.
 * <p>
 * Queue routing uses {@code Program_Queue_Routing__mdt} matched to {@code Program.Program_Code__c}.
 * Declared {@code without sharing} so share rows can be inserted regardless of the running user’s visibility.
 *
 * @see LeadRoutingService
 * @see Program_Queue_Routing__mdt
 * @see LeadProgramTriggerHandler
 * @see SPJIMRUtility
 * @see ProgramQueueRoutingService
 */
public without sharing class LeadProgramQueueSharingService {
    private static final String LEAD_PROGRAM_SHARE_OBJECT = 'Lead_Program__Share';
    private static final String MANUAL = 'Manual';
    private static final String ACCESS_EDIT = 'Edit';

    /**
     * For each new {@code Lead_Program__c}, ensures the program’s queue has manual shares on the parent Lead
     * and on that Lead Program row (idempotent; bulk SOQL/DML only).
     *
     * @param newRows Records from {@code Lead_Program__c} after insert (must include {@code Id}).
     */
    public static void shareForNewLeadPrograms(List<Lead_Program__c> newRows) {
        if (newRows != null && !newRows.isEmpty()) {
            Set<Id> programIds = new Set<Id>();
            Set<Id> leadIds = new Set<Id>();
            Set<Id> lpIds = new Set<Id>();
            collectLeadProgramReferenceIds(newRows, programIds, leadIds, lpIds);
            if (!programIds.isEmpty() && !leadIds.isEmpty() && !lpIds.isEmpty()) {
                Map<Id, String> programIdToCode = loadProgramIdToCodeMap(programIds);
                Set<String> codes = new Set<String>(programIdToCode.values());
                Map<String, Id> codeToQueueId = ProgramQueueRoutingService.resolveProgramCodeToQueueIdMap(codes);
                Set<Id> queueIds = nonNullIdsFromValues(codeToQueueId.values());
                if (!queueIds.isEmpty()) {
                    Set<Id> validQueueIds = loadValidQueueIds(queueIds);
                    if (!validQueueIds.isEmpty()) {
                        insertSharesForResolvedQueues(
                            newRows,
                            programIdToCode,
                            codeToQueueId,
                            validQueueIds,
                            leadIds,
                            lpIds
                        );
                    }
                }
            }
        }
    }

    /**
     * Populates program, lead, and lead-program Id sets from the trigger batch.
     *
     * @param newRows Source lead program rows.
     * @param programIds Output: {@code Program__c} Ids.
     * @param leadIds Output: parent {@code Lead__c} Ids.
     * @param lpIds Output: {@code Lead_Program__c} Ids.
     */
    private static void collectLeadProgramReferenceIds(
        List<Lead_Program__c> newRows,
        Set<Id> programIds,
        Set<Id> leadIds,
        Set<Id> lpIds
    ) {
        for (Lead_Program__c lp : newRows) {
            if (lp.Program__c != null) {
                programIds.add(lp.Program__c);
            }
            if (lp.Lead__c != null) {
                leadIds.add(lp.Lead__c);
            }
            if (lp.Id != null) {
                lpIds.add(lp.Id);
            }
        }
    }

    /**
     * Loads {@code Program.Program_Code__c} for the given program Ids (single query).
     *
     * @param programIds Program record Ids to resolve.
     * @return Map of program Id to trimmed program code; programs without code are omitted.
     */
    private static Map<Id, String> loadProgramIdToCodeMap(Set<Id> programIds) {
        Map<Id, String> programIdToCode = new Map<Id, String>();
        for (Program pr : [SELECT Id, Program_Code__c FROM Program WHERE Id IN :programIds]) {
            if (String.isNotBlank(pr.Program_Code__c)) {
                programIdToCode.put(pr.Id, pr.Program_Code__c.trim());
            }
        }
        return programIdToCode;
    }

    /**
     * Collects non-null queue Ids from a map’s values.
     *
     * @param values Iterable of candidate queue Ids (may include null).
     * @return Set without null entries.
     */
    private static Set<Id> nonNullIdsFromValues(Iterable<Id> values) {
        Set<Id> queueIds = new Set<Id>();
        for (Id q : values) {
            if (q != null) {
                queueIds.add(q);
            }
        }
        return queueIds;
    }

    /**
     * Returns subset of Ids that are Salesforce queues ({@code Group.Type = 'Queue'}).
     *
     * @param queueIds Candidate group Ids from metadata or tests.
     * @return Valid queue Ids only.
     */
    private static Set<Id> loadValidQueueIds(Set<Id> queueIds) {
        Set<Id> validQueueIds = new Set<Id>();
        for (Group g : [SELECT Id FROM Group WHERE Id IN :queueIds AND Type = 'Queue']) {
            validQueueIds.add(g.Id);
        }
        return validQueueIds;
    }

    /**
     * Builds share rows and performs up to two bulk inserts (LeadShare, then Lead_Program__Share).
     *
     * @param newRows Same batch as the trigger.
     * @param programIdToCode Program Id to program code.
     * @param codeToQueueId Program code to queue Id from routing.
     * @param validQueueIds Queues confirmed to exist as queues.
     * @param leadIds All parent lead Ids in the batch (for existing-share query).
     * @param lpIds All lead program Ids in the batch (for existing-share query).
     */
    private static void insertSharesForResolvedQueues(
        List<Lead_Program__c> newRows,
        Map<Id, String> programIdToCode,
        Map<String, Id> codeToQueueId,
        Set<Id> validQueueIds,
        Set<Id> leadIds,
        Set<Id> lpIds
    ) {
        Set<String> existingLeadKeys = loadLeadShareKeys(leadIds, validQueueIds);
        Set<String> existingLpKeys = loadLeadProgramShareKeys(lpIds, validQueueIds);
        List<LeadShare> leadShares = new List<LeadShare>();
        List<SObject> lpShares = new List<SObject>();
        for (Lead_Program__c lp : newRows) {
            appendSharesForLeadProgramRow(
                lp,
                programIdToCode,
                codeToQueueId,
                validQueueIds,
                existingLeadKeys,
                existingLpKeys,
                leadShares,
                lpShares
            );
        }
        insertShareListsIfNotEmpty(leadShares, lpShares);
    }

    /**
     * Appends manual share rows for one lead program when routing and data are complete.
     *
     * @param lp Lead program row.
     * @param programIdToCode Program Id to code map.
     * @param codeToQueueId Code to target queue Id.
     * @param validQueueIds Allowed queue Ids.
     * @param existingLeadKeys Keys for Lead shares already present or queued in this run.
     * @param existingLpKeys Keys for Lead Program shares already present or queued in this run.
     * @param leadShares Output list for new {@code LeadShare} rows.
     * @param lpShares Output list for new {@code Lead_Program__Share} rows.
     */
    private static void appendSharesForLeadProgramRow(
        Lead_Program__c lp,
        Map<Id, String> programIdToCode,
        Map<String, Id> codeToQueueId,
        Set<Id> validQueueIds,
        Set<String> existingLeadKeys,
        Set<String> existingLpKeys,
        List<LeadShare> leadShares,
        List<SObject> lpShares
    ) {
        if (lp.Lead__c != null && lp.Id != null && lp.Program__c != null) {
            String code = programIdToCode.get(lp.Program__c);
            if (String.isNotBlank(code)) {
                Id queueId = codeToQueueId.get(code);
                if (queueId != null && validQueueIds.contains(queueId)) {
                    addLeadShareIfNew(lp.Lead__c, queueId, existingLeadKeys, leadShares);
                    addLeadProgramShareIfNew(lp.Id, queueId, existingLpKeys, lpShares);
                }
            }
        }
    }

    /**
     * Adds a {@code LeadShare} for lead + queue if that pair is not already shared.
     *
     * @param leadId Parent lead Id.
     * @param queueId Target queue ({@code Group}) Id.
     * @param existingLeadKeys In/out set of composite keys to avoid duplicates.
     * @param leadShares List to append new share rows.
     */
    private static void addLeadShareIfNew(
        Id leadId,
        Id queueId,
        Set<String> existingLeadKeys,
        List<LeadShare> leadShares
    ) {
        String leadKey = shareKey(leadId, queueId);
        if (!existingLeadKeys.contains(leadKey)) {
            leadShares.add(buildLeadShare(leadId, queueId));
            existingLeadKeys.add(leadKey);
        }
    }

    /**
     * Adds a {@code Lead_Program__Share} for lead program + queue if missing.
     *
     * @param leadProgramId Lead program record Id.
     * @param queueId Target queue Id.
     * @param existingLpKeys In/out set of composite keys to avoid duplicates.
     * @param lpShares List to append new share rows.
     */
    private static void addLeadProgramShareIfNew(
        Id leadProgramId,
        Id queueId,
        Set<String> existingLpKeys,
        List<SObject> lpShares
    ) {
        String lpKey = shareKey(leadProgramId, queueId);
        if (!existingLpKeys.contains(lpKey)) {
            SObject lpShare = buildLeadProgramShare(leadProgramId, queueId);
            if (lpShare != null) {
                lpShares.add(lpShare);
                existingLpKeys.add(lpKey);
            }
        }
    }

    /**
     * Performs bulk insert for non-empty share lists.
     *
     * @param leadShares Manual lead shares to insert.
     * @param lpShares Manual lead program shares to insert.
     */
    private static void insertShareListsIfNotEmpty(List<LeadShare> leadShares, List<SObject> lpShares) {
        if (!leadShares.isEmpty()) {
            insert leadShares;
        }
        if (!lpShares.isEmpty()) {
            insert lpShares;
        }
    }

    /**
     * Loads composite keys for existing manual {@code LeadShare} rows (bulk query).
     *
     * @param leadIds Parent lead Ids.
     * @param queueIds Candidate queue Ids.
     * @return Set of {@code shareKey(leadId, queueId)} strings.
     */
    private static Set<String> loadLeadShareKeys(Set<Id> leadIds, Set<Id> queueIds) {
        Set<String> keys = new Set<String>();
        if (!leadIds.isEmpty() && !queueIds.isEmpty()) {
            for (LeadShare ls : [
                SELECT LeadId, UserOrGroupId
                FROM LeadShare
                WHERE LeadId IN :leadIds AND UserOrGroupId IN :queueIds AND RowCause = :MANUAL
            ]) {
                keys.add(shareKey(ls.LeadId, ls.UserOrGroupId));
            }
        }
        return keys;
    }

    /**
     * Loads composite keys for existing manual {@code Lead_Program__Share} rows when the object exists.
     *
     * @param lpIds Lead program Ids.
     * @param queueIds Candidate queue Ids.
     * @return Set of {@code shareKey(parentId, queueId)} strings.
     */
    private static Set<String> loadLeadProgramShareKeys(Set<Id> lpIds, Set<Id> queueIds) {
        Set<String> keys = new Set<String>();
        if (!lpIds.isEmpty() && !queueIds.isEmpty() && Schema.getGlobalDescribe().containsKey(LEAD_PROGRAM_SHARE_OBJECT)) {
            String soql =
                'SELECT ParentId, UserOrGroupId FROM Lead_Program__Share WHERE ParentId IN :lpIds AND UserOrGroupId IN :queueIds AND RowCause = :MANUAL';
            for (SObject row : Database.query(soql)) {
                keys.add(shareKey((Id) row.get('ParentId'), (Id) row.get('UserOrGroupId')));
            }
        }
        return keys;
    }

    /**
     * Builds a manual {@code LeadShare} row (Edit access).
     *
     * @param leadId Lead Id ({@code LeadShare.LeadId}).
     * @param queueId Queue ({@code UserOrGroupId}).
     * @return Configured share row (not inserted).
     */
    private static LeadShare buildLeadShare(Id leadId, Id queueId) {
        LeadShare ls = new LeadShare();
        ls.LeadId = leadId;
        ls.UserOrGroupId = queueId;
        ls.LeadAccessLevel = ACCESS_EDIT;
        ls.RowCause = MANUAL;
        return ls;
    }

    /**
     * Builds a manual {@code Lead_Program__Share} row when the share object is available.
     *
     * @param leadProgramId {@code Lead_Program__c} Id ({@code ParentId} on share).
     * @param queueId Queue Id.
     * @return Share sObject, or null if the share type is not deployed.
     */
    private static SObject buildLeadProgramShare(Id leadProgramId, Id queueId) {
        SObject sh = null;
        Schema.SObjectType shareType = Schema.getGlobalDescribe().get(LEAD_PROGRAM_SHARE_OBJECT);
        if (shareType != null) {
            sh = shareType.newSObject();
            sh.put('ParentId', leadProgramId);
            sh.put('UserOrGroupId', queueId);
            sh.put('AccessLevel', ACCESS_EDIT);
            sh.put('RowCause', MANUAL);
        }
        return sh;
    }

    /**
     * Stable string key for deduplicating share rows ({@code parent + '_' + queue}).
     *
     * @param parentId Lead Id or Lead Program Id depending on share object.
     * @param groupId Queue ({@code Group}) Id.
     * @return Composite key string.
     */
    private static String shareKey(Id parentId, Id groupId) {
        return String.valueOf(parentId) + '_' + String.valueOf(groupId);
    }

    /**
     * Test-only: delegates to {@link ProgramQueueRoutingService#setTestProgramCodeToQueueIdOverride}.
     *
     * @param mapByCode Program code to queue Id; pass null to clear.
     */
    @TestVisible
    static void setTestProgramCodeToQueueIdOverride(Map<String, Id> mapByCode) {
        ProgramQueueRoutingService.setTestProgramCodeToQueueIdOverride(mapByCode);
    }
}
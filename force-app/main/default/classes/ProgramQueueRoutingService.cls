/**
 * Resolves program queue Ids from {@code Program_Queue_Routing__mdt} using {@code Program.Program_Code__c}.
 * <p>
 * Shared by {@link LeadProgramQueueSharingService} (manual shares) and B2C Opportunity owner assignment.
 *
 * @see Program_Queue_Routing__mdt
 * @see SPJIMRUtility
 */
public with sharing class ProgramQueueRoutingService {
    @TestVisible
    private static Map<String, Id> testProgramCodeToQueueIdOverride;

    /**
     * Maps each program Id to a validated queue ({@code Group.Type = 'Queue'}) when routing metadata resolves.
     *
     * @param programIds {@code Program} Ids (e.g. from {@code Opportunity.Program__c}).
     * @return Program Id → queue Id; programs without routing or invalid queue Ids are omitted.
     */
    public static Map<Id, Id> resolveProgramIdToValidatedQueueIdMap(Set<Id> programIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (programIds == null || programIds.isEmpty()) {
            return result;
        }
        Map<Id, String> programIdToCode = new Map<Id, String>();
        for (Program pr : [SELECT Id, Program_Code__c FROM Program WHERE Id IN :programIds]) {
            if (String.isNotBlank(pr.Program_Code__c)) {
                programIdToCode.put(pr.Id, pr.Program_Code__c.trim());
            }
        }
        if (programIdToCode.isEmpty()) {
            return result;
        }
        Set<String> codes = new Set<String>(programIdToCode.values());
        Map<String, Id> codeToQueueId = resolveProgramCodeToQueueIdMap(codes);
        Set<Id> candidateQueues = new Set<Id>();
        for (Id q : codeToQueueId.values()) {
            if (q != null) {
                candidateQueues.add(q);
            }
        }
        if (candidateQueues.isEmpty()) {
            return result;
        }
        Set<Id> validQueueIds = new Set<Id>();
        for (Group g : [SELECT Id FROM Group WHERE Id IN :candidateQueues AND Type = 'Queue']) {
            validQueueIds.add(g.Id);
        }
        for (Id programId : programIdToCode.keySet()) {
            String code = programIdToCode.get(programId);
            Id queueId = codeToQueueId.get(code);
            if (queueId != null && validQueueIds.contains(queueId)) {
                result.put(programId, queueId);
            }
        }
        return result;
    }

    /**
     * Resolves program codes to queue Ids from test override (if set) or {@code Program_Queue_Routing__mdt}.
     *
     * @param codes {@code Program.Program_Code__c} values.
     * @return Program code → queue Id (not validated against {@code Group}).
     */
    public static Map<String, Id> resolveProgramCodeToQueueIdMap(Set<String> codes) {
        Map<String, Id> out = new Map<String, Id>();
        Boolean filledFromTest = applyTestRoutingOverrideIfApplicable(codes, out);
        if (!filledFromTest) {
            mergeRoutingFromCustomMetadata(codes, out);
        }
        return out;
    }

    /**
     * Test-only: overrides metadata for {@link #resolveProgramCodeToQueueIdMap} / program Id resolution.
     *
     * @param mapByCode Program code → queue Id; null clears override.
     */
    @TestVisible
    public static void setTestProgramCodeToQueueIdOverride(Map<String, Id> mapByCode) {
        testProgramCodeToQueueIdOverride = mapByCode == null ? null : new Map<String, Id>(mapByCode);
    }

    private static Boolean applyTestRoutingOverrideIfApplicable(Set<String> codes, Map<String, Id> out) {
        Boolean applied = false;
        if (Test.isRunningTest() && testProgramCodeToQueueIdOverride != null) {
            applied = true;
            for (String c : codes) {
                if (testProgramCodeToQueueIdOverride.containsKey(c)) {
                    out.put(c, testProgramCodeToQueueIdOverride.get(c));
                }
            }
        }
        return applied;
    }

    private static void mergeRoutingFromCustomMetadata(Set<String> codes, Map<String, Id> out) {
        if (codes != null && !codes.isEmpty()) {
            List<Program_Queue_Routing__mdt> rows = [
                SELECT Program_Code__c, Queue_Id__c, Queue_Developer_Name__c
                FROM Program_Queue_Routing__mdt
                WHERE Program_Code__c IN :codes
            ];
            putDirectQueueIdsFromMetadata(rows, out);
            putQueueIdsFromDeveloperNames(rows, out);
        }
    }

    private static void putDirectQueueIdsFromMetadata(List<Program_Queue_Routing__mdt> rows, Map<String, Id> out) {
        for (Program_Queue_Routing__mdt row : rows) {
            if (String.isNotBlank(row.Program_Code__c)) {
                String codeKey = row.Program_Code__c.trim();
                Id qid = parseQueueIdFromMetadataRow(row);
                if (qid != null) {
                    out.put(codeKey, qid);
                }
            }
        }
    }

    private static void putQueueIdsFromDeveloperNames(List<Program_Queue_Routing__mdt> rows, Map<String, Id> out) {
        Set<String> devNames = new Set<String>();
        for (Program_Queue_Routing__mdt row : rows) {
            if (String.isNotBlank(row.Program_Code__c) && String.isNotBlank(row.Queue_Developer_Name__c)) {
                String codeKey = row.Program_Code__c.trim();
                if (!out.containsKey(codeKey)) {
                    devNames.add(row.Queue_Developer_Name__c.trim());
                }
            }
        }
        if (!devNames.isEmpty()) {
            Map<String, Id> devToId = loadQueueIdsByDeveloperName(devNames);
            for (Program_Queue_Routing__mdt row : rows) {
                if (String.isNotBlank(row.Program_Code__c)) {
                    String codeKey = row.Program_Code__c.trim();
                    if (!out.containsKey(codeKey) && String.isNotBlank(row.Queue_Developer_Name__c)) {
                        Id q = devToId.get(row.Queue_Developer_Name__c.trim());
                        if (q != null) {
                            out.put(codeKey, q);
                        }
                    }
                }
            }
        }
    }

    private static Map<String, Id> loadQueueIdsByDeveloperName(Set<String> devNames) {
        Map<String, Id> devToId = new Map<String, Id>();
        for (Group g : [
            SELECT Id, DeveloperName
            FROM Group
            WHERE DeveloperName IN :devNames AND Type = 'Queue'
        ]) {
            devToId.put(g.DeveloperName, g.Id);
        }
        return devToId;
    }

    private static Id parseQueueIdFromMetadataRow(Program_Queue_Routing__mdt row) {
        Id parsed = null;
        if (row != null) {
            parsed = SPJIMRUtility.parseSalesforceId(row.Queue_Id__c);
        }
        return parsed;
    }
}
/**
 * Maintains {@code Lead.All_Program_Codes__c} for B2C leads only from {@code Lead_Program__c} rows
 * (distinct {@code Program.Program_Code__c}, sorted alphabetically, semicolon-separated, with a trailing semicolon when non-empty).
 * Non-B2C leads are never updated. The field is Text(255); longer joined strings are truncated to fit.
 */
public without sharing class LeadProgramCodesAggregationService {

    private static final Integer ALL_PROGRAM_CODES_MAX_LENGTH = 255;

    /**
     * Recomputes {@code All_Program_Codes__c} on each B2C Lead in {@code leadIds} from current junction rows.
     *
     * @param leadIds Parent lead Ids to refresh (non-B2C leads are ignored).
     */
    public static void syncAggregatedProgramCodes(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }
        Schema.RecordTypeInfo b2cRt = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        if (b2cRt == null) {
            return;
        }
        Id b2cRtId = b2cRt.getRecordTypeId();

        Map<Id, Lead> b2cLeads = new Map<Id, Lead>([
            SELECT Id
            FROM Lead
            WHERE Id IN :leadIds AND RecordTypeId = :b2cRtId
        ]);
        if (b2cLeads.isEmpty()) {
            return;
        }
        Set<Id> b2cLeadIdSet = b2cLeads.keySet();

        List<Lead_Program__c> junctions = [
            SELECT Lead__c, Program__r.Program_Code__c
            FROM Lead_Program__c
            WHERE Lead__c IN :b2cLeadIdSet
        ];

        Map<Id, Set<String>> leadToCodes = new Map<Id, Set<String>>();
        for (Id lid : b2cLeadIdSet) {
            leadToCodes.put(lid, new Set<String>());
        }
        for (Lead_Program__c lp : junctions) {
            if (lp.Program__r == null || String.isBlank(lp.Program__r.Program_Code__c)) {
                continue;
            }
            String code = lp.Program__r.Program_Code__c.trim();
            if (String.isBlank(code)) {
                continue;
            }
            if (leadToCodes.containsKey(lp.Lead__c)) {
                leadToCodes.get(lp.Lead__c).add(code);
            }
        }

        List<Lead> toUpdate = new List<Lead>();
        for (Id lid : b2cLeadIdSet) {
            Set<String> codes = leadToCodes.get(lid);
            List<String> sorted = new List<String>(codes);
            sorted.sort();
            String joined = String.join(sorted, ';');
            if (String.isNotBlank(joined)) {
                joined = joined + ';';
            }
            toUpdate.add(new Lead(Id = lid, All_Program_Codes__c = fitAllProgramCodesField(joined)));
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * Truncates the value (including optional trailing {@code ;}) to the Lead field max length (255).
     *
     * @param joined Semicolon-separated codes with trailing semicolon when non-empty; null treated as empty.
     * @return Value safe to assign to {@code All_Program_Codes__c}.
     */
    private static String fitAllProgramCodesField(String joined) {
        String result = joined == null ? '' : joined;
        if (result.length() > ALL_PROGRAM_CODES_MAX_LENGTH) {
            return result.substring(0, ALL_PROGRAM_CODES_MAX_LENGTH);
        }
        return result;
    }
}
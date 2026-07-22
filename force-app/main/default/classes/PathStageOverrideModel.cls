/**
 * Rows from {@link Path_Stage_Override__mdt}, resolved per lead using related program codes.
 */
public with sharing class PathStageOverrideModel {
    public String pathStageValueApi { get; set; }
    /** Normalized key from CMDT; null/blank in CMDT means "any program". */
    public String programCode { get; set; }
    public Boolean showOnPath { get; set; }
    public Boolean openSubStatusModal { get; set; }

    /**
     * Effective flags for one path picklist value and the lead's program codes.
     */
    public class ResolvedStageOverride {
        /** True when at least one CMDT row applies (stage match + program match or blank program). */
        public Boolean hasApplicableRules { get; set; }
        /** False if any applicable row hides the stage on the path. */
        public Boolean showOnPath { get; set; }
        /** True if any applicable row requests the sub-status modal. */
        public Boolean openSubStatusModal { get; set; }
    }

    /**
     * Loads all override rows for a path wizard config.
     */
    public static List<PathStageOverrideModel> loadRowsForConfig(String configDeveloperName) {
        List<PathStageOverrideModel> result = new List<PathStageOverrideModel>();
        if (String.isBlank(configDeveloperName)) {
            return result;
        }
        String key = configDeveloperName.trim();
        for (
            Path_Stage_Override__mdt row : [
                SELECT Path_Stage_Value_API__c, Show_On_Path__c, Open_Sub_Status_Modal__c, Program_Code__c
                FROM Path_Stage_Override__mdt
                WHERE Path_Config_Developer_Name__c = :key
            ]
        ) {
            PathStageOverrideModel m = new PathStageOverrideModel();
            m.pathStageValueApi = String.isNotBlank(row.Path_Stage_Value_API__c) ? row.Path_Stage_Value_API__c.trim() : null;
            m.programCode = String.isNotBlank(row.Program_Code__c) ? row.Program_Code__c.trim() : null;
            m.showOnPath = row.Show_On_Path__c != false;
            m.openSubStatusModal = row.Open_Sub_Status_Modal__c != false;
            result.add(m);
        }
        return result;
    }

    /**
     * Merges all rows that apply to {@code pathValue} and the lead's programs (blank program code = matches any lead).
     */
    public static ResolvedStageOverride resolveForPathValue(
        String pathValue,
        Set<String> programCodesNormalized,
        List<PathStageOverrideModel> allRows
    ) {
        ResolvedStageOverride r = new ResolvedStageOverride();
        r.hasApplicableRules = false;
        r.showOnPath = true;
        r.openSubStatusModal = false;
        if (String.isBlank(pathValue) || allRows == null || allRows.isEmpty()) {
            return r;
        }
        List<PathStageOverrideModel> applicable = new List<PathStageOverrideModel>();
        for (PathStageOverrideModel row : allRows) {
            if (String.isNotBlank(row.pathStageValueApi) && !pathValue.equals(row.pathStageValueApi)) {
                continue;
            }
            if (String.isNotBlank(row.programCode)) {
                String pc = normalizeProgramCode(row.programCode);
                if (!programCodesNormalized.contains(pc)) {
                    continue;
                }
            }
            applicable.add(row);
        }
        if (applicable.isEmpty()) {
            return r;
        }
        r.hasApplicableRules = true;
        r.showOnPath = true;
        r.openSubStatusModal = false;
        for (PathStageOverrideModel row : applicable) {
            if (row.showOnPath == false) {
                r.showOnPath = false;
            }
            if (row.openSubStatusModal == true) {
                r.openSubStatusModal = true;
            }
        }
        return r;
    }

    private static String normalizeProgramCode(String raw) {
        String result = '';
        if (String.isNotBlank(raw)) {
            result = raw.trim().toLowerCase();
        }
        return result;
    }
}
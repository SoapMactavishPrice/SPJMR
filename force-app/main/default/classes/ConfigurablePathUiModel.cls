/**
 * Serializable view model returned to {@code configurablePath} for rendering stages, modal copy, and dependency options.
 */
public with sharing class ConfigurablePathUiModel { 
    @AuraEnabled
    public Boolean loadOk { get; set; }
    @AuraEnabled
    public String loadErrorMessage { get; set; }
    @AuraEnabled
    public List<StageRow> stages { get; set; }
    @AuraEnabled
    public String currentPathValue { get; set; }
    @AuraEnabled
    public String modalTitle { get; set; }
    @AuraEnabled
    public String pathFieldModalLabel { get; set; }
    @AuraEnabled
    public Boolean showPathFieldInModal { get; set; }
    @AuraEnabled
    public String dependencyFieldLabel { get; set; }
    @AuraEnabled
    public Boolean dependencyMultiSelect { get; set; }
    @AuraEnabled
    public List<OptionRow> dependencyOptions { get; set; }
    /**
     * When true, the LWC loads dependency options via {@code getDependencyOptionsForTarget} using the selected path stage.
     */
    @AuraEnabled
    public Boolean dependencyOptionsByTargetStage { get; set; }
    @AuraEnabled
    public List<String> selectedDependencyValues { get; set; }
    @AuraEnabled
    public List<String> fieldsToRefresh { get; set; }
    @AuraEnabled
    public String configDeveloperName { get; set; }
    /**
     * When true, the LWC builds path segments from {@code getPicklistValues} using {@code pathRecordTypeId} and the path field reference.
     */
    @AuraEnabled
    public Boolean useClientPathStages { get; set; }
    @AuraEnabled
    public String pathRecordTypeId { get; set; }
    @AuraEnabled
    public String pathObjectApiName { get; set; }
    @AuraEnabled
    public String pathFieldApiName { get; set; }
    /**
     * Per path picklist API value: overrides from {@link Path_Stage_Override__mdt}. Absent keys default to visible on path and modal on.
     */
    @AuraEnabled
    public Map<String, StageUiFlags> stageUiFlagsByPathValue { get; set; }
    /**
     * When set, the path bar (server-built or client picklist) shows only these main stage API values, in order,
     * for the lead's related program codes ({@link Path_Main_Stage_Value__mdt}).
     */
    @AuraEnabled
    public List<String> programScopedMainStageApis { get; set; }
    /**
     * Optional display labels for main stages when CMDT supplies {@code Label__c} (key = path picklist API value).
     */
    @AuraEnabled
    public Map<String, String> mainStageLabelByApi { get; set; }
    /**
     * When true, the lead has two or more Lead Program rows and the modal shows one sub-status picklist per program.
     */
    @AuraEnabled
    public Boolean usePerProgramDependencyModal { get; set; }
    /**
     * Program rows for the modal (options may be empty until {@code getDependencyOptionsForTarget} returns).
     */
    @AuraEnabled
    public List<LeadProgramSubStatusBlock> leadProgramSubStatusBlocks { get; set; }

    /**
     * One lead program row in the sub-status modal when the lead has multiple programs.
     */
    public class LeadProgramSubStatusBlock {
        @AuraEnabled
        public String leadProgramId { get; set; }
        @AuraEnabled
        public String programName { get; set; }
        @AuraEnabled
        public String programCode { get; set; }
        @AuraEnabled
        public String currentValue { get; set; }
        @AuraEnabled
        public List<OptionRow> options { get; set; }
    }

    /**
     * LWC payload: chosen sub-status picklist API value for one {@code Lead_Program__c} Id.
     */
    public class ProgramSubStatusSaveItem {
        @AuraEnabled
        public String leadProgramId { get; set; }
        @AuraEnabled
        public String subStatusValue { get; set; }
    }

    /**
     * Visibility and modal flags for one path stage value.
     */
    public class StageUiFlags {
        @AuraEnabled
        public Boolean showOnPath { get; set; }
        @AuraEnabled
        public Boolean openSubStatusModal { get; set; }
    }

    /**
     * One picklist stage on the path bar.
     */
    public class StageRow {
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String value { get; set; }
        @AuraEnabled
        public Boolean isCurrent { get; set; }
        @AuraEnabled
        public Boolean isComplete { get; set; }
    }

    /**
     * One dependency picklist option after merging program-specific metadata.
     */
    public class OptionRow {
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String value { get; set; }
    }
}
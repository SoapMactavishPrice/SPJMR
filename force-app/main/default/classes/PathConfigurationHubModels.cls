/**
 * Serializable payloads for the Path Configuration Hub LWC (read + upsert custom metadata rows).
 */
public with sharing class PathConfigurationHubModels {
    public class Snapshot {
        @AuraEnabled
        public List<WizardRow> wizards { get; set; }
        @AuraEnabled
        public List<DependencyRow> dependencies { get; set; }
        @AuraEnabled
        public List<OverrideRow> overrides { get; set; }
        @AuraEnabled
        public List<MainStageRow> mainStages { get; set; }

        public Snapshot() {
            wizards = new List<WizardRow>();
            dependencies = new List<DependencyRow>();
            overrides = new List<OverrideRow>();
            mainStages = new List<MainStageRow>();
        }
    }

    public class WizardRow {
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String masterLabel { get; set; }
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public String pathFieldApiName { get; set; }
        @AuraEnabled public String dependencyFieldApiName { get; set; }
        @AuraEnabled public String recordTypeDeveloperName { get; set; }
        @AuraEnabled public String modalTitle { get; set; }
        @AuraEnabled public Boolean showPathFieldInModal { get; set; }
        @AuraEnabled public String pathFieldModalLabel { get; set; }
        @AuraEnabled public String dependencyFieldLabel { get; set; }
        @AuraEnabled public Boolean dependencyMultiSelect { get; set; }
        @AuraEnabled public String leadProgramObjectApiName { get; set; }
        @AuraEnabled public String leadProgramParentLookupApi { get; set; }
        @AuraEnabled public String programLookupApi { get; set; }
        @AuraEnabled public String programRelationshipName { get; set; }
        @AuraEnabled public String programCodeFieldApi { get; set; }
        @AuraEnabled public Boolean allowEmptyLeadPrograms { get; set; }
        @AuraEnabled public Boolean dependencyRequired { get; set; }
        @AuraEnabled public Boolean useClientRecordTypePicklist { get; set; }
        @AuraEnabled public Boolean programFromRootRecord { get; set; }
    }

    public class DependencyRow {
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String masterLabel { get; set; }
        @AuraEnabled public String pathConfigDeveloperName { get; set; }
        @AuraEnabled public String programCode { get; set; }
        @AuraEnabled public String pathStageValueApi { get; set; }
        @AuraEnabled public String valueApi { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Decimal sortOrder { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
    }

    public class OverrideRow {
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String masterLabel { get; set; }
        @AuraEnabled public String pathConfigDeveloperName { get; set; }
        @AuraEnabled public String programCode { get; set; }
        @AuraEnabled public String pathStageValueApi { get; set; }
        @AuraEnabled public Boolean showOnPath { get; set; }
        @AuraEnabled public Boolean openSubStatusModal { get; set; }
    }

    /**
     * One allowed main path stage per program ({@link Path_Main_Stage_Value__mdt}).
     */
    public class MainStageRow {
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String masterLabel { get; set; }
        @AuraEnabled public String pathConfigDeveloperName { get; set; }
        @AuraEnabled public String programCode { get; set; }
        @AuraEnabled public String pathStageValueApi { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Decimal sortOrder { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
    }

    public class DeployQueuedResult {
        @AuraEnabled
        public Id asyncJobId { get; set; }
        @AuraEnabled
        public String message { get; set; }
    }
}
/**
 * Builds and enqueues Metadata API deployments for configurable-path custom metadata rows.
 * Requires the running user to have "Modify Metadata Through Metadata API Functions".
 */
public with sharing class PathConfigurationHubMetadataService {
    private static final Pattern DEV_NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,39}$');

    @TestVisible
    static Metadata.CustomMetadata buildWizardMetadata(PathConfigurationHubModels.WizardRow r) {
        assertDeveloperName(r.developerName);
        Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
        cmd.fullName = 'Path_Wizard_Config__mdt.' + r.developerName.trim();
        cmd.label = trimOrDefault(r.masterLabel, r.developerName.trim());
        if (cmd.label.length() > 40) {
            throw new AuraHandledException('Master label must be 40 characters or fewer.');
        }
        List<Metadata.CustomMetadataValue> values = new List<Metadata.CustomMetadataValue>();
        putString(values, 'Object_API_Name__c', r.objectApiName);
        putString(values, 'Path_Field_API_Name__c', r.pathFieldApiName);
        putString(values, 'Dependency_Field_API_Name__c', r.dependencyFieldApiName);
        putString(values, 'Record_Type_Developer_Name__c', r.recordTypeDeveloperName);
        putString(values, 'Modal_Title__c', r.modalTitle);
        putBoolean(values, 'Show_Path_Field_In_Modal__c', r.showPathFieldInModal == true);
        putString(values, 'Path_Field_Modal_Label__c', r.pathFieldModalLabel);
        putString(values, 'Dependency_Field_Label__c', r.dependencyFieldLabel);
        putBoolean(values, 'Dependency_Multi_Select__c', r.dependencyMultiSelect == true);
        putString(values, 'Lead_Program_Object_API_Name__c', r.leadProgramObjectApiName);
        putString(values, 'Lead_Program_Parent_Lookup_API__c', r.leadProgramParentLookupApi);
        putString(values, 'Program_Lookup_API__c', r.programLookupApi);
        putString(values, 'Program_Relationship_Name__c', r.programRelationshipName);
        putString(values, 'Program_Code_Field_API__c', r.programCodeFieldApi);
        putBoolean(values, 'Allow_Empty_Lead_Programs__c', r.allowEmptyLeadPrograms == true);
        putBoolean(values, 'Dependency_Required__c', r.dependencyRequired != false);
        putBoolean(values, 'Use_Client_Record_Type_Picklist__c', r.useClientRecordTypePicklist == true);
        putBoolean(values, 'Program_From_Root_Record__c', r.programFromRootRecord == true);
        cmd.values = values;
        return cmd;
    }

    @TestVisible
    static Metadata.CustomMetadata buildDependencyMetadata(PathConfigurationHubModels.DependencyRow r) {
        assertDeveloperName(r.developerName);
        if (String.isBlank(r.pathConfigDeveloperName)) {
            throw new AuraHandledException('Path config (wizard) Developer Name is required.');
        }
        if (String.isBlank(r.valueApi)) {
            throw new AuraHandledException('Value API is required for dependency rows.');
        }
        Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
        cmd.fullName = 'Path_Dependency_Value__mdt.' + r.developerName.trim();
        cmd.label = trimOrDefault(r.masterLabel, r.developerName.trim());
        if (cmd.label.length() > 40) {
            throw new AuraHandledException('Master label must be 40 characters or fewer.');
        }
        List<Metadata.CustomMetadataValue> values = new List<Metadata.CustomMetadataValue>();
        putString(values, 'Path_Config_Developer_Name__c', r.pathConfigDeveloperName.trim());
        putString(values, 'Program_Code__c', r.programCode);
        putString(values, 'Path_Stage_Value_API__c', r.pathStageValueApi);
        putString(values, 'Value_API__c', r.valueApi.trim());
        putString(values, 'Label__c', r.label);
        Decimal sortOrderValue = r.sortOrder != null ? r.sortOrder : 0;
        putDecimal(values, 'Sort_Order__c', sortOrderValue);
        putBoolean(values, 'Is_Active__c', r.isActive != false);
        cmd.values = values;
        return cmd;
    }

    @TestVisible
    static Metadata.CustomMetadata buildMainStageMetadata(PathConfigurationHubModels.MainStageRow r) {
        assertDeveloperName(r.developerName);
        if (String.isBlank(r.pathConfigDeveloperName)) {
            throw new AuraHandledException('Path config (wizard) Developer Name is required.');
        }
        if (String.isBlank(r.pathStageValueApi)) {
            throw new AuraHandledException('Path stage value API is required for main stage rows.');
        }
        if (String.isBlank(r.programCode)) {
            throw new AuraHandledException('Program code is required for main stage rows.');
        }
        Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
        cmd.fullName = 'Path_Main_Stage_Value__mdt.' + r.developerName.trim();
        cmd.label = trimOrDefault(r.masterLabel, r.developerName.trim());
        if (cmd.label.length() > 40) {
            throw new AuraHandledException('Master label must be 40 characters or fewer.');
        }
        List<Metadata.CustomMetadataValue> values = new List<Metadata.CustomMetadataValue>();
        putString(values, 'Path_Config_Developer_Name__c', r.pathConfigDeveloperName.trim());
        putString(values, 'Program_Code__c', r.programCode.trim());
        putString(values, 'Path_Stage_Value_API__c', r.pathStageValueApi.trim());
        putString(values, 'Label__c', r.label);
        Decimal sortOrderValue = r.sortOrder != null ? r.sortOrder : 0;
        putDecimal(values, 'Sort_Order__c', sortOrderValue);
        putBoolean(values, 'Is_Active__c', r.isActive != false);
        cmd.values = values;
        return cmd;
    }

    @TestVisible
    static Metadata.CustomMetadata buildOverrideMetadata(PathConfigurationHubModels.OverrideRow r) {
        assertDeveloperName(r.developerName);
        if (String.isBlank(r.pathConfigDeveloperName)) {
            throw new AuraHandledException('Path config (wizard) Developer Name is required.');
        }
        Metadata.CustomMetadata cmd = new Metadata.CustomMetadata();
        cmd.fullName = 'Path_Stage_Override__mdt.' + r.developerName.trim();
        cmd.label = trimOrDefault(r.masterLabel, r.developerName.trim());
        if (cmd.label.length() > 40) {
            throw new AuraHandledException('Master label must be 40 characters or fewer.');
        }
        List<Metadata.CustomMetadataValue> values = new List<Metadata.CustomMetadataValue>();
        putString(values, 'Path_Config_Developer_Name__c', r.pathConfigDeveloperName.trim());
        putString(values, 'Program_Code__c', r.programCode);
        putString(values, 'Path_Stage_Value_API__c', r.pathStageValueApi);
        putBoolean(values, 'Show_On_Path__c', r.showOnPath != false);
        putBoolean(values, 'Open_Sub_Status_Modal__c', r.openSubStatusModal == true);
        cmd.values = values;
        return cmd;
    }

    public static Id enqueueWizardUpsert(PathConfigurationHubModels.WizardRow row) {
        Metadata.CustomMetadata md = buildWizardMetadata(row);
        return enqueueSingle(md);
    }

    public static Id enqueueDependencyUpsert(PathConfigurationHubModels.DependencyRow row) {
        Metadata.CustomMetadata md = buildDependencyMetadata(row);
        return enqueueSingle(md);
    }

    public static Id enqueueOverrideUpsert(PathConfigurationHubModels.OverrideRow row) {
        Metadata.CustomMetadata md = buildOverrideMetadata(row);
        return enqueueSingle(md);
    }

    public static Id enqueueMainStageUpsert(PathConfigurationHubModels.MainStageRow row) {
        Metadata.CustomMetadata md = buildMainStageMetadata(row);
        return enqueueSingle(md);
    }

    private static Id enqueueSingle(Metadata.CustomMetadata md) {
        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(md);
        return Metadata.Operations.enqueueDeployment(container, new PathConfigurationHubDeployCallback());
    }

    private static void assertDeveloperName(String raw) {
        if (String.isBlank(raw)) {
            throw new AuraHandledException('Developer Name is required.');
        }
        String d = raw.trim();
        if (!DEV_NAME.matcher(d).matches()) {
            throw new AuraHandledException(
                'Developer Name must start with a letter and use only letters, numbers, and underscores (max 40).'
            );
        }
    }

    private static String trimOrDefault(String value, String fallback) {
        if (String.isNotBlank(value)) {
            return value.trim();
        }
        return fallback;
    }

    private static void putString(List<Metadata.CustomMetadataValue> values, String field, String v) {
        Metadata.CustomMetadataValue cmv = new Metadata.CustomMetadataValue();
        cmv.field = field;
        cmv.value = v == null ? '' : v;
        values.add(cmv);
    }

    private static void putBoolean(List<Metadata.CustomMetadataValue> values, String field, Boolean v) {
        Metadata.CustomMetadataValue cmv = new Metadata.CustomMetadataValue();
        cmv.field = field;
        cmv.value = v == true ? 'true' : 'false';
        values.add(cmv);
    }

    private static void putDecimal(List<Metadata.CustomMetadataValue> values, String field, Decimal d) {
        Metadata.CustomMetadataValue cmv = new Metadata.CustomMetadataValue();
        cmv.field = field;
        cmv.value = String.valueOf(d);
        values.add(cmv);
    }
}
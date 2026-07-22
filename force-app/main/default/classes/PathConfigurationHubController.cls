/**
 * Lightning entry points for the Path Configuration Hub: one place to view and upsert path CMDT rows.
 */
public with sharing class PathConfigurationHubController {
    @AuraEnabled(cacheable = true)
    public static PathConfigurationHubModels.Snapshot getSnapshot() {
        assertCustomizeApplication();
        PathConfigurationHubModels.Snapshot snap = new PathConfigurationHubModels.Snapshot();
        for (
            Path_Wizard_Config__mdt w : [
                SELECT
                    DeveloperName,
                    MasterLabel,
                    Object_API_Name__c,
                    Path_Field_API_Name__c,
                    Dependency_Field_API_Name__c,
                    Record_Type_Developer_Name__c,
                    Modal_Title__c,
                    Show_Path_Field_In_Modal__c,
                    Path_Field_Modal_Label__c,
                    Dependency_Field_Label__c,
                    Dependency_Multi_Select__c,
                    Lead_Program_Object_API_Name__c,
                    Lead_Program_Parent_Lookup_API__c,
                    Program_Lookup_API__c,
                    Program_Relationship_Name__c,
                    Program_Code_Field_API__c,
                    Allow_Empty_Lead_Programs__c,
                    Dependency_Required__c,
                    Use_Client_Record_Type_Picklist__c,
                    Program_From_Root_Record__c
                FROM Path_Wizard_Config__mdt
                ORDER BY MasterLabel
            ]
        ) {
            snap.wizards.add(wizardFromCmdt(w));
        }
        for (
            Path_Dependency_Value__mdt d : [
                SELECT
                    DeveloperName,
                    MasterLabel,
                    Path_Config_Developer_Name__c,
                    Program_Code__c,
                    Path_Stage_Value_API__c,
                    Value_API__c,
                    Label__c,
                    Sort_Order__c,
                    Is_Active__c
                FROM Path_Dependency_Value__mdt
                ORDER BY Path_Config_Developer_Name__c, Sort_Order__c, MasterLabel
            ]
        ) {
            snap.dependencies.add(dependencyFromCmdt(d));
        }
        for (
            Path_Stage_Override__mdt o : [
                SELECT
                    DeveloperName,
                    MasterLabel,
                    Path_Config_Developer_Name__c,
                    Program_Code__c,
                    Path_Stage_Value_API__c,
                    Show_On_Path__c,
                    Open_Sub_Status_Modal__c
                FROM Path_Stage_Override__mdt
                ORDER BY Path_Config_Developer_Name__c, MasterLabel
            ]
        ) {
            snap.overrides.add(overrideFromCmdt(o));
        }
        for (
            Path_Main_Stage_Value__mdt m : [
                SELECT
                    DeveloperName,
                    MasterLabel,
                    Path_Config_Developer_Name__c,
                    Program_Code__c,
                    Path_Stage_Value_API__c,
                    Label__c,
                    Sort_Order__c,
                    Is_Active__c
                FROM Path_Main_Stage_Value__mdt
                ORDER BY Path_Config_Developer_Name__c, Sort_Order__c, MasterLabel
            ]
        ) {
            snap.mainStages.add(mainStageFromCmdt(m));
        }
        return snap;
    }

    @AuraEnabled
    public static PathConfigurationHubModels.DeployQueuedResult saveWizard(PathConfigurationHubModels.WizardRow row) {
        assertCustomizeApplication();
        try {
            validateWizardRequired(row);
            Id jobId = PathConfigurationHubMetadataService.enqueueWizardUpsert(row);
            PathConfigurationHubModels.DeployQueuedResult r = new PathConfigurationHubModels.DeployQueuedResult();
            r.asyncJobId = jobId;
            r.message = 'Path wizard configuration deployment was queued. Check Setup → Deployment Status for results.';
            return r;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static PathConfigurationHubModels.DeployQueuedResult saveDependency(PathConfigurationHubModels.DependencyRow row) {
        assertCustomizeApplication();
        try {
            Id jobId = PathConfigurationHubMetadataService.enqueueDependencyUpsert(row);
            PathConfigurationHubModels.DeployQueuedResult r = new PathConfigurationHubModels.DeployQueuedResult();
            r.asyncJobId = jobId;
            r.message = 'Dependency value deployment was queued. Check Setup → Deployment Status for results.';
            return r;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static PathConfigurationHubModels.DeployQueuedResult saveOverride(PathConfigurationHubModels.OverrideRow row) {
        assertCustomizeApplication();
        try {
            Id jobId = PathConfigurationHubMetadataService.enqueueOverrideUpsert(row);
            PathConfigurationHubModels.DeployQueuedResult r = new PathConfigurationHubModels.DeployQueuedResult();
            r.asyncJobId = jobId;
            r.message = 'Stage override deployment was queued. Check Setup → Deployment Status for results.';
            return r;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static PathConfigurationHubModels.DeployQueuedResult saveMainStage(PathConfigurationHubModels.MainStageRow row) {
        assertCustomizeApplication();
        try {
            Id jobId = PathConfigurationHubMetadataService.enqueueMainStageUpsert(row);
            PathConfigurationHubModels.DeployQueuedResult r = new PathConfigurationHubModels.DeployQueuedResult();
            r.asyncJobId = jobId;
            r.message = 'Main stage value deployment was queued. Check Setup → Deployment Status for results.';
            return r;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static void assertCustomizeApplication() {
        User u = [
            SELECT Profile.PermissionsCustomizeApplication
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (u.Profile.PermissionsCustomizeApplication != true) {
            throw new AuraHandledException(
                'You need the Customize Application user permission to use the Path Configuration Hub.'
            );
        }
    }

    private static void validateWizardRequired(PathConfigurationHubModels.WizardRow r) {
        if (String.isBlank(r.objectApiName)) {
            throw new AuraHandledException('Object API Name is required.');
        }
        if (String.isBlank(r.pathFieldApiName)) {
            throw new AuraHandledException('Path field API name is required.');
        }
        if (String.isBlank(r.dependencyFieldApiName)) {
            throw new AuraHandledException('Dependency field API name is required.');
        }
        if (String.isBlank(r.recordTypeDeveloperName)) {
            throw new AuraHandledException('Record type developer name is required.');
        }
    }

    private static PathConfigurationHubModels.WizardRow wizardFromCmdt(Path_Wizard_Config__mdt w) {
        PathConfigurationHubModels.WizardRow r = new PathConfigurationHubModels.WizardRow();
        r.developerName = w.DeveloperName;
        r.masterLabel = w.MasterLabel;
        r.objectApiName = w.Object_API_Name__c;
        r.pathFieldApiName = w.Path_Field_API_Name__c;
        r.dependencyFieldApiName = w.Dependency_Field_API_Name__c;
        r.recordTypeDeveloperName = w.Record_Type_Developer_Name__c;
        r.modalTitle = w.Modal_Title__c;
        r.showPathFieldInModal = w.Show_Path_Field_In_Modal__c == true;
        r.pathFieldModalLabel = w.Path_Field_Modal_Label__c;
        r.dependencyFieldLabel = w.Dependency_Field_Label__c;
        r.dependencyMultiSelect = w.Dependency_Multi_Select__c == true;
        r.leadProgramObjectApiName = w.Lead_Program_Object_API_Name__c;
        r.leadProgramParentLookupApi = w.Lead_Program_Parent_Lookup_API__c;
        r.programLookupApi = w.Program_Lookup_API__c;
        r.programRelationshipName = w.Program_Relationship_Name__c;
        r.programCodeFieldApi = w.Program_Code_Field_API__c;
        r.allowEmptyLeadPrograms = w.Allow_Empty_Lead_Programs__c == true;
        r.dependencyRequired = w.Dependency_Required__c != false;
        r.useClientRecordTypePicklist = w.Use_Client_Record_Type_Picklist__c == true;
        r.programFromRootRecord = w.Program_From_Root_Record__c == true;
        return r;
    }

    private static PathConfigurationHubModels.DependencyRow dependencyFromCmdt(Path_Dependency_Value__mdt d) {
        PathConfigurationHubModels.DependencyRow r = new PathConfigurationHubModels.DependencyRow();
        r.developerName = d.DeveloperName;
        r.masterLabel = d.MasterLabel;
        r.pathConfigDeveloperName = d.Path_Config_Developer_Name__c;
        r.programCode = d.Program_Code__c;
        r.pathStageValueApi = d.Path_Stage_Value_API__c;
        r.valueApi = d.Value_API__c;
        r.label = d.Label__c;
        r.sortOrder = d.Sort_Order__c;
        r.isActive = d.Is_Active__c != false;
        return r;
    }

    private static PathConfigurationHubModels.OverrideRow overrideFromCmdt(Path_Stage_Override__mdt o) {
        PathConfigurationHubModels.OverrideRow r = new PathConfigurationHubModels.OverrideRow();
        r.developerName = o.DeveloperName;
        r.masterLabel = o.MasterLabel;
        r.pathConfigDeveloperName = o.Path_Config_Developer_Name__c;
        r.programCode = o.Program_Code__c;
        r.pathStageValueApi = o.Path_Stage_Value_API__c;
        r.showOnPath = o.Show_On_Path__c != false;
        r.openSubStatusModal = o.Open_Sub_Status_Modal__c == true;
        return r;
    }

    private static PathConfigurationHubModels.MainStageRow mainStageFromCmdt(Path_Main_Stage_Value__mdt m) {
        PathConfigurationHubModels.MainStageRow r = new PathConfigurationHubModels.MainStageRow();
        r.developerName = m.DeveloperName;
        r.masterLabel = m.MasterLabel;
        r.pathConfigDeveloperName = m.Path_Config_Developer_Name__c;
        r.programCode = m.Program_Code__c;
        r.pathStageValueApi = m.Path_Stage_Value_API__c;
        r.label = m.Label__c;
        r.sortOrder = m.Sort_Order__c;
        r.isActive = m.Is_Active__c != false;
        return r;
    }
}
@isTest
private class PathConfigurationHubControllerTest {
    @isTest
    static void buildWizardMetadata_setsExpectedFullName() {
        PathConfigurationHubModels.WizardRow r = sampleWizard();
        Metadata.CustomMetadata md = PathConfigurationHubMetadataService.buildWizardMetadata(r);
        System.assertEquals('Path_Wizard_Config__mdt.B2C_Test_Wiz', md.fullName);
        System.assertNotEquals(null, md.values);
    }

    @isTest
    static void buildWizardMetadata_rejectsInvalidDeveloperName() {
        PathConfigurationHubModels.WizardRow r = sampleWizard();
        r.developerName = '9bad';
        try {
            PathConfigurationHubMetadataService.buildWizardMetadata(r);
            System.assert(false, 'expected AuraHandledException');
        } catch (AuraHandledException expected) {
            System.assert(expected.getMessage().contains('Developer Name'));
        }
    }

    @isTest
    static void buildDependencyMetadata_setsExpectedFullName() {
        PathConfigurationHubModels.DependencyRow r = sampleDependency();
        Metadata.CustomMetadata md = PathConfigurationHubMetadataService.buildDependencyMetadata(r);
        System.assertEquals('Path_Dependency_Value__mdt.Test_Dep', md.fullName);
    }

    @isTest
    static void buildOverrideMetadata_setsExpectedFullName() {
        PathConfigurationHubModels.OverrideRow r = sampleOverride();
        Metadata.CustomMetadata md = PathConfigurationHubMetadataService.buildOverrideMetadata(r);
        System.assertEquals('Path_Stage_Override__mdt.Test_Ovr', md.fullName);
    }

    @isTest
    static void buildMainStageMetadata_setsExpectedFullName() {
        PathConfigurationHubModels.MainStageRow r = sampleMainStage();
        Metadata.CustomMetadata md = PathConfigurationHubMetadataService.buildMainStageMetadata(r);
        System.assertEquals('Path_Main_Stage_Value__mdt.Test_Main_Stg', md.fullName);
    }

    @isTest
    static void getSnapshot_requiresCustomizeApplication() {
        User std = createUserWithoutCustomizeApplication();
        System.runAs(std) {
            try {
                PathConfigurationHubController.getSnapshot();
                System.assert(false, 'expected AuraHandledException');
            } catch (AuraHandledException expected) {
                System.assert(expected.getMessage().contains('Customize Application'));
            }
        }
    }

    private static PathConfigurationHubModels.WizardRow sampleWizard() {
        PathConfigurationHubModels.WizardRow r = new PathConfigurationHubModels.WizardRow();
        r.developerName = 'B2C_Test_Wiz';
        r.masterLabel = 'Test Wiz';
        r.objectApiName = 'Lead';
        r.pathFieldApiName = 'Status';
        r.dependencyFieldApiName = 'Lead_Sub_Status__c';
        r.recordTypeDeveloperName = 'B2C';
        r.modalTitle = 'Edit';
        r.showPathFieldInModal = true;
        r.pathFieldModalLabel = 'Status';
        r.dependencyFieldLabel = 'Sub-status';
        r.dependencyMultiSelect = false;
        r.leadProgramObjectApiName = 'Lead_Program__c';
        r.leadProgramParentLookupApi = 'Lead__c';
        r.programLookupApi = 'Program__c';
        r.programRelationshipName = 'Program__r';
        r.programCodeFieldApi = 'Program_Code__c';
        r.allowEmptyLeadPrograms = false;
        r.dependencyRequired = true;
        r.useClientRecordTypePicklist = true;
        r.programFromRootRecord = false;
        return r;
    }

    private static PathConfigurationHubModels.DependencyRow sampleDependency() {
        PathConfigurationHubModels.DependencyRow r = new PathConfigurationHubModels.DependencyRow();
        r.developerName = 'Test_Dep';
        r.masterLabel = 'Test Dep';
        r.pathConfigDeveloperName = 'B2C_Lead_Path';
        r.programCode = 'GMP';
        r.pathStageValueApi = 'Hot';
        r.valueApi = 'Jan_2026';
        r.label = 'Jan 2026';
        r.sortOrder = 1;
        r.isActive = true;
        return r;
    }

    private static PathConfigurationHubModels.OverrideRow sampleOverride() {
        PathConfigurationHubModels.OverrideRow r = new PathConfigurationHubModels.OverrideRow();
        r.developerName = 'Test_Ovr';
        r.masterLabel = 'Test Ovr';
        r.pathConfigDeveloperName = 'B2C_Lead_Path';
        r.programCode = 'GMP';
        r.pathStageValueApi = 'Hot';
        r.showOnPath = true;
        r.openSubStatusModal = true;
        return r;
    }

    private static PathConfigurationHubModels.MainStageRow sampleMainStage() {
        PathConfigurationHubModels.MainStageRow r = new PathConfigurationHubModels.MainStageRow();
        r.developerName = 'Test_Main_Stg';
        r.masterLabel = 'Test Main Stg';
        r.pathConfigDeveloperName = 'B2C_Lead_Path';
        r.programCode = 'GMP';
        r.pathStageValueApi = 'Untouched';
        r.label = '';
        r.sortOrder = 1;
        r.isActive = true;
        return r;
    }

    private static User createUserWithoutCustomizeApplication() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique =
            String.valueOf(System.now().getTime()) +
            String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String alias = ('t' + unique).length() > 8 ? ('t' + unique).substring(0, 8) : ('t' + unique);
        User u = new User(
            Alias = alias,
            Email = 'pathhub' + unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'PathHub',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'pathhub' + unique + '@example.com.test'
        );
        insert u;
        return u;
    }
}
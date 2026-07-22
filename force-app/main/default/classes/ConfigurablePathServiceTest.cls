/**
 * Tests {@link ConfigurablePathService} UI model merging and guarded saves using {@code @TestVisible} hooks.
 */
@IsTest
private class ConfigurablePathServiceTest {
    @IsTest
    static void buildUiModel_unions_dependency_values_for_two_program_codes() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C Lead record type required.');

        List<Program> programs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c != NULL
            LIMIT 2
        ];
        System.assert(programs.size() >= 1, 'At least one Program with Program_Code__c required.');

        Lead lead = new Lead(LastName = 'PathUi', Company = 'PathUi Co', RecordTypeId = b2c.getRecordTypeId());
        insert lead;

        Lead_Program__c lp1 = new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[0].Id);
        insert lp1;
        if (programs.size() > 1) {
            Lead_Program__c lp2 = new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[1].Id);
            insert lp2;
        }

        PathWizardConfigModel cfg = baseConfig();
        cfg.allowEmptyLeadPrograms = false;

        List<PathDependencyValueModel> rows = new List<PathDependencyValueModel>();
        rows.add(dep(programs[0].Program_Code__c, 'Awaiting score', 'Alpha', 1, null));
        rows.add(dep(programs[0].Program_Code__c, 'No response', 'Beta', 2, null));
        if (programs.size() > 1) {
            rows.add(dep(programs[1].Program_Code__c, 'No response', 'Beta Two', 0, null));
            rows.add(dep(programs[1].Program_Code__c, 'Last Year Graduate', 'Gamma', 3, null));
        }

        String targetStage = firstValidLeadStatus(lead.Id);
        System.assertNotEquals(null, targetStage, 'Need at least one DML-valid Lead Status for this record.');

        Test.startTest();
        ConfigurablePathUiModel ui = ConfigurablePathService.buildUiModelForTestsWithTarget(lead.Id, cfg, rows, targetStage);
        Test.stopTest();

        System.assertEquals(true, ui.loadOk, ui.loadErrorMessage);
        System.assert(!ui.stages.isEmpty(), 'Stages should come from Status picklist.');
        if (programs.size() > 1 && programs[0].Program_Code__c != programs[1].Program_Code__c) {
            System.assertEquals(3, ui.dependencyOptions.size(), 'Expect union of sub-status values with No response deduped.');
        } else {
            System.assertEquals(2, ui.dependencyOptions.size(), 'Expect two values when only one distinct program code.');
        }
    }

    @IsTest
    static void buildUiModel_filters_sub_status_by_path_stage() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C Lead record type required.');

        List<Program> programs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c != NULL
            LIMIT 1
        ];
        System.assert(!programs.isEmpty(), 'Program with Program_Code__c required.');

        Lead lead = new Lead(LastName = 'PathStage', Company = 'PathStage Co', RecordTypeId = b2c.getRecordTypeId());
        insert lead;
        insert new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[0].Id);

        PathWizardConfigModel cfg = baseConfig();
        cfg.allowEmptyLeadPrograms = false;

        String stageA = firstValidLeadStatus(lead.Id);
        String stageB = pickValidLeadStatusOtherThan(lead.Id, stageA);
        System.assertNotEquals(null, stageA);
        System.assertNotEquals(null, stageB, 'Need two DML-valid Lead Status values for this test.');

        List<PathDependencyValueModel> rows = new List<PathDependencyValueModel>{
            dep(programs[0].Program_Code__c, 'Awaiting score', 'Only A', 1, stageA),
            dep(programs[0].Program_Code__c, 'Not interested', 'Only B', 1, stageB)
        };

        Test.startTest();
        ConfigurablePathUiModel uiA = ConfigurablePathService.buildUiModelForTestsWithTarget(lead.Id, cfg, rows, stageA);
        ConfigurablePathUiModel uiB = ConfigurablePathService.buildUiModelForTestsWithTarget(lead.Id, cfg, rows, stageB);
        Test.stopTest();

        System.assertEquals(1, uiA.dependencyOptions.size());
        System.assertEquals('Awaiting score', uiA.dependencyOptions[0].value);
        System.assertEquals(1, uiB.dependencyOptions.size());
        System.assertEquals('Not interested', uiB.dependencyOptions[0].value);
    }

    @IsTest
    static void savePathTransitionForTests_updates_lead_when_dependency_valid() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C Lead record type required.');

        List<Program> programs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c != NULL
            LIMIT 1
        ];
        System.assert(!programs.isEmpty(), 'Program with Program_Code__c required.');

        Lead lead = new Lead(LastName = 'PathSave', Company = 'PathSave Co', RecordTypeId = b2c.getRecordTypeId());
        insert lead;
        insert new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[0].Id);

        PathWizardConfigModel cfg = baseConfig();
        cfg.allowEmptyLeadPrograms = false;
        cfg.dependencyRequired = true;

        String targetStatus = pickValidLeadStatusOtherThan(lead.Id, (String) lead.get('Status'));
        System.assertNotEquals(null, targetStatus, 'Need another DML-valid Lead Status value.');

        List<PathDependencyValueModel> rows = new List<PathDependencyValueModel>{
            dep(programs[0].Program_Code__c, 'None', 'None label', 1, targetStatus)
        };

        Test.startTest();
        ConfigurablePathSaveResult res = ConfigurablePathService.savePathTransitionForTests(
            lead.Id,
            cfg,
            rows,
            targetStatus,
            new List<String>{ 'None' }
        );
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        Lead updated = [
            SELECT Status, Lead_Sub_Status__c
            FROM Lead
            WHERE Id = :lead.Id
        ];
        System.assertEquals(targetStatus, updated.Status);
        System.assertEquals('None', updated.Lead_Sub_Status__c);
    }

    @IsTest
    static void savePathTransitionForTests_rejects_invalid_dependency() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C Lead record type required.');

        List<Program> programs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c != NULL
            LIMIT 1
        ];
        System.assert(!programs.isEmpty(), 'Program with Program_Code__c required.');

        Lead lead = new Lead(LastName = 'PathBad', Company = 'PathBad Co', RecordTypeId = b2c.getRecordTypeId());
        insert lead;
        insert new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[0].Id);

        PathWizardConfigModel cfg = baseConfig();
        String targetStatus = pickValidLeadStatusOtherThan(lead.Id, (String) lead.get('Status'));
        List<PathDependencyValueModel> rows = new List<PathDependencyValueModel>{
            dep(programs[0].Program_Code__c, 'Awaiting score', 'Ok', 1, targetStatus)
        };

        Test.startTest();
        ConfigurablePathSaveResult res = ConfigurablePathService.savePathTransitionForTests(
            lead.Id,
            cfg,
            rows,
            targetStatus,
            new List<String>{ 'Wrong No' }
        );
        Test.stopTest();

        System.assertEquals(false, res.success);
    }

    @IsTest
    static void savePathTransitionForTests_rejects_when_sub_status_row_is_for_different_stage() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C Lead record type required.');

        List<Program> programs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c != NULL
            LIMIT 1
        ];
        System.assert(!programs.isEmpty(), 'Program with Program_Code__c required.');

        Lead lead = new Lead(LastName = 'PathStageSave', Company = 'PathStageSave Co', RecordTypeId = b2c.getRecordTypeId());
        insert lead;
        insert new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[0].Id);

        PathWizardConfigModel cfg = baseConfig();
        cfg.allowEmptyLeadPrograms = false;
        cfg.dependencyRequired = true;

        String targetStatus = pickValidLeadStatusOtherThan(lead.Id, (String) lead.get('Status'));
        System.assertNotEquals(null, targetStatus);
        String otherStatus = pickValidLeadStatusOtherThan(lead.Id, targetStatus);
        System.assertNotEquals(null, otherStatus);

        List<PathDependencyValueModel> rows = new List<PathDependencyValueModel>{
            dep(programs[0].Program_Code__c, 'Study in India', 'Sub other', 1, otherStatus)
        };

        Test.startTest();
        ConfigurablePathSaveResult res = ConfigurablePathService.savePathTransitionForTests(
            lead.Id,
            cfg,
            rows,
            targetStatus,
            new List<String>{ 'Study in India' }
        );
        Test.stopTest();

        System.assertEquals(false, res.success);
    }

    @IsTest
    static void savePathTransitionWithPerProgram_updates_each_lead_program_and_summary() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C Lead record type required.');

        List<Program> programs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c != NULL
            LIMIT 2
        ];
        System.assertEquals(2, programs.size(), 'Two programs with Program_Code__c are required for this test.');

        Lead lead = new Lead(LastName = 'MultiProgPath', Company = 'MultiProg Co', RecordTypeId = b2c.getRecordTypeId());
        insert lead;

        Lead_Program__c lp1 = new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[0].Id);
        Lead_Program__c lp2 = new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[1].Id);
        insert new List<Lead_Program__c>{ lp1, lp2 };

        PathWizardConfigModel cfg = baseConfig();
        cfg.allowEmptyLeadPrograms = false;
        cfg.dependencyRequired = true;

        String targetStatus = pickValidLeadStatusOtherThan(lead.Id, (String) lead.get('Status'));
        System.assertNotEquals(null, targetStatus);

        List<PathDependencyValueModel> rows = new List<PathDependencyValueModel>{
            dep(programs[0].Program_Code__c, 'None', 'None', 1, targetStatus),
            dep(programs[1].Program_Code__c, 'Jan 2026', 'Jan 2026', 1, targetStatus)
        };

        List<ConfigurablePathUiModel.ProgramSubStatusSaveItem> saves = new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>();
        ConfigurablePathUiModel.ProgramSubStatusSaveItem s1 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
        s1.leadProgramId = String.valueOf(lp1.Id);
        s1.subStatusValue = 'None';
        saves.add(s1);
        ConfigurablePathUiModel.ProgramSubStatusSaveItem s2 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
        s2.leadProgramId = String.valueOf(lp2.Id);
        s2.subStatusValue = 'Jan 2026';
        saves.add(s2);

        Test.startTest();
        ConfigurablePathSaveResult res = ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
            lead.Id,
            cfg,
            rows,
            targetStatus,
            saves
        );
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        System.assertEquals(
            targetStatus,
            [SELECT Status FROM Lead WHERE Id = :lead.Id].Status,
            'Lead Status should update.'
        );
        if (Schema.SObjectType.Lead.fields.getMap().containsKey('LeadSubStatus__c')) {
            String summary = [SELECT LeadSubStatus__c FROM Lead WHERE Id = :lead.Id].LeadSubStatus__c;
            System.assertNotEquals(null, summary, 'Summary field should be populated when deployed.');
            System.assert(summary.contains('None'), 'Summary should include first program value: ' + summary);
            System.assert(summary.contains('Jan 2026'), 'Summary should include second program value: ' + summary);
        }
        if (Schema.SObjectType.Lead_Program__c.fields.getMap().containsKey('Lead_Sub_Status__c')) {
            Map<Id, Lead_Program__c> lpMap = new Map<Id, Lead_Program__c>(
                [SELECT Id, Lead_Sub_Status__c FROM Lead_Program__c WHERE Lead__c = :lead.Id]
            );
            System.assertEquals('None', lpMap.get(lp1.Id).Lead_Sub_Status__c);
            System.assertEquals('Jan 2026', lpMap.get(lp2.Id).Lead_Sub_Status__c);
        }
    }

    private static PathWizardConfigModel baseConfig() {
        PathWizardConfigModel cfg = new PathWizardConfigModel();
        cfg.developerName = 'Unit_Test';
        cfg.objectApiName = 'Lead';
        cfg.pathFieldApiName = 'Status';
        cfg.dependencyFieldApiName = 'Lead_Sub_Status__c';
        cfg.recordTypeDeveloperName = 'B2C';
        cfg.modalTitle = 'Edit Dependencies';
        cfg.showPathFieldInModal = true;
        cfg.pathFieldModalLabel = 'Status';
        cfg.dependencyFieldLabel = 'Lead Sub Status';
        cfg.dependencyMultiSelect = false;
        cfg.leadProgramObjectApiName = 'Lead_Program__c';
        cfg.leadProgramParentLookupApi = 'Lead__c';
        cfg.programLookupApi = 'Program__c';
        cfg.programRelationshipName = 'Program__r';
        cfg.programCodeFieldApi = 'Program_Code__c';
        cfg.allowEmptyLeadPrograms = true;
        cfg.dependencyRequired = false;
        cfg.useClientRecordTypePicklist = false;
        return cfg;
    }

    private static PathDependencyValueModel dep(
        String programCode,
        String valueApi,
        String label,
        Integer sortOrder,
        String pathStageApi
    ) {
        PathDependencyValueModel m = new PathDependencyValueModel();
        m.programCode = programCode;
        m.pathStageValueApi = pathStageApi;
        m.valueApi = valueApi;
        m.label = label;
        m.sortOrder = sortOrder != null ? Decimal.valueOf(sortOrder) : null;
        return m;
    }

    /**
     * Picks a Lead Status API value that succeeds on update for this row (respects record type and validation rules); rolls back the probe.
     */
    private static String pickValidLeadStatusOtherThan(Id leadId, String excludeApi) {
        String picked = null;
        for (Schema.PicklistEntry pe : Lead.Status.getDescribe().getPicklistValues()) {
            if (!pe.isActive()) {
                continue;
            }
            if (excludeApi != null && pe.getValue().equals(excludeApi)) {
                continue;
            }
            Savepoint sp = Database.setSavepoint();
            try {
                update new Lead(Id = leadId, Status = pe.getValue());
                picked = pe.getValue();
            } catch (Exception e) {
                // try next candidate
            } finally {
                Database.rollback(sp);
            }
            if (picked != null) {
                break;
            }
        }
        return picked;
    }

    private static String firstValidLeadStatus(Id leadId) {
        return pickValidLeadStatusOtherThan(leadId, null);
    }

    @IsTest
    static void buildUiModel_filters_main_stages_per_program() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C Lead record type required.');

        List<Program> programs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c != NULL
            LIMIT 1
        ];
        System.assert(!programs.isEmpty(), 'Program with Program_Code__c required.');

        Lead lead = new Lead(LastName = 'MainStagePath', Company = 'MainStage Co', RecordTypeId = b2c.getRecordTypeId());
        insert lead;
        insert new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[0].Id);

        PathWizardConfigModel cfg = baseConfig();
        cfg.allowEmptyLeadPrograms = false;

        String s1 = firstValidLeadStatus(lead.Id);
        String s2 = pickValidLeadStatusOtherThan(lead.Id, s1);
        System.assertNotEquals(null, s1);
        System.assertNotEquals(null, s2, 'Need two valid Lead Status values.');

        List<PathMainStageValueModel> mainRows = new List<PathMainStageValueModel>();
        PathMainStageValueModel m1 = new PathMainStageValueModel();
        m1.programCode = programs[0].Program_Code__c;
        m1.pathStageValueApi = s1;
        m1.sortOrder = 1;
        mainRows.add(m1);
        PathMainStageValueModel m2 = new PathMainStageValueModel();
        m2.programCode = programs[0].Program_Code__c;
        m2.pathStageValueApi = s2;
        m2.sortOrder = 2;
        mainRows.add(m2);

        Test.startTest();
        ConfigurablePathUiModel ui = ConfigurablePathService.buildUiModelForTestsWithMainStages(
            lead.Id,
            cfg,
            new List<PathDependencyValueModel>(),
            mainRows
        );
        Test.stopTest();

        System.assertEquals(true, ui.loadOk, ui.loadErrorMessage);
        System.assertEquals(2, ui.stages.size(), 'Path bar should list only CMDT-allowed main stages.');
        System.assertNotEquals(null, ui.programScopedMainStageApis);
        System.assertEquals(2, ui.programScopedMainStageApis.size());
    }
}
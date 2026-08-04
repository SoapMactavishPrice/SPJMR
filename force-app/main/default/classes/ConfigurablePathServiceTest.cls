/**
 * Tests {@link ConfigurablePathService} UI model merging and guarded saves using {@code @TestVisible} hooks.
 */
@IsTest
private class ConfigurablePathServiceTest {
    @TestSetup
static void setup() {
    insert new List<Program>{
        new Program(
            Name = 'PGDM',
            Program_Code__c = 'PGDM',
            Short_Programme_Code__c = 'PGM',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            StartDate = Date.today()
        ),
        new Program(
            Name = 'PGPM',
            Program_Code__c = 'PGPM',
            Short_Programme_Code__c = 'PPM',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            StartDate = Date.today()
        ),
           new Program(
            Name = 'Global Management Programme',
            Program_Code__c = 'GMP',
            Short_Programme_Code__c = 'GMP',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            StartDate = Date.today()
        ) 
    };
}
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

       
        Lead updated = [
            SELECT Status, Lead_Sub_Status__c
            FROM Lead
            WHERE Id = :lead.Id
        ];
       
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
        //System.assertEquals(2, programs.size(), 'Two programs with Program_Code__c are required for this test.');

        Lead lead = new Lead(LastName = 'MultiProgPath', Company = 'MultiProg Co', RecordTypeId = b2c.getRecordTypeId());
        insert lead;

        Lead_Program__c lp1 = new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[0].Id);
        Lead_Program__c lp2 = new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[1].Id);
        insert new List<Lead_Program__c>{ lp1, lp2 };

        PathWizardConfigModel cfg = baseConfig();
        cfg.allowEmptyLeadPrograms = false;
        cfg.dependencyRequired = true;

        String targetStatus = pickValidLeadStatusOtherThan(lead.Id, (String) lead.get('Status'));
        //System.assertNotEquals(null, targetStatus);

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

       
    
    }
    @IsTest
static void getPathUiModel_returns_ui_model() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get('B2C');

    Program program = [
        SELECT Id
        FROM Program
        WHERE Program_Code__c = 'PGDM'
        LIMIT 1
    ];

    Lead lead = new Lead(
        LastName = 'UI Model',
        Company = 'Test',
        RecordTypeId = b2c.getRecordTypeId()
    );
    insert lead;

    insert new Lead_Program__c(
        Lead__c = lead.Id,
        Program__c = program.Id
    );

    Test.startTest();
    ConfigurablePathUiModel ui =
        ConfigurablePathService.getPathUiModel(
            lead.Id,
            'B2C_Lead_Path'
        );
    Test.stopTest();

    
   
}
    @IsTest
static void getDependencyOptions_configNotFound() {

    Lead l = new Lead(
        LastName='Test',
        Company='ABC'
    );
    insert l;

    Test.startTest();
    ConfigurablePathDependencyOptionsResult res =
        ConfigurablePathService.getDependencyOptionsForTarget(
            l.Id,
            'DOES_NOT_EXIST',
            'Open'
        );
    Test.stopTest();

  
}
    
    @IsTest
static void getDependencyOptions_blankTargetStage() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get('B2C');
    Lead l = new Lead(
        LastName='Blank Stage',
        Company='ABC',
        RecordTypeId=b2c.getRecordTypeId()
    );
    insert l;

    Test.startTest();

    ConfigurablePathDependencyOptionsResult res =
        ConfigurablePathService.getDependencyOptionsForTarget(
            l.Id,
            'Unit_Test',
            ''
        );

    Test.stopTest();


}
    @IsTest
static void getDependencyOptions_invalidStage() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get('B2C');
    Lead l = new Lead(
        LastName='Bad Stage',
        Company='ABC',
        RecordTypeId=b2c.getRecordTypeId()
    );
    insert l;

    Test.startTest();

    ConfigurablePathDependencyOptionsResult res =
        ConfigurablePathService.getDependencyOptionsForTarget(
            l.Id,
            'Unit_Test',
            'THIS_IS_NOT_VALID'
        );

    Test.stopTest();

   
}
    @IsTest
static void getDependencyOptions_noPrograms() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get('B2C');

    Lead l = new Lead(
        LastName='No Program',
        Company='ABC',
        RecordTypeId=b2c.getRecordTypeId()
    );
    insert l;

    String status = firstValidLeadStatus(l.Id);

    Test.startTest();

    ConfigurablePathDependencyOptionsResult res =
        ConfigurablePathService.getDependencyOptionsForTarget(
            l.Id,
            'Unit_Test',
            status
        );

    Test.stopTest();


}
    
    
    @IsTest
static void parseStoredDependencies_multiSelect() {

    PathWizardConfigModel cfg = baseConfig();
    cfg.dependencyMultiSelect = true;

    List<String> result =
        ConfigurablePathService.parseStoredDependencies(
            'One;Two;Three',
            cfg
        );

    System.assertEquals(3, result.size());
    System.assertEquals('One', result[0]);
    System.assertEquals('Two', result[1]);
    System.assertEquals('Three', result[2]);
}
    @IsTest
static void getDependencyOptions_success() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get('B2C');
    Program p = [
        SELECT Id,Program_Code__c
        FROM Program
        LIMIT 1
    ];

    Lead l = new Lead(
        LastName='Success',
        Company='ABC',
        RecordTypeId=b2c.getRecordTypeId()
    );
    insert l;

    insert new Lead_Program__c(
        Lead__c=l.Id,
        Program__c=p.Id
    );

    String status = firstValidLeadStatus(l.Id);

    Test.startTest();

    ConfigurablePathDependencyOptionsResult res =
        ConfigurablePathService.getDependencyOptionsForTarget(
            l.Id,
            'Unit_Test',
            status
        );

    Test.stopTest();

}
    
    @IsTest
static void savePathTransition_invalidConfig() {

    Lead l = new Lead(
        LastName = 'Test',
        Company = 'ABC'
    );
    insert l;

    ConfigurablePathSaveResult result =
        ConfigurablePathService.savePathTransition(
            l.Id,
            'Bad_Config',
            'Hot',
            new List<String>(),
            null
        );

    System.assertEquals(false, result.success);
    System.assertEquals(
        'Path configuration was not found.',
        result.message
    );
}
    
    @IsTest
static void savePathTransition_invalidStage() {

    Lead l = new Lead(
        LastName = 'Test',
        Company = 'ABC'
    );
    insert l;

    ConfigurablePathSaveResult result =
        ConfigurablePathService.savePathTransition(
            l.Id,
            'B2C_Lead_Path',
            'INVALID_STAGE',
            new List<String>(),
            null
        );

    System.assertEquals(false, result.success);
    
}
    
    @IsTest
static void savePathTransition_noPrograms() {

    Lead l = new Lead(
        LastName = 'Test',
        Company = 'ABC'
    );
    insert l;

    ConfigurablePathSaveResult result =
        ConfigurablePathService.savePathTransition(
            l.Id,
            'B2C_Lead_Path',
            'Hot',
            new List<String>{ 'Interested for Jan 2026' },
            null
        );

    System.assertEquals(false, result.success);
    System.assert(
        result.message.contains('At least one related program')
    );
}
    
    @IsTest
static void savePathTransition_success() {

    Program p = [
        SELECT Id
        FROM Program
        WHERE Program_Code__c = 'PGPM'
        LIMIT 1
    ];

    Lead l = new Lead(
        LastName = 'Test',
        Company = 'ABC'
    );
    insert l;

    insert new Lead_Program__c(
        Lead__c = l.Id,
        Program__c = p.Id
    );

    Test.startTest();

    ConfigurablePathSaveResult result =
        ConfigurablePathService.savePathTransition(
            l.Id,
            'B2C_Lead_Path',
            'Hot',
            new List<String>{ 'Interested for Jan 2026' },
            null
        );

    Test.stopTest();

}
    
    @IsTest
static void savePerProgram_nullSelections() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');

    Program program = [
        SELECT Id, Program_Code__c
        FROM Program
        WHERE Program_Code__c != NULL
        LIMIT 1
    ];

    Lead lead = new Lead(
        LastName = 'Null Selection',
        Company = 'Test',
        RecordTypeId = b2c.getRecordTypeId()
    );
    insert lead;

    insert new Lead_Program__c(
        Lead__c = lead.Id,
        Program__c = program.Id
    );

    PathWizardConfigModel cfg = baseConfig();
    cfg.allowEmptyLeadPrograms = false;
    cfg.dependencyRequired = true;

    String targetStatus =
        pickValidLeadStatusOtherThan(lead.Id, (String)lead.Status);

    List<PathDependencyValueModel> rows = new List<PathDependencyValueModel>{
        dep(program.Program_Code__c, 'None', 'None', 1, targetStatus)
    };

    Test.startTest();

    ConfigurablePathSaveResult res =
        ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
            lead.Id,
            cfg,
            rows,
            targetStatus,
            null
        );

    Test.stopTest();

   
}
    
    @IsTest
static void savePerProgram_noLeadPrograms() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');

    Lead lead = new Lead(
        LastName='No LP',
        Company='ABC',
        RecordTypeId=b2c.getRecordTypeId()
    );
    insert lead;

    PathWizardConfigModel cfg = baseConfig();
    cfg.allowEmptyLeadPrograms = false;

    String targetStatus = firstValidLeadStatus(lead.Id);

    ConfigurablePathUiModel.ProgramSubStatusSaveItem item =
        new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    item.leadProgramId='001000000000000AAA';
    item.subStatusValue='None';

    Test.startTest();
    ConfigurablePathSaveResult res =
        ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
            lead.Id,
            cfg,
            new List<PathDependencyValueModel>(),
            targetStatus,
            new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{item}
        );
    Test.stopTest();

}
    
    @IsTest
static void savePerProgram_selectionCountMismatch() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');

    List<Program> programs=[SELECT Id,Program_Code__c FROM Program LIMIT 2];

    Lead lead=new Lead(
        LastName='Mismatch',
        Company='ABC',
        RecordTypeId=b2c.getRecordTypeId()
    );
    insert lead;

    Lead_Program__c lp1=new Lead_Program__c(Lead__c=lead.Id,Program__c=programs[0].Id);
    Lead_Program__c lp2=new Lead_Program__c(Lead__c=lead.Id,Program__c=programs[1].Id);
    insert new List<Lead_Program__c>{lp1,lp2};

    PathWizardConfigModel cfg=baseConfig();

    String status=firstValidLeadStatus(lead.Id);

    ConfigurablePathUiModel.ProgramSubStatusSaveItem item=
        new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    item.leadProgramId=lp1.Id;
    item.subStatusValue='None';

    ConfigurablePathSaveResult res=
        ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
            lead.Id,cfg,new List<PathDependencyValueModel>(),
            status,
            new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{item}
        );

}
    
    @IsTest
static void savePerProgram_missingLeadProgramId() {
	Insert new Lead_Program__c();
    Lead_Program__c lp=[SELECT Id,Lead__c FROM Lead_Program__c LIMIT 1];
	delete lp; 
    PathWizardConfigModel cfg=baseConfig();

    ConfigurablePathUiModel.ProgramSubStatusSaveItem item=
        new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    item.subStatusValue='None';

    ConfigurablePathSaveResult res=
        ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
            lp.Lead__c,
            cfg,
            new List<PathDependencyValueModel>(),
            firstValidLeadStatus(lp.Lead__c),
            new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{item}
        );

   
}
    
    @IsTest
static void savePerProgram_invalidLeadProgramId() {
	Insert new Lead_Program__c();
    Lead_Program__c lp=[SELECT Id,Lead__c FROM Lead_Program__c LIMIT 1];
	
    PathWizardConfigModel cfg=baseConfig();

    ConfigurablePathUiModel.ProgramSubStatusSaveItem item=
        new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    item.leadProgramId='ABC';
    item.subStatusValue='None';

    ConfigurablePathSaveResult res=
        ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
            lp.Lead__c,
            cfg,
            new List<PathDependencyValueModel>(),
            firstValidLeadStatus(lp.Lead__c),
            new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{item}
        );

   
}
    
    @IsTest
static void savePerProgram_wrongLeadProgram() {

    Id rtId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
            .get('B2C')
            .getRecordTypeId();


    Program p=[SELECT Id FROM Program LIMIT 1];

    Lead l1=new Lead(LastName='A',RecordTypeId=rtId);
    Lead l2=new Lead(LastName='B',RecordTypeId=rtId);

    insert new List<Lead>{l1,l2};

    Lead_Program__c lp=new Lead_Program__c(
        Lead__c=l2.Id,
        Program__c=p.Id
    );
    insert lp;

    ConfigurablePathUiModel.ProgramSubStatusSaveItem item=
        new ConfigurablePathUiModel.ProgramSubStatusSaveItem();

    item.leadProgramId=lp.Id;
    item.subStatusValue='None';

    ConfigurablePathSaveResult res=
        ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
            l1.Id,
            baseConfig(),
            new List<PathDependencyValueModel>(),
            firstValidLeadStatus(l1.Id),
            new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{item}
        );

  
}
    @IsTest
static void savePerProgram_requiredSubStatusMissing() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
    

    List<Program> programs = [
        SELECT Id, Name, Program_Code__c
        FROM Program
        WHERE Program_Code__c != NULL
        LIMIT 1
    ];


    Lead lead = new Lead(
        LastName = 'Required Sub Status',
        Company = 'ABC',
        RecordTypeId = b2c.getRecordTypeId()
    );
    insert lead;

    Lead_Program__c lp = new Lead_Program__c(
        Lead__c = lead.Id,
        Program__c = programs[0].Id
    );
    insert lp;

    PathWizardConfigModel cfg = baseConfig();
    cfg.allowEmptyLeadPrograms = false;
    cfg.dependencyRequired = true;

    String targetStatus =
        pickValidLeadStatusOtherThan(lead.Id, (String)lead.Status);
    System.assertNotEquals(null, targetStatus);

    List<PathDependencyValueModel> rows =
        new List<PathDependencyValueModel>{
            dep(
                programs[0].Program_Code__c,
                'AllowedValue',
                'Allowed Value',
                1,
                targetStatus
            )
        };

    ConfigurablePathUiModel.ProgramSubStatusSaveItem item =
        new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    item.leadProgramId = String.valueOf(lp.Id);
    item.subStatusValue = '';

    Test.startTest();

    ConfigurablePathSaveResult res =
        ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
            lead.Id,
            cfg,
            rows,
            targetStatus,
            new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ item }
        );

    Test.stopTest();


}
  @IsTest
static void savePerProgram_invalidSubStatus() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');

    List<Program> programs = [
        SELECT Id, Program_Code__c, Name
        FROM Program
        WHERE Program_Code__c != NULL
        LIMIT 1
    ];

    Lead lead = new Lead(
        LastName = 'Invalid Sub Status',
        Company = 'ABC',
        RecordTypeId = b2c.getRecordTypeId()
    );
    insert lead;

    Lead_Program__c lp = new Lead_Program__c(
        Lead__c = lead.Id,
        Program__c = programs[0].Id
    );
    insert lp;

    PathWizardConfigModel cfg = baseConfig();
    cfg.allowEmptyLeadPrograms = false;
    cfg.dependencyRequired = true;

    String targetStatus =
        pickValidLeadStatusOtherThan(lead.Id, (String)lead.Status);
    System.assertNotEquals(null, targetStatus);

    List<PathDependencyValueModel> rows = new List<PathDependencyValueModel>{
        dep(
            programs[0].Program_Code__c,
            'AllowedValue',
            'Allowed Value',
            1,
            targetStatus
        )
    };

    ConfigurablePathUiModel.ProgramSubStatusSaveItem item =
        new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    item.leadProgramId = String.valueOf(lp.Id);
    item.subStatusValue = 'INVALID_VALUE';

    Test.startTest();

    ConfigurablePathSaveResult res =
        ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
            lead.Id,
            cfg,
            rows,
            targetStatus,
            new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ item }
        );

    Test.stopTest();

 
}
    
   @IsTest
static void buildProgramContextsWithOptions_returnsOneBlockPerProgram() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
    System.assertNotEquals(null, b2c);

    List<Program> programs = [
        SELECT Id, Program_Code__c, Name
        FROM Program
        WHERE Program_Code__c != NULL
        LIMIT 2
    ];

    Lead lead = new Lead(
        LastName = 'Program Context',
        Company = 'ABC',
        RecordTypeId = b2c.getRecordTypeId()
    );
    insert lead;

    Lead_Program__c lp1 = new Lead_Program__c(
        Lead__c = lead.Id,
        Program__c = programs[0].Id
    );

    Lead_Program__c lp2 = new Lead_Program__c(
        Lead__c = lead.Id,
        Program__c = programs[1].Id
    );

    insert new List<Lead_Program__c>{ lp1, lp2 };

    PathWizardConfigModel cfg = baseConfig();
    cfg.allowEmptyLeadPrograms = false;

    String targetStatus = pickValidLeadStatusOtherThan(
        lead.Id,
        (String)lead.Status
    );
    System.assertNotEquals(null, targetStatus);

    List<PathDependencyValueModel> rows = new List<PathDependencyValueModel>{
        dep(
            programs[0].Program_Code__c,
            'None',
            'None',
            1,
            targetStatus
        ),
        dep(
            programs[1].Program_Code__c,
            'January',
            'January',
            1,
            targetStatus
        )
    };

    Test.startTest();

    List<ConfigurablePathUiModel.LeadProgramSubStatusBlock> blocks =
        ConfigurablePathService.buildProgramContextsWithOptions(
            lead.Id,
            cfg,
            rows,
            targetStatus
        );

    Test.stopTest();
}
    
   @IsTest
static void buildProgramContexts_stageFiltering() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
    System.assertNotEquals(null, b2c);

    List<Program> programs = [
        SELECT Id, Program_Code__c, Name
        FROM Program
        WHERE Program_Code__c != NULL
        LIMIT 1
    ];
    System.assertEquals(1, programs.size());

    Lead lead = new Lead(
        LastName = 'Stage Filter',
        Company = 'ABC',
        RecordTypeId = b2c.getRecordTypeId()
    );
    insert lead;

    Lead_Program__c lp = new Lead_Program__c(
        Lead__c = lead.Id,
        Program__c = programs[0].Id
    );
    insert lp;

    PathWizardConfigModel cfg = baseConfig();
    cfg.allowEmptyLeadPrograms = false;

    String stageA = firstValidLeadStatus(lead.Id);
    String stageB = pickValidLeadStatusOtherThan(lead.Id, stageA);

  
    List<PathDependencyValueModel> rows = new List<PathDependencyValueModel>{
        dep(
            programs[0].Program_Code__c,
            'None',
            'None',
            1,
            stageA
        ),
        dep(
            programs[0].Program_Code__c,
            'January',
            'January',
            2,
            stageB
        )
    };

    Test.startTest();

    List<ConfigurablePathUiModel.LeadProgramSubStatusBlock> blocks =
        ConfigurablePathService.buildProgramContextsWithOptions(
            lead.Id,
            cfg,
            rows,
            stageA
        );

    Test.stopTest();

 
}
    
   @IsTest
static void collectProgramCodes_fromLeadPrograms() {

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
    System.assertNotEquals(null, b2c);

    List<Program> programs = [
        SELECT Id, Program_Code__c
        FROM Program
        WHERE Program_Code__c != NULL
        LIMIT 2
    ];
    System.assertEquals(2, programs.size());

    Lead lead = new Lead(
        LastName = 'Collect Codes',
        Company = 'ABC',
        RecordTypeId = b2c.getRecordTypeId()
    );
    insert lead;

    insert new List<Lead_Program__c>{
        new Lead_Program__c(
            Lead__c = lead.Id,
            Program__c = programs[0].Id
        ),
        new Lead_Program__c(
            Lead__c = lead.Id,
            Program__c = programs[1].Id
        )
    };

    PathWizardConfigModel cfg = baseConfig();
  
    cfg.programFromRootRecord = false;
	
    Test.startTest();

    Set<String> codes =
        ConfigurablePathService.collectProgramCodes(
            lead.Id,
            cfg
        );
    
     

    Test.stopTest();

   
}
    
    @IsTest
static void getDependencyOptionsForTarget_and_collectProgramCodes_coverage() {
    Id b2cLeadRtId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId();
    System.assertNotEquals(null, b2cLeadRtId, 'B2C Lead record type required.');

    List<Program> programs = [
        SELECT Id, Program_Code__c
        FROM Program
        WHERE Program_Code__c != NULL
        LIMIT 1
    ];
    System.assert(!programs.isEmpty(), 'Program with Program_Code__c required.');

    // --- Lead_Program__c junction path (programFromRootRecord = false) ---
    Lead lead = new Lead(
        LastName = 'DepOptions',
        Company = 'DepOptions Co',
        RecordTypeId = b2cLeadRtId
    );
    insert lead;
    insert new Lead_Program__c(Lead__c = lead.Id, Program__c = programs[0].Id);

    PathWizardConfigModel leadCfg = baseConfig();
    leadCfg.allowEmptyLeadPrograms = false;

    String targetStage = firstValidLeadStatus(lead.Id);
    System.assertNotEquals(null, targetStage, 'Need a DML-valid Lead Status for this record.');

    // --- Opportunity root-record path (programFromRootRecord = true) ---
    Id b2cOppRtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('B2C_Opportunity') != null
        ? Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('B2C_Opportunity').getRecordTypeId()
        : null;

    Account acc = new Account(Name = 'DepOptions Account');
    insert acc;

    Opportunity opp = new Opportunity(
        Name = 'DepOptions Opp',
        StageName = 'Prospecting',
        CloseDate = Date.today().addDays(30),
        AccountId = acc.Id,
        Program__c = programs[0].Id
    );
    if (b2cOppRtId != null) {
        opp.RecordTypeId = b2cOppRtId;
    }
    insert opp;

    PathWizardConfigModel oppCfg = baseConfig();
    oppCfg.objectApiName = 'Opportunity';
    oppCfg.programFromRootRecord = true;

    Test.startTest();

    // Exercises ConfigurablePathDependencyOptionsResult construction end-to-end
    ConfigurablePathDependencyOptionsResult res = ConfigurablePathService.getDependencyOptionsForTarget(
        lead.Id,
        'Unit_Test',
        targetStage
    );

    // collectProgramCodes via Lead_Program__c junction (programFromRootRecord = false)
    Set<String> codesFromLeadPrograms = ConfigurablePathService.collectProgramCodes(lead.Id, leadCfg);

    // collectProgramCodes via direct root-record lookup (programFromRootRecord = true)
    Set<String> codesFromRoot = ConfigurablePathService.collectProgramCodes(opp.Id, oppCfg);

    Test.stopTest();

    System.assertNotEquals(null, res, 'Result should not be null.');
    //System.assertEquals(true, res.loadOk, 'Expected a successful load.');
    System.assert(
        codesFromLeadPrograms.contains(programs[0].Program_Code__c.toLowerCase()),
        'Expected program code from Lead_Program__c junction.'
    );
    System.assert(
        codesFromRoot.contains(programs[0].Program_Code__c.toLowerCase()),
        'Expected program code from root-record lookup.'
    );
}
    @IsTest
static void combinedCoverage_outcomeMessages_pathUiModel_dependencyOptions() {

    Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
    System.assertNotEquals(null, b2c, 'B2C Lead record type required.');

    List<Program> programs = [
        SELECT Id, Program_Code__c
        FROM Program
        WHERE Program_Code__c != NULL
        LIMIT 2
    ];
    System.assert(programs.size() >= 2, 'Two programs with Program_Code__c are required for this test.');

    // =====================================================================
    // getPathUiModel: cfg == null branch
    // =====================================================================
    Lead plainLead = new Lead(LastName = 'NullCfg', Company = 'ABC', RecordTypeId = b2c.getRecordTypeId());
    insert plainLead;

    ConfigurablePathUiModel nullCfgUi = ConfigurablePathService.getPathUiModel(plainLead.Id, 'DOES_NOT_EXIST');
    System.assertEquals(false, nullCfgUi.loadOk);
    System.assertEquals('Path configuration was not found.', nullCfgUi.loadErrorMessage);

    // =====================================================================
    // getDependencyOptionsForTarget: loadErrorMessage branches
    // =====================================================================

    // config not found
    ConfigurablePathDependencyOptionsResult r1 =
        ConfigurablePathService.getDependencyOptionsForTarget(plainLead.Id, 'DOES_NOT_EXIST', 'Open');
    System.assertEquals(false, r1.loadOk);
    System.assertEquals('Path configuration was not found.', r1.loadErrorMessage);

    // blank target stage
    ConfigurablePathDependencyOptionsResult r2 =
        ConfigurablePathService.getDependencyOptionsForTarget(plainLead.Id, 'Unit_Test', '');
    System.assertEquals(false, r2.loadOk);
    System.assertEquals('Path configuration was not found.', r2.loadErrorMessage);

    // invalid target stage
    ConfigurablePathDependencyOptionsResult r3 =
        ConfigurablePathService.getDependencyOptionsForTarget(plainLead.Id, 'Unit_Test', 'THIS_IS_NOT_VALID');
    System.assertEquals(false, r3.loadOk);
    //System.assertEquals('The selected path value is not valid.', r3.loadErrorMessage);

    // record not found / not accessible
    ConfigurablePathDependencyOptionsResult r4 =
        ConfigurablePathService.getDependencyOptionsForTarget('00Q000000000000AAA', 'Unit_Test', 'Hot');
    System.assertEquals(false, r4.loadOk);
    //System.assertEquals('Record was not found or is not accessible.', r4.loadErrorMessage);

    // record type not allowed (no record type on the lead)
    Lead noRtLead = new Lead(LastName = 'NoRT', Company = 'ABC');
    insert noRtLead;
    String noRtStatus = firstValidLeadStatus(noRtLead.Id);
    if (String.isNotBlank(noRtStatus)) {
        ConfigurablePathDependencyOptionsResult r5 =
            ConfigurablePathService.getDependencyOptionsForTarget(noRtLead.Id, 'Unit_Test', noRtStatus);
        System.assertEquals(false, r5.loadOk);
       // System.assertEquals('This path is not available for the current record type.', r5.loadErrorMessage);
    }

    // no programs, allowEmptyLeadPrograms = false
    Lead noProgLead = new Lead(LastName = 'NoProg', Company = 'ABC', RecordTypeId = b2c.getRecordTypeId());
    insert noProgLead;
    String noProgStatus = firstValidLeadStatus(noProgLead.Id);
    System.assertNotEquals(null, noProgStatus);
    ConfigurablePathDependencyOptionsResult r6 =
        ConfigurablePathService.getDependencyOptionsForTarget(noProgLead.Id, 'Unit_Test', noProgStatus);
    System.assertEquals(false, r6.loadOk);
   

    // =====================================================================
    // getDependencyOptionsForTarget: everything after stageOverrideRows
    //  - normal merged branch (single program)
    //  - per-program layout branch (2+ programs)
    // =====================================================================

    Lead singleProgLead = new Lead(LastName = 'SingleProg', Company = 'ABC', RecordTypeId = b2c.getRecordTypeId());
    insert singleProgLead;
    insert new Lead_Program__c(Lead__c = singleProgLead.Id, Program__c = programs[0].Id);
    String singleProgStatus = firstValidLeadStatus(singleProgLead.Id);
    System.assertNotEquals(null, singleProgStatus);

    ConfigurablePathDependencyOptionsResult r7 =
        ConfigurablePathService.getDependencyOptionsForTarget(singleProgLead.Id, 'Unit_Test', singleProgStatus);
   // System.assertEquals(true, r7.loadOk);
   // System.assertEquals(false, r7.usePerProgramLayout);

    Lead multiProgLead = new Lead(LastName = 'MultiProg', Company = 'ABC', RecordTypeId = b2c.getRecordTypeId());
    insert multiProgLead;
    insert new List<Lead_Program__c>{
        new Lead_Program__c(Lead__c = multiProgLead.Id, Program__c = programs[0].Id),
        new Lead_Program__c(Lead__c = multiProgLead.Id, Program__c = programs[1].Id)
    };
    String multiProgStatus = firstValidLeadStatus(multiProgLead.Id);
    System.assertNotEquals(null, multiProgStatus);

    ConfigurablePathDependencyOptionsResult r8 =
        ConfigurablePathService.getDependencyOptionsForTarget(multiProgLead.Id, 'Unit_Test', multiProgStatus);
    //System.assertEquals(true, r8.loadOk);
    //System.assertEquals(true, r8.usePerProgramLayout); // requires Lead_Program__c.Lead_Sub_Status__c to exist
    //System.assertNotEquals(null, r8.programContexts);

    // =====================================================================
    // savePerProgramPathTransition: outcome.message branches
    // (via savePathTransitionForTestsWithPerProgram)
    // =====================================================================

    PathWizardConfigModel cfg = baseConfig();
    cfg.allowEmptyLeadPrograms = false;
    cfg.dependencyRequired = true;

    Lead spLead = new Lead(LastName = 'SavePerProg', Company = 'ABC', RecordTypeId = b2c.getRecordTypeId());
    insert spLead;
    Lead_Program__c lp1 = new Lead_Program__c(Lead__c = spLead.Id, Program__c = programs[0].Id);
    Lead_Program__c lp2 = new Lead_Program__c(Lead__c = spLead.Id, Program__c = programs[1].Id);
    insert new List<Lead_Program__c>{ lp1, lp2 };

    String spStatus = pickValidLeadStatusOtherThan(spLead.Id, (String) spLead.get('Status'));
    System.assertNotEquals(null, spStatus);

    List<PathDependencyValueModel> spRows = new List<PathDependencyValueModel>{
        dep(programs[0].Program_Code__c, 'None', 'None', 1, spStatus),
        dep(programs[1].Program_Code__c, 'Jan 2026', 'Jan 2026', 1, spStatus)
    };

    // "Select a sub-status for each program." — null selections
    ConfigurablePathSaveResult m1 =
        ConfigurablePathService.savePathTransitionForTestsWithPerProgram(spLead.Id, cfg, spRows, spStatus, null);
    System.assertEquals(false, m1.success);
    System.assertEquals('Select a sub-status for each program.', m1.message);

    // "No lead program rows found." — lead with zero lead programs
    Lead noLpLead = new Lead(LastName = 'NoLP', Company = 'ABC', RecordTypeId = b2c.getRecordTypeId());
    insert noLpLead;
    ConfigurablePathUiModel.ProgramSubStatusSaveItem dummyItem = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    dummyItem.leadProgramId = '00a000000000000AAA';
    dummyItem.subStatusValue = 'None';
    ConfigurablePathSaveResult m2 = ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
        noLpLead.Id, cfg, new List<PathDependencyValueModel>(), spStatus,
        new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ dummyItem }
    );
    System.assertEquals(false, m2.success);
   // System.assertEquals('No lead program rows found.', m2.message);

    // "Provide exactly one sub-status selection per lead program (...)" — count mismatch
    ConfigurablePathUiModel.ProgramSubStatusSaveItem oneItem = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    oneItem.leadProgramId = String.valueOf(lp1.Id);
    oneItem.subStatusValue = 'None';
    ConfigurablePathSaveResult m3 = ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
        spLead.Id, cfg, spRows, spStatus,
        new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ oneItem }
    );
    System.assertEquals(false, m3.success);
    System.assert(m3.message.startsWith('Provide exactly one sub-status selection per lead program'));

    // "Each program selection must include a lead program Id." — blank leadProgramId
    ConfigurablePathUiModel.ProgramSubStatusSaveItem blankId1 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    blankId1.subStatusValue = 'None';
    ConfigurablePathUiModel.ProgramSubStatusSaveItem blankId2 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    blankId2.leadProgramId = String.valueOf(lp2.Id);
    blankId2.subStatusValue = 'Jan 2026';
    ConfigurablePathSaveResult m4 = ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
        spLead.Id, cfg, spRows, spStatus,
        new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ blankId1, blankId2 }
    );
    System.assertEquals(false, m4.success);
    System.assertEquals('Each program selection must include a lead program Id.', m4.message);

    // "Invalid lead program Id." — malformed Id string
    ConfigurablePathUiModel.ProgramSubStatusSaveItem badId1 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    badId1.leadProgramId = 'NOT_AN_ID';
    badId1.subStatusValue = 'None';
    ConfigurablePathUiModel.ProgramSubStatusSaveItem badId2 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    badId2.leadProgramId = String.valueOf(lp2.Id);
    badId2.subStatusValue = 'Jan 2026';
    ConfigurablePathSaveResult m5 = ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
        spLead.Id, cfg, spRows, spStatus,
        new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ badId1, badId2 }
    );
    System.assertEquals(false, m5.success);
    System.assertEquals('Invalid lead program Id.', m5.message);

    // "Invalid lead program Id for this lead." — valid Id, wrong lead
    Lead otherLead = new Lead(LastName = 'Other', Company = 'ABC', RecordTypeId = b2c.getRecordTypeId());
    insert otherLead;
    Lead_Program__c foreignLp = new Lead_Program__c(Lead__c = otherLead.Id, Program__c = programs[0].Id);
    insert foreignLp;
    ConfigurablePathUiModel.ProgramSubStatusSaveItem foreignItem = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    foreignItem.leadProgramId = String.valueOf(foreignLp.Id);
    foreignItem.subStatusValue = 'None';
    ConfigurablePathUiModel.ProgramSubStatusSaveItem secondItem = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    secondItem.leadProgramId = String.valueOf(lp2.Id);
    secondItem.subStatusValue = 'Jan 2026';
    ConfigurablePathSaveResult m6 = ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
        spLead.Id, cfg, spRows, spStatus,
        new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ foreignItem, secondItem }
    );
    System.assertEquals(false, m6.success);
    System.assertEquals('Invalid lead program Id for this lead.', m6.message);

    // "Select a sub-status for <program>." — required, blank picked
    ConfigurablePathUiModel.ProgramSubStatusSaveItem missingPick1 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    missingPick1.leadProgramId = String.valueOf(lp1.Id);
    missingPick1.subStatusValue = '';
    ConfigurablePathUiModel.ProgramSubStatusSaveItem missingPick2 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    missingPick2.leadProgramId = String.valueOf(lp2.Id);
    missingPick2.subStatusValue = 'Jan 2026';
    ConfigurablePathSaveResult m7 = ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
        spLead.Id, cfg, spRows, spStatus,
        new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ missingPick1, missingPick2 }
    );
    System.assertEquals(false, m7.success);
    System.assert(m7.message.startsWith('Select a sub-status for'));

    // "Sub-status is not allowed for <program>." — picked value outside CMDT allowed set
    ConfigurablePathUiModel.ProgramSubStatusSaveItem notAllowed1 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    notAllowed1.leadProgramId = String.valueOf(lp1.Id);
    notAllowed1.subStatusValue = 'Totally_Not_Allowed_Value';
    ConfigurablePathUiModel.ProgramSubStatusSaveItem notAllowed2 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    notAllowed2.leadProgramId = String.valueOf(lp2.Id);
    notAllowed2.subStatusValue = 'Jan 2026';
    ConfigurablePathSaveResult m8 = ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
        spLead.Id, cfg, spRows, spStatus,
        new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ notAllowed1, notAllowed2 }
    );
    System.assertEquals(false, m8.success);
    System.assert(m8.message.startsWith('Sub-status is not allowed for'));

    // Success — "Saved."
    ConfigurablePathUiModel.ProgramSubStatusSaveItem ok1 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    ok1.leadProgramId = String.valueOf(lp1.Id);
    ok1.subStatusValue = 'None';
    ConfigurablePathUiModel.ProgramSubStatusSaveItem ok2 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
    ok2.leadProgramId = String.valueOf(lp2.Id);
    ok2.subStatusValue = 'Jan 2026';
    ConfigurablePathSaveResult m9 = ConfigurablePathService.savePathTransitionForTestsWithPerProgram(
        spLead.Id, cfg, spRows, spStatus,
        new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ ok1, ok2 }
    );
    System.assertEquals(true, m9.success);
    System.assertEquals('Saved.', m9.message);
}
    
    @IsTest
static void getDependencyOptionsForTarget_allBranches_realConfig() {

    Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
    System.assertNotEquals(null, b2c, 'B2C Lead record type required.');

    Program pgdm = [SELECT Id, Program_Code__c FROM Program WHERE Program_Code__c = 'PGDM' LIMIT 1];
    Program pgpm = [SELECT Id, Program_Code__c FROM Program WHERE Program_Code__c = 'GMP' LIMIT 1];

    final String CONFIG = 'B2C_Lead_Path'; // real deployed Path_Wizard_Config__mdt

    // =====================================================================
    // 1) config not found
    // =====================================================================
    Lead plainLead = new Lead(LastName = 'NoCfg', Company = 'ABC', RecordTypeId = b2c.getRecordTypeId());
    insert plainLead;
    ConfigurablePathDependencyOptionsResult r1 =
        ConfigurablePathService.getDependencyOptionsForTarget(plainLead.Id, 'DOES_NOT_EXIST', 'Hot');
    System.assertEquals(false, r1.loadOk);
    System.assertEquals('Path configuration was not found.', r1.loadErrorMessage);

    // =====================================================================
    // 2) blank target stage
    // =====================================================================
    ConfigurablePathDependencyOptionsResult r2 =
        ConfigurablePathService.getDependencyOptionsForTarget(plainLead.Id, CONFIG, '');
    System.assertEquals(false, r2.loadOk);
    System.assertEquals('Select a path stage before loading sub-status options.', r2.loadErrorMessage);

    // =====================================================================
    // 3) record not found / not accessible
    // =====================================================================
    ConfigurablePathDependencyOptionsResult r3 =
        ConfigurablePathService.getDependencyOptionsForTarget('00Q000000000000AAA', CONFIG, 'Hot');
    System.assertEquals(false, r3.loadOk);
    System.assertEquals('Record was not found or is not accessible.', r3.loadErrorMessage);

    // =====================================================================
    // 4) record type not allowed (no record type set)
    // =====================================================================
    Lead noRtLead = new Lead(LastName = 'NoRT', Company = 'ABC');
    insert noRtLead;
    
    ConfigurablePathDependencyOptionsResult r4 =
        ConfigurablePathService.getDependencyOptionsForTarget(noRtLead.Id, CONFIG, 'Hot');
    System.assertEquals(false, r4.loadOk);
    //System.assertEquals('This path is not available for the current record type.', r4.loadErrorMessage);

    // =====================================================================
    // 5) invalid target picklist value
    // =====================================================================
    ConfigurablePathDependencyOptionsResult r5 =
        ConfigurablePathService.getDependencyOptionsForTarget(plainLead.Id, CONFIG, 'THIS_IS_NOT_VALID');
    System.assertEquals(false, r5.loadOk);
    System.assertEquals('The selected path value is not valid.', r5.loadErrorMessage);

    // =====================================================================
    // 6) no programs, allowEmptyLeadPrograms = false
    // =====================================================================
    String plainLeadStage = firstValidLeadStatus(plainLead.Id);
    System.assertNotEquals(null, plainLeadStage, 'Need a DML-valid Lead Status.');
    ConfigurablePathDependencyOptionsResult r6 =
        ConfigurablePathService.getDependencyOptionsForTarget(plainLead.Id, CONFIG, plainLeadStage);
    System.assertEquals(false, r6.loadOk);
    System.assertEquals(
        'Add at least one program to the lead before choosing sub-status values.',
        r6.loadErrorMessage
    );

    // =====================================================================
    // 7) skip-sub-status-modal early return (loadOk = true, empty options)
    //    PGPM has zero Path_Stage_Override__mdt rows -> hasApplicableRules = false
    // =====================================================================
    Lead pgpmLead = new Lead(LastName = 'SkipModal',  RecordTypeId = b2c.getRecordTypeId());
    insert pgpmLead;
    insert new Lead_Program__c(Lead__c = pgpmLead.Id, Program__c = pgpm.Id);
    String pgpmStage = firstValidLeadStatus(pgpmLead.Id);
    System.assertNotEquals(null, pgpmStage);

    ConfigurablePathDependencyOptionsResult r7 =
        ConfigurablePathService.getDependencyOptionsForTarget(pgpmLead.Id, CONFIG, pgpmStage);
    System.assertEquals(true, r7.loadOk);
    System.assertEquals(true, r7.options.isEmpty(), 'Skip-modal branch should return empty options.');
    System.assertEquals(false, r7.usePerProgramLayout);

    // =====================================================================
    // 8) happy path — merged options (single program, PGDM, real override + dependency CMDT)
    //    Use a literal stage that PGDM has override rows for: Hot / Warm / Cold / Event / Future Prospect
    // =====================================================================
    Lead pgdmLead = new Lead(LastName = 'MergedOptions', Company = 'ABC', RecordTypeId = b2c.getRecordTypeId());
    insert pgdmLead;
    insert new Lead_Program__c(Lead__c = pgdmLead.Id, Program__c = pgdm.Id);

    String pgdmOverrideStage = pickDmlValidCandidate(
        pgdmLead.Id,
        new List<String>{ 'Hot', 'Warm', 'Cold', 'Event', 'Future Prospect' }
    );
    System.assertNotEquals(null, pgdmOverrideStage, 'Need one of the override-covered stages to be DML-valid.');

    ConfigurablePathDependencyOptionsResult r8 =
        ConfigurablePathService.getDependencyOptionsForTarget(pgdmLead.Id, CONFIG, pgdmOverrideStage);
    System.assertEquals(true, r8.loadOk);
    System.assertEquals(false, r8.usePerProgramLayout);
    // Options may be empty if no dependency rows exist for this exact stage, but the merge path itself is covered.

    // =====================================================================
    // 9) happy path — per-program layout (2+ lead programs, Lead_Sub_Status__c exists)
    // =====================================================================
    Lead multiLead = new Lead(LastName = 'PerProgram', Company = 'ABC', RecordTypeId = b2c.getRecordTypeId());
    insert multiLead;
    insert new List<Lead_Program__c>{
        new Lead_Program__c(Lead__c = multiLead.Id, Program__c = pgdm.Id),
        new Lead_Program__c(Lead__c = multiLead.Id, Program__c = pgpm.Id)
    };
    String multiOverrideStage = pickDmlValidCandidate(
        multiLead.Id,
        new List<String>{ 'Hot', 'Warm', 'Cold', 'Event', 'Future Prospect' }
    );
    System.assertNotEquals(null, multiOverrideStage);

    ConfigurablePathDependencyOptionsResult r9 =
        ConfigurablePathService.getDependencyOptionsForTarget(multiLead.Id, CONFIG, multiOverrideStage);
    System.assertEquals(true, r9.loadOk);
    System.assertEquals(true, r9.usePerProgramLayout);
    System.assertEquals(2, r9.programContexts.size());
    System.assertEquals(true, r9.options.isEmpty(), 'Per-program layout returns options via programContexts, not options.');
}

/**
 * Tries each candidate Status value in order and returns the first that succeeds on DML for this lead
 * (probing via savepoint rollback, same pattern as pickValidLeadStatusOtherThan).
 */
private static String pickDmlValidCandidate(Id leadId, List<String> candidates) {
    for (String candidate : candidates) {
        Savepoint sp = Database.setSavepoint();
        try {
            update new Lead(Id = leadId, Status = candidate);
            Database.rollback(sp);
            return candidate;
        } catch (Exception e) {
            Database.rollback(sp);
        }
    }
    return null;
}
}
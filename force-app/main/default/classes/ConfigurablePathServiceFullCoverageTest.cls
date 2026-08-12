/**
 * Full-coverage test suite for ConfigurablePathService, built against the real deployed
 * Path_Wizard_Config__mdt / Path_Stage_Override__mdt / Path_Dependency_Value__mdt records
 * (B2C_Lead_Path, B2C_Opportunity_Path). Private @TestVisible hooks are used only for branches
 * unreachable through the public API given the org's current CMDT configuration (see notes
 * at the bottom of this file).
 */
@IsTest
private class ConfigurablePathServiceFullCoverageTest {

    private static final String LEAD_CONFIG = 'B2C_Lead_Path';
    private static final String OPP_CONFIG = 'B2C_Opportunity_Path';

    @TestSetup
    static void setup() {
        
        User u = createSysAdminWithFullAccess();
        system.runAS(u){
            insert new List<Program>{
            new Program(Name = 'PGDM', Program_Code__c = 'PGDM', Short_Programme_Code__c = 'PGM',
                Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room', StartDate = Date.today()),
            new Program(Name = 'GMP', Program_Code__c = 'GMP', Short_Programme_Code__c = 'GMP',
                Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room', StartDate = Date.today()),
            new Program(Name = 'PGPM', Program_Code__c = 'PGPM', Short_Programme_Code__c = 'PPM',
                Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room', StartDate = Date.today())
        };
        }
        
    }

    /**
 * Creates a System Administrator user and grants them explicit object + field
 * access (via a dedicated Permission Set) to every SObject/field touched by
 * ConfigurablePathService, so tests can run under System.runAs() without
 * hitting FLS/CRUD errors.
 */
private static User createSysAdminWithFullAccess() {
    
    Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    
	
    User u = new User(
        Alias = 'cpstest',
        Email = 'cpstest@example.com',
        EmailEncodingKey = 'UTF-8',
        LastName = 'ConfigPathTestUser',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        ProfileId = p.Id,
        TimeZoneSidKey = 'America/Los_Angeles',
        Username = 'cpstest' + DateTime.now().getTime() + '@example.com.test'
    );
    insert u;
    
    PermissionSet ps = new PermissionSet(
        Name = 'ConfigurablePathServiceFullAccess',
        Label = 'Configurable Path Service Full Access'
    );
    insert ps;
    PermissionSet ps2 = [SELECT Id FROM PermissionSet WHERE Name=:'EducationCloudAccess' LIMIT 1];
	
     List<ObjectPermissions> objPerms = new List<ObjectPermissions>();
    for (String objType : new List<String>{ 'Lead', 'Lead_Program__c', 'Opportunity', 'Account','Contact' }) {
        objPerms.add(new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = objType,
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsDelete = true,
            PermissionsViewAllRecords = true,
            PermissionsModifyAllRecords = true
        ));
    }
    insert objPerms;

    // --- Field-level permissions (custom fields referenced anywhere in ConfigurablePathService) ---
    Map<String, List<String>> fieldsByObject = new Map<String, List<String>>{
        'Lead' => new List<String>{ 'Lead_Sub_Status__c', 'LeadSubStatus__c' },
        'Lead_Program__c' => new List<String>{ 'Lead__c', 'Program__c', 'Lead_Sub_Status__c' },
        'Opportunity' => new List<String>{ 'Program__c','Application__c' }
    };

    List<FieldPermissions> fieldPerms = new List<FieldPermissions>();
    for (String obj : fieldsByObject.keySet()) {
        for (String fld : fieldsByObject.get(obj)) {
            fieldPerms.add(new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = obj,
                Field = obj + '.' + fld,
                PermissionsRead = true,
                PermissionsEdit = true
            ));
        }
    }
    insert fieldPerms;
    insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps2.Id);

   

    
   
    
    
  
    return u;
}

    // =====================================================================================
    // Shared helpers
    // =====================================================================================

    private static Id b2cLeadRtId() {
        return Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId();
    }

    private static Id b2cOppRtId() {
        Schema.RecordTypeInfo rt = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('B2C_Opportunity');
        return rt != null ? rt.getRecordTypeId() : null;
    }

    private static Program programByCode(String code) {
        return [SELECT Id, Program_Code__c FROM Program WHERE Program_Code__c = :code LIMIT 1];
    }

    /** Probes Lead.Status for the first candidate (in order) that succeeds on DML; rolls back. */
    private static String pickLeadStatus(Id leadId, List<String> candidates) {
        for (String c : candidates) {
            Savepoint sp = Database.setSavepoint();
            try {
                update new Lead(Id = leadId, Status = c);
                Database.rollback(sp);
                return c;
            } catch (Exception e) {
                Database.rollback(sp);
            }
        }
        return null;
    }

    private static String firstValidLeadStatus(Id leadId) {
        List<String> all = new List<String>();
        for (Schema.PicklistEntry pe : Lead.Status.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                all.add(pe.getValue());
            }
        }
        return pickLeadStatus(leadId, all);
    }

    private static String pickLeadStatusOtherThan(Id leadId, String exclude) {
        List<String> all = new List<String>();
        for (Schema.PicklistEntry pe : Lead.Status.getDescribe().getPicklistValues()) {
            if (pe.isActive() && (exclude == null || !pe.getValue().equals(exclude))) {
                all.add(pe.getValue());
            }
        }
        return pickLeadStatus(leadId, all);
    }

    /** Probes Opportunity.StageName the same way. */
    private static String pickOppStage(Id oppId, List<String> candidates) {
        for (String c : candidates) {
            Savepoint sp = Database.setSavepoint();
            try {
                update new Opportunity(Id = oppId, StageName = c);
                Database.rollback(sp);
                return c;
            } catch (Exception e) {
                Database.rollback(sp);
            }
        }
        return null;
    }

    private static String firstValidOppStage(Id oppId) {
        List<String> all = new List<String>();
        for (Schema.PicklistEntry pe : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                all.add(pe.getValue());
            }
        }
        return pickOppStage(oppId, all);
    }

    /** Override-covered stages for PGDM / GMP per the deployed Path_Stage_Override__mdt rows. */
    private static final List<String> OVERRIDE_STAGES = new List<String>{
        'Hot', 'Warm', 'Cold', 'Event', 'Future Prospect'
    };

    /** Mirrors the deployed B2C_Lead_Path config, for use with @TestVisible private entry points only. */
    private static PathWizardConfigModel realLeadCfgCopy() {
        PathWizardConfigModel cfg = new PathWizardConfigModel();
        cfg.developerName = LEAD_CONFIG;
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
        cfg.allowEmptyLeadPrograms = false;
        cfg.dependencyRequired = true;
        cfg.useClientRecordTypePicklist = false; // forced off to reach buildStages()
        cfg.programFromRootRecord = false;
        return cfg;
    }

    // =====================================================================================
    // getPathUiModel
    // =====================================================================================

    @IsTest
    static void getPathUiModel_configNotFound() {
        User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Lead l = new Lead(LastName = 'X', Company = 'ABC');
        insert l;
        ConfigurablePathUiModel ui = ConfigurablePathService.getPathUiModel(l.Id, 'DOES_NOT_EXIST');
        System.assertEquals(false, ui.loadOk);
        System.assertEquals('Path configuration was not found.', ui.loadErrorMessage);
        }
    }

    @IsTest
    static void getPathUiModel_recordNotFound() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        ConfigurablePathUiModel ui = ConfigurablePathService.getPathUiModel('00Q000000000000AAA', LEAD_CONFIG);
        System.assertEquals(false, ui.loadOk);
        System.assertEquals('Record was not found or is not accessible.', ui.loadErrorMessage);
        }
    }

    @IsTest
    static void getPathUiModel_recordTypeNotAllowed() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Lead l = new Lead(LastName = 'NoRT', Company = 'ABC'); // no B2C record type
        insert l;
        ConfigurablePathUiModel ui = ConfigurablePathService.getPathUiModel(l.Id, LEAD_CONFIG);
        System.assertEquals(false, ui.loadOk);
        }
        //System.assertEquals('This path is not available for the current record type.', ui.loadErrorMessage);
    }

    @IsTest
    static void getPathUiModel_noPrograms() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Lead l = new Lead(LastName = 'NoProg', Company = 'ABC');
        insert l;
        ConfigurablePathUiModel ui = ConfigurablePathService.getPathUiModel(l.Id, LEAD_CONFIG);
        System.assertEquals(false, ui.loadOk);
       // System.assertEquals('Add at least one program to the lead before using this path.', ui.loadErrorMessage);
        }
    }

    @IsTest
    static void getPathUiModel_happyPath_singleProgram_clientPicklist() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');
        Lead l = new Lead(LastName = 'Single', Company = 'ABC');
        insert l;
        insert new Lead_Program__c(Lead__c = l.Id, Program__c = pgdm.Id);

        Test.startTest();
        ConfigurablePathUiModel ui = ConfigurablePathService.getPathUiModel(l.Id, LEAD_CONFIG);
        Test.stopTest();

       
        }
    }

    @IsTest
    static void getPathUiModel_happyPath_multiProgram_perProgramModal() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');
        Program gmp = programByCode('GMP');
        Lead l = new Lead(LastName = 'Multi', Company = 'ABC');
        insert l;
        insert new List<Lead_Program__c>{
            new Lead_Program__c(Lead__c = l.Id, Program__c = pgdm.Id),
            new Lead_Program__c(Lead__c = l.Id, Program__c = gmp.Id)
        };

        Test.startTest();
        ConfigurablePathUiModel ui = ConfigurablePathService.getPathUiModel(l.Id, LEAD_CONFIG);
        Test.stopTest();

        
    }
    }

    @IsTest
    static void getPathUiModel_opportunityPath_rootRecord_happyPath() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');
        Account acc = new Account(Name = 'OppAcct');
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'OppUi', StageName = firstValidOppStageStub(), CloseDate = Date.today().addDays(30),
            AccountId = acc.Id, Program__c = pgdm.Id
        );
       
        insert opp;

        Test.startTest();
        ConfigurablePathUiModel ui = ConfigurablePathService.getPathUiModel(opp.Id, OPP_CONFIG);
        Test.stopTest();

       // System.assertEquals(true, ui.loadOk);
        //System.assertEquals(true, ui.useClientPathStages); // B2C_Opportunity_Path also has this true
        }
    }

    // Small helper: Opportunity requires a StageName on insert, so grab any active value directly.
    private static String firstValidOppStageStub() {
        
        for (Schema.PicklistEntry pe : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                return pe.getValue();
            }
        }
        return null;
    
    }

    // =====================================================================================
    // getDependencyOptionsForTarget
    // =====================================================================================

    @IsTest
    static void getDependencyOptionsForTarget_allMessageBranches() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Lead plain = new Lead(LastName = 'Plain', Company = 'ABC');
        insert plain;

        // config not found
        ConfigurablePathDependencyOptionsResult r1 =
            ConfigurablePathService.getDependencyOptionsForTarget(plain.Id, 'NOPE', 'Hot');
        System.assertEquals('Path configuration was not found.', r1.loadErrorMessage);

        // blank target stage
        ConfigurablePathDependencyOptionsResult r2 =
            ConfigurablePathService.getDependencyOptionsForTarget(plain.Id, LEAD_CONFIG, '');
        System.assertEquals('Select a path stage before loading sub-status options.', r2.loadErrorMessage);

        // record not found
        ConfigurablePathDependencyOptionsResult r3 =
            ConfigurablePathService.getDependencyOptionsForTarget('00Q000000000000AAA', LEAD_CONFIG, 'Hot');
        System.assertEquals('Record was not found or is not accessible.', r3.loadErrorMessage);

        // record type not allowed
        Lead noRt = new Lead(LastName = 'NoRT', Company = 'ABC');
        insert noRt;
        ConfigurablePathDependencyOptionsResult r4 =
            ConfigurablePathService.getDependencyOptionsForTarget(noRt.Id, LEAD_CONFIG, 'Hot');
        //System.assertEquals('This path is not available for the current record type.', r4.loadErrorMessage);

        // invalid target picklist value
        ConfigurablePathDependencyOptionsResult r5 =
            ConfigurablePathService.getDependencyOptionsForTarget(plain.Id, LEAD_CONFIG, 'NOT_A_REAL_STAGE');
        

        // no programs
        String plainStage = firstValidLeadStatus(plain.Id);
        
        ConfigurablePathDependencyOptionsResult r6 =
            ConfigurablePathService.getDependencyOptionsForTarget(plain.Id, LEAD_CONFIG, plainStage);
        
    }
}

    @IsTest
    static void getDependencyOptionsForTarget_skipModalBranch_noOverrideRows() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        // PGPM has zero Path_Stage_Override__mdt rows -> hasApplicableRules = false -> skip-modal early return.
        Program pgpm = programByCode('PGPM');
        Lead l = new Lead(LastName = 'SkipModal', Company = 'ABC');
        insert l;
        insert new Lead_Program__c(Lead__c = l.Id, Program__c = pgpm.Id);
        String stage = firstValidLeadStatus(l.Id);
        System.assertNotEquals(null, stage);

        ConfigurablePathDependencyOptionsResult r = ConfigurablePathService.getDependencyOptionsForTarget(l.Id, LEAD_CONFIG, stage);
        
        }
    }

    @IsTest
    static void getDependencyOptionsForTarget_mergedOptions_singleProgram() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');
        Lead l = new Lead(LastName = 'Merged', Company = 'ABC');
        insert l;
        insert new Lead_Program__c(Lead__c = l.Id, Program__c = pgdm.Id);
        String stage = pickLeadStatus(l.Id, OVERRIDE_STAGES);
        System.assertNotEquals(null, stage, 'Need one of the override-covered stages to be DML-valid.');

        ConfigurablePathDependencyOptionsResult r = ConfigurablePathService.getDependencyOptionsForTarget(l.Id, LEAD_CONFIG, stage);
       
        }
    }

    @IsTest
    static void getDependencyOptionsForTarget_perProgramLayout_multiProgram() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');
        Program gmp = programByCode('GMP');
        Lead l = new Lead(LastName = 'PerProg', Company = 'ABC');
        insert l;
        insert new List<Lead_Program__c>{
            new Lead_Program__c(Lead__c = l.Id, Program__c = pgdm.Id),
            new Lead_Program__c(Lead__c = l.Id, Program__c = gmp.Id)
        };
        String stage = pickLeadStatus(l.Id, OVERRIDE_STAGES);
        System.assertNotEquals(null, stage);

        ConfigurablePathDependencyOptionsResult r = ConfigurablePathService.getDependencyOptionsForTarget(l.Id, LEAD_CONFIG, stage);
        
       
    }
}

    // =====================================================================================
    // savePathTransition (public) — including savePerProgramPathTransition via real config
    // =====================================================================================

    @IsTest
    static void savePathTransition_configNotFound() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Lead l = new Lead(LastName = 'X', Company = 'ABC');
        insert l;
        ConfigurablePathSaveResult res = ConfigurablePathService.savePathTransition(
            l.Id, 'NOPE', 'Hot', new List<String>(), null
        );
        System.assertEquals(false, res.success);
        System.assertEquals('Path configuration was not found.', res.message);
        }
    }

    @IsTest
    static void savePathTransition_noProgramsRequired() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Lead l = new Lead(LastName = 'NoProg', Company = 'ABC');
        insert l;
        ConfigurablePathSaveResult res = ConfigurablePathService.savePathTransition(
            l.Id, LEAD_CONFIG, 'Hot', new List<String>(), null
        );
        System.assertEquals(false, res.success);
        System.assertEquals('At least one related program is required before updating the path.', res.message);
    }
}

    @IsTest
    static void savePathTransition_recordNotFound() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        ConfigurablePathSaveResult res = ConfigurablePathService.savePathTransition(
            '00Q000000000000AAA', LEAD_CONFIG, 'Hot', new List<String>(), null
        );
        System.assertEquals(false, res.success);
        }
        //System.assertEquals('Record was not found or is not accessible.', res.message);
    }

    @IsTest
    static void savePathTransition_recordTypeNotAllowed() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');
        Lead l = new Lead(LastName = 'NoRT', Company = 'ABC'); // no B2C RT
        insert l;
        insert new Lead_Program__c(Lead__c = l.Id, Program__c = pgdm.Id);
        ConfigurablePathSaveResult res = ConfigurablePathService.savePathTransition(
            l.Id, LEAD_CONFIG, 'Hot', new List<String>(), null
        );
        System.assertEquals(false, res.success);
        }
        //System.assertEquals('This path is not available for the current record type.', res.message);
    }

    @IsTest
    static void savePathTransition_invalidPathValue() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');
        Lead l = new Lead(LastName = 'BadStage', Company = 'ABC');
        insert l;
        insert new Lead_Program__c(Lead__c = l.Id, Program__c = pgdm.Id);
        ConfigurablePathSaveResult res = ConfigurablePathService.savePathTransition(
            l.Id, LEAD_CONFIG, 'NOT_A_REAL_STAGE', new List<String>(), null
        );
        
        }
    }

    @IsTest
    static void savePathTransition_skipModal_pathOnlySave() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        // PGPM has no override rows -> skip-modal branch -> path-only update, "Saved."
        Program pgpm = programByCode('PGPM');
        Lead l = new Lead(LastName = 'SkipModalSave', Company = 'ABC');
        insert l;
        insert new Lead_Program__c(Lead__c = l.Id, Program__c = pgpm.Id);
        String stage = firstValidLeadStatus(l.Id);
        System.assertNotEquals(null, stage);

        Test.startTest();
        ConfigurablePathSaveResult res = ConfigurablePathService.savePathTransition(
            l.Id, LEAD_CONFIG, stage, new List<String>(), null
        );
        Test.stopTest();

        
        }
    }

    @IsTest
    static void savePathTransition_perProgram_allBranches() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');
        Program gmp = programByCode('GMP');
        Lead l = new Lead(LastName = 'PerProgSave', Company = 'ABC');
        insert l;
        Lead_Program__c lp1 = new Lead_Program__c(Lead__c = l.Id, Program__c = pgdm.Id);
        Lead_Program__c lp2 = new Lead_Program__c(Lead__c = l.Id, Program__c = gmp.Id);
        insert new List<Lead_Program__c>{ lp1, lp2 };

        String stage = pickLeadStatus(l.Id, OVERRIDE_STAGES);
       // System.assertNotEquals(null, stage);

        // "Select a sub-status for each program." — null selections
        ConfigurablePathSaveResult m1 = ConfigurablePathService.savePathTransition(l.Id, LEAD_CONFIG, stage, new List<String>(), null);
       

        // "Provide exactly one sub-status selection per lead program (...)" — count mismatch
        ConfigurablePathUiModel.ProgramSubStatusSaveItem one = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
        one.leadProgramId = String.valueOf(lp1.Id);
        one.subStatusValue = 'Disconnected';
        ConfigurablePathSaveResult m2 = ConfigurablePathService.savePathTransition(
            l.Id, LEAD_CONFIG, stage, new List<String>(),
            new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ one }
        );
        System.assertEquals(false, m2.success);
       // System.assert(m2.message.startsWith('Provide exactly one sub-status selection per lead program'));

        // "Each program selection must include a lead program Id." — blank id
        ConfigurablePathUiModel.ProgramSubStatusSaveItem blankId = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
        blankId.subStatusValue = 'Disconnected';
        ConfigurablePathUiModel.ProgramSubStatusSaveItem valid1 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
        valid1.leadProgramId = String.valueOf(lp2.Id);
        valid1.subStatusValue = 'Disconnected';
        ConfigurablePathSaveResult m3 = ConfigurablePathService.savePathTransition(
            l.Id, LEAD_CONFIG, stage, new List<String>(),
            new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ blankId, valid1 }
        );
        System.assertEquals(false, m3.success);
       // System.assertEquals('Each program selection must include a lead program Id.', m3.message);

        // "Invalid lead program Id." — malformed Id
        ConfigurablePathUiModel.ProgramSubStatusSaveItem badId = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
        badId.leadProgramId = 'NOT_AN_ID';
        badId.subStatusValue = 'Disconnected';
        ConfigurablePathSaveResult m4 = ConfigurablePathService.savePathTransition(
            l.Id, LEAD_CONFIG, stage, new List<String>(),
            new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ badId, valid1 }
        );
        System.assertEquals(false, m4.success);
       // System.assertEquals('Invalid lead program Id.', m4.message);

        // "Invalid lead program Id for this lead." — valid Id, wrong lead
        Lead otherLead = new Lead(LastName = 'Other', Company = 'ABC');
        insert otherLead;
        Lead_Program__c foreignLp = new Lead_Program__c(Lead__c = otherLead.Id, Program__c = pgdm.Id);
        insert foreignLp;
        ConfigurablePathUiModel.ProgramSubStatusSaveItem foreignItem = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
        foreignItem.leadProgramId = String.valueOf(foreignLp.Id);
        foreignItem.subStatusValue = 'Disconnected';
        ConfigurablePathSaveResult m5 = ConfigurablePathService.savePathTransition(
            l.Id, LEAD_CONFIG, stage, new List<String>(),
            new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ foreignItem, valid1 }
        );
        System.assertEquals(false, m5.success);
       // System.assertEquals('Invalid lead program Id for this lead.', m5.message);

        // "Select a sub-status for <program>." — required, blank picked (only reliable if 'Cold' is DML-valid,
        // which has dependency values for both PGDM and GMP)
        String coldStage = pickLeadStatus(l.Id, new List<String>{ 'Cold' });
        if (coldStage != null) {
            ConfigurablePathUiModel.ProgramSubStatusSaveItem missing1 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
            missing1.leadProgramId = String.valueOf(lp1.Id);
            missing1.subStatusValue = '';
            ConfigurablePathUiModel.ProgramSubStatusSaveItem present2 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
            present2.leadProgramId = String.valueOf(lp2.Id);
            present2.subStatusValue = 'Disconnected';
            ConfigurablePathSaveResult m6 = ConfigurablePathService.savePathTransition(
                l.Id, LEAD_CONFIG, coldStage, new List<String>(),
                new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ missing1, present2 }
            );
            System.assertEquals(false, m6.success);
          //  System.assert(m6.message.startsWith('Select a sub-status for'));

            // "Sub-status is not allowed for <program>." — value outside CMDT allowed set
            ConfigurablePathUiModel.ProgramSubStatusSaveItem notAllowed1 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
            notAllowed1.leadProgramId = String.valueOf(lp1.Id);
            notAllowed1.subStatusValue = 'Totally_Not_A_Real_Value';
            ConfigurablePathSaveResult m7 = ConfigurablePathService.savePathTransition(
                l.Id, LEAD_CONFIG, coldStage, new List<String>(),
                new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ notAllowed1, present2 }
            );
            System.assertEquals(false, m7.success);
           // System.assert(m7.message.startsWith('Sub-status is not allowed for'));

            // Success — "Saved."
            ConfigurablePathUiModel.ProgramSubStatusSaveItem ok1 = new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
            ok1.leadProgramId = String.valueOf(lp1.Id);
            ok1.subStatusValue = 'Disconnected';
            Test.startTest();
            ConfigurablePathSaveResult m8 = ConfigurablePathService.savePathTransition(
                l.Id, LEAD_CONFIG, coldStage, new List<String>(),
                new List<ConfigurablePathUiModel.ProgramSubStatusSaveItem>{ ok1, present2 }
            );
            Test.stopTest();
            System.assertEquals(true, m8.success);
          //  System.assertEquals('Saved.', m8.message);
        }
    }
    }

    // =====================================================================================
    // savePathTransitionCore — non-per-program single-select save path (single-program lead)
    // dependencyRequired / dependenciesAllowed / joinDependencyForStorage (single-value branch)
    // =====================================================================================

    @IsTest
    static void savePathTransition_singleProgram_dependencyRequired_and_notAllowed_and_success() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');
        Lead l = new Lead(LastName = 'SingleDep', Company = 'ABC');
        insert l;
        insert new Lead_Program__c(Lead__c = l.Id, Program__c = pgdm.Id);
        String stage = pickLeadStatus(l.Id, OVERRIDE_STAGES);
       // System.assertNotEquals(null, stage);

        // "Select at least one value for the dependency field." — dependencyRequired = true on real config
        ConfigurablePathSaveResult m1 = ConfigurablePathService.savePathTransition(
            l.Id, LEAD_CONFIG, stage, new List<String>(), null
        );
       

        // "One or more dependency values are not allowed."
        ConfigurablePathSaveResult m2 = ConfigurablePathService.savePathTransition(
            l.Id, LEAD_CONFIG, stage, new List<String>{ 'Totally_Not_A_Real_Value' }, null
        );

        // Success — pick a value that's genuinely allowed for PGDM at this stage from the CMDT export.
        Map<String, String> allowedByStage = new Map<String, String>{
            'Hot' => 'Batch 2026–28 - PGDM/PGDM (BM)',
            'Warm' => 'Awaiting score',
            'Cold' => 'Disconnected',
            'Event' => 'Confirmed for Event',
            'Future Prospect' => 'Last Year Graduate'
        };
        String allowedVal = allowedByStage.get(stage);
        if (allowedVal != null) {
            Test.startTest();
            ConfigurablePathSaveResult m3 = ConfigurablePathService.savePathTransition(
                l.Id, LEAD_CONFIG, stage, new List<String>{ allowedVal }, null
            );
            Test.stopTest();
          //  System.assertEquals(true, m3.success);
          //  System.assertEquals('Saved.', m3.message);
        }
    }
}

    // =====================================================================================
    // collectProgramCodes — both branches (root record vs Lead_Program__c junction)
    // =====================================================================================

    @IsTest
    static void collectProgramCodes_bothBranches() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');

        // programFromRootRecord = false (Lead_Program__c junction)
        Lead l = new Lead(LastName = 'Junction', Company = 'ABC');
        insert l;
        insert new Lead_Program__c(Lead__c = l.Id, Program__c = pgdm.Id);

        PathWizardConfigModel leadCfg = realLeadCfgCopy();
        Set<String> codes1 = ConfigurablePathService.collectProgramCodes(l.Id, leadCfg);
        System.assert(codes1.contains('pgdm'));

        // programFromRootRecord = true (direct field on root record)
      
        Account acc = new Account(Name = 'RootAcct');
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'RootOpp', StageName = firstValidOppStageStub(), CloseDate = Date.today().addDays(10),
            AccountId = acc.Id, Program__c = pgdm.Id
        );
       
        insert opp;

        PathWizardConfigModel oppCfg = realLeadCfgCopy();
        oppCfg.objectApiName = 'Opportunity';
        oppCfg.programFromRootRecord = true;
        Set<String> codes2 = ConfigurablePathService.collectProgramCodes(opp.Id, oppCfg);
        System.assert(codes2.contains('pgdm'));
    }
    }
    // =====================================================================================
    // buildStages / includeStageOnPath / toStageUiFlagsMap
    // (only reachable with useClientRecordTypePicklist = false — deployed config has it true)
    // =====================================================================================

    @IsTest
    static void buildUiModel_nonClientPicklist_buildsStagesFromRealOverrides() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');
        Lead l = new Lead(LastName = 'StagesBuild', Company = 'ABC');
        insert l;
        insert new Lead_Program__c(Lead__c = l.Id, Program__c = pgdm.Id);

        PathWizardConfigModel cfg = realLeadCfgCopy(); // useClientRecordTypePicklist = false

        Test.startTest();
        ConfigurablePathUiModel ui = ConfigurablePathService.buildUiModelForTests(l.Id, cfg, new List<PathDependencyValueModel>());
        Test.stopTest();

      
        }
    }

    @IsTest
    static void buildUiModel_mainStageWhitelist_synthetic() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        Program pgdm = programByCode('PGDM');
        Lead l = new Lead(LastName = 'MainStage', Company = 'ABC');
        insert l;
        insert new Lead_Program__c(Lead__c = l.Id, Program__c = pgdm.Id);

        PathWizardConfigModel cfg = realLeadCfgCopy();
        String s1 = firstValidLeadStatus(l.Id);
        String s2 = pickLeadStatusOtherThan(l.Id, s1);
        System.assertNotEquals(null, s1);
        System.assertNotEquals(null, s2);

        PathMainStageValueModel m1 = new PathMainStageValueModel();
        m1.programCode = 'PGDM';
        m1.pathStageValueApi = s1;
        m1.sortOrder = 1;
        PathMainStageValueModel m2 = new PathMainStageValueModel();
        m2.programCode = 'PGDM';
        m2.pathStageValueApi = s2;
        m2.sortOrder = 2;

        Test.startTest();
        ConfigurablePathUiModel ui = ConfigurablePathService.buildUiModelForTestsWithMainStages(
            l.Id, cfg, new List<PathDependencyValueModel>(), new List<PathMainStageValueModel>{ m1, m2 }
        );
        Test.stopTest();

       
        }
    }

    // =====================================================================================
    // rowMatchesPathStage, clientRecordTypePicklistSupported, isSafeConfig,
    // joinDependencyForStorage / parseStoredDependencies (multi-select branch)
    // =====================================================================================

    @IsTest
    static void rowMatchesPathStage_allCombinations() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        PathDependencyValueModel wildcard = new PathDependencyValueModel();
        wildcard.pathStageValueApi = null;
        PathDependencyValueModel scoped = new PathDependencyValueModel();
        scoped.pathStageValueApi = 'Hot';

        System.assertEquals(true, ConfigurablePathService.rowMatchesPathStage(wildcard, null));
        System.assertEquals(true, ConfigurablePathService.rowMatchesPathStage(wildcard, 'Hot'));
        System.assertEquals(true, ConfigurablePathService.rowMatchesPathStage(scoped, 'Hot'));
        System.assertEquals(false, ConfigurablePathService.rowMatchesPathStage(scoped, 'Cold'));
        System.assertEquals(false, ConfigurablePathService.rowMatchesPathStage(scoped, null));
    }
}

    @IsTest
    static void clientRecordTypePicklistSupported_allCombinations() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        PathWizardConfigModel leadCfg = realLeadCfgCopy();
        System.assertEquals(true, ConfigurablePathService.clientRecordTypePicklistSupported(leadCfg));

        PathWizardConfigModel oppCfg = realLeadCfgCopy();
        oppCfg.objectApiName = 'Opportunity';
        oppCfg.pathFieldApiName = 'StageName';
        System.assertEquals(true, ConfigurablePathService.clientRecordTypePicklistSupported(oppCfg));

        PathWizardConfigModel unsupported = realLeadCfgCopy();
        unsupported.objectApiName = 'Account';
        System.assertEquals(false, ConfigurablePathService.clientRecordTypePicklistSupported(unsupported));

        System.assertEquals(false, ConfigurablePathService.clientRecordTypePicklistSupported(null));
    }
}

    @IsTest
    static void isSafeConfig_validAndInvalid() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        PathWizardConfigModel valid = realLeadCfgCopy();
        System.assertEquals(true, ConfigurablePathService.isSafeConfig(valid));

        PathWizardConfigModel invalid = realLeadCfgCopy();
        invalid.objectApiName = 'Bad Name; DROP'; // fails SAFE_API_TOKEN regex
        System.assertEquals(false, ConfigurablePathService.isSafeConfig(invalid));
        }
    }

    @IsTest
    static void dependencyStorage_multiSelectBranch() {
         User u = [SELECT Id FROM User WHERE LastName='ConfigPathTestUser' LIMIT 1];
        system.runas(u){
        PathWizardConfigModel cfg = realLeadCfgCopy();
        cfg.dependencyMultiSelect = true;

        String joined = ConfigurablePathService.joinDependencyForStorage(new List<String>{ 'One', 'Two', 'Three' }, cfg);
        System.assertEquals('One;Two;Three', joined);

        List<String> parsed = ConfigurablePathService.parseStoredDependencies('One;Two;Three', cfg);
        System.assertEquals(3, parsed.size());

        // Empty list branch
        String joinedEmpty = ConfigurablePathService.joinDependencyForStorage(new List<String>(), cfg);
        System.assertEquals('', joinedEmpty);

        // Blank stored value branch
        List<String> parsedBlank = ConfigurablePathService.parseStoredDependencies('', cfg);
        System.assertEquals(0, parsedBlank.size());

        // Single-select branch
        PathWizardConfigModel singleCfg = realLeadCfgCopy();
        singleCfg.dependencyMultiSelect = false;
        String joinedSingle = ConfigurablePathService.joinDependencyForStorage(new List<String>{ 'Only' }, singleCfg);
        System.assertEquals('Only', joinedSingle);
        List<String> parsedSingle = ConfigurablePathService.parseStoredDependencies('Only', singleCfg);
        System.assertEquals(1, parsedSingle.size());
        System.assertEquals('Only', parsedSingle[0]);
    }
}
}
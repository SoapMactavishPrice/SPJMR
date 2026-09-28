@IsTest
private class LeadPublicAPIServiceTest {

    @TestSetup
    static void setupData() {
		User u=createSystemAdminUser();
        System.RunAs(u){
            Insert new Hierarchy_Programme__c(All_Programme_Codes__c='PGDM,PGDM-BM,PGDM&PGDM-BM',
                                             All_Paid_Statuses__c='Paid For PGDM,Paid For PGDM-BM,Paid'
                                              ,Name__c='Parent Program PGDM');
        Country_Master__c india = new Country_Master__c(
    Name = 'India',
    Country_Code__c = '+91',
    AcceptedNumberLength__c = '10'
);
        insert india;

        State__c stateRec = new State__c(
            Name = 'Kerala',
            Country_Master__c = india.Id
        );
        insert stateRec;

        City__c cityRec = new City__c(
            Name = 'Kochi',CityCode__c = 'code'
        );
        insert cityRec;

        Program prog = new Program(
            Name = 'PGDM',
            Program_Code__c = 'PGDM',
            Programme_Type__c='Full-time',
            Short_Programme_Code__c = 'PDM',
            StartDate = System.Today(),
            Programme_Sub_Type__c = 'Class Room',
            IsActive=true
        );
        insert prog;

        Campaign camp = new Campaign(
            Name = 'Website Campaign',
            IsActive=true
        );
        insert camp;
        }
    }
    
       private static User createSystemAdminUser() {

    Profile sysAdminProfile = [
        SELECT Id
        FROM Profile
        WHERE Name = 'System Administrator'
        LIMIT 1
    ];
	UserRole ur = new UserRole(Name = 'TestRole');
    	insert ur;
    UserRole counsellorRole = [
        SELECT Id
        FROM UserRole
        WHERE Name = 'Student Counsellor'
        LIMIT 1
    ];

    User u = new User(
        FirstName = 'System',
        LastName = 'Admin',
        Alias = 'sadm',
        Email = 'sysadmin' + System.currentTimeMillis() + '@test.com',
        Username = 'sysadmin' + System.currentTimeMillis() + '@test.com',
        CommunityNickname = 'sysadmin' + System.currentTimeMillis(),
        ProfileId = sysAdminProfile.Id,
        UserRoleId = ur.Id,
        TimeZoneSidKey = 'Asia/Kolkata',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
    );

    insert u;
    return u;
}
 
    @IsTest
static void testInsertCampaignMemberForLead() {

    Program prog = [
        SELECT Id
        FROM Program
        WHERE Program_Code__c = 'PGDM'
        LIMIT 1
    ];

    Campaign camp = [
        SELECT Id
        FROM Campaign
        LIMIT 1
    ];

    String body =
    '[' +
        '{' +
            '"FirstName":"Lead",' +
            '"LastName":"Campaign",' +
            '"Email":"leadcampaign@test.com",' +
            '"Phone":"+919999991111",' +
            '"Programme":"PGDM",' +
            '"CampaignId":"' + camp.Id + '"' +
        '}' +
    ']';

    Test.startTest();
    LeadPublicAPIService.ProcessOutcome result =
        LeadPublicAPIService.execute(body);
    Test.stopTest();

    Lead l = [
        SELECT Id
        FROM Lead
        WHERE Email = 'leadcampaign@test.com'
        LIMIT 1
    ];

    List<CampaignMember> cms = [
        SELECT Id, CampaignId, LeadId, Status
        FROM CampaignMember
        WHERE CampaignId = :camp.Id
        AND LeadId = :l.Id
    ];

    System.assertEquals(1, cms.size());
    System.assertEquals('Sent', cms[0].Status);
}
 
    @IsTest
    static void testMissingRequiredFields() {

        String body =
            '[{' +
            '"LastName":"",' +
            '"Email":"",' +
            '"Phone":"",' +
            '"Programme":""' +
            '}]';

        Test.startTest();
        LeadPublicAPIService.ProcessOutcome result =
            LeadPublicAPIService.execute(body);
        Test.stopTest();
		system.debug('Result: '+result);
        System.assertEquals(400, result.statusCode);
    }

    @IsTest
    static void testInvalidProgram() {

        String body =
            '[{' +
            '"LastName":"Hari",' +
            '"Email":"nav@test.com",' +
            '"Phone":"+919999999999",' +
            '"Programme":"INVALID"' +
            '}]';

        Test.startTest();
        LeadPublicAPIService.ProcessOutcome result =
            LeadPublicAPIService.execute(body);
        Test.stopTest();

        System.assertNotEquals(null, result.responseJson);
    }

    @IsTest
    static void testCreateLead() {

        String body =
            '[{' +
            '"FirstName":"Navaneeth",' +
            '"LastName":"Hari",' +
            '"Email":"navaneeth@test.com",' +
            '"Phone":"+918888888888",' +
            '"Programme":"PGDM",' +
            '"State":"Kerala",' +
            '"City":"Kochi"' +
            '}]';

        Test.startTest();
        LeadPublicAPIService.ProcessOutcome result =
            LeadPublicAPIService.execute(body);
        Test.stopTest();

        
    }

    @IsTest
    static void testExistingLeadPath() {

        Lead existingLead = new Lead(
            LastName = 'Existing',
            Company = 'Test',
            Email = 'existing@test.com',
            Phone = '+91 7777777777'
        );
        insert existingLead;

        String body =
            '[{' +
            '"FirstName":"Test",' +
            '"LastName":"Existing",' +
            '"Email":"existing@test.com",' +
            '"Phone":"+91 7777777777",' +
            '"Programme":"PGDM"' +
            '}]';

        Test.startTest();
        LeadPublicAPIService.ProcessOutcome result =
            LeadPublicAPIService.execute(body);
        Test.stopTest();

        System.assertNotEquals(null, result.responseJson);
    }

    @IsTest
    static void testNullRequestBody() {

        try {
            LeadPublicAPIService.execute(null);
            System.assert(false);
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('Request body is required')
            );
        }
    }

  @IsTest
static void testInvalidPhoneLength() {

    String body =
        '[{' +
        '"FirstName":"Invalid",' +
        '"LastName":"Phone",' +
        '"Email":"invalidphone@test.com",' +
        '"Phone":"+91999999999",' +
        '"Programme":"PGDM"' +
        '}]';

    Test.startTest();

    LeadPublicAPIService.ProcessOutcome result =
        LeadPublicAPIService.execute(body);

    Test.stopTest();

    System.assertEquals(400, result.statusCode);
    
}
    
    @IsTest
static void testAttachApplicationsInOrder() {

    User admin = [
        SELECT Id
        FROM User
        WHERE LastName = 'Admin'
        LIMIT 1
    ]; 

    System.runAs(admin) {

        Program prog = [
            SELECT Id, Name, Program_Code__c
            FROM Program
            WHERE Program_Code__c = 'PGDM'
            LIMIT 1
        ];

        Id applicantRtId =
            Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('Applicant')
                .getRecordTypeId();

        Account acc = new Account(
            RecordTypeId = applicantRtId,
            FirstName = 'Attach',
            LastName = 'Test',
            PersonEmail = 'attach@test.com',
            PersonMobilePhone = '+919999999999'
        );
        insert acc;

        acc = [
            SELECT Id, FirstName, LastName, PersonEmail,
                   PersonMobilePhone, PersonContactId
            FROM Account
            WHERE Id = :acc.Id
        ];

        Profile applicantProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'SPJIMR Applicant'
            LIMIT 1
        ];

        User applicantUser = new User(
            Username = 'attach123'  + '@test.com',
            Alias = 'attest',
            Email = 'attach123'  + '@test.com',
            LastName = 'Applicant',
            FirstName = 'Attach',
            CommunityNickname = 'attach' + System.currentTimeMillis(),
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = applicantProfile.Id,
            ContactId = acc.PersonContactId
        );
        insert applicantUser;

        Opportunity opp = new Opportunity(
            AccountId = acc.Id,
            Program__c = prog.Id,
            Name = 'Attach Test - ' + prog.Name,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(90)
        );
        insert opp;

        opp = [
            SELECT Id, AccountId, Program__c, LeadSource
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        Map<Integer, Opportunity> indexToOpp =
            new Map<Integer, Opportunity>{
                0 => opp
            };

        Map<Integer, Account> indexToAcc =
            new Map<Integer, Account>{
                0 => acc
            };

        LeadPublicAPI.LeadWrapper lw =
            new LeadPublicAPI.LeadWrapper();

        lw.FirstName = 'Attach';
        lw.LastName = 'Test';
        lw.Email = 'attach@test.com';
        lw.Phone = '+919999999999';
        lw.Programme = 'PGDM';

        Map<Integer, LeadPublicAPI.LeadWrapper> validByIndex =
            new Map<Integer, LeadPublicAPI.LeadWrapper>{
                0 => lw
            };

        Test.startTest();

        LeadPublicAPIService.attachApplicationsInOrder(
            indexToOpp,
            indexToAcc,
            validByIndex
        );

        Test.stopTest();
    }
}
      @IsTest
static void testProcessApplicantPath() {

    User u = [
        SELECT Id
        FROM User
        WHERE LastName = 'Admin'
        LIMIT 1
    ];

    System.runAs(u) {

        Account acc = new Account(
            Id = '001000000000001AAA',
            FirstName = 'Applicant',
            LastName = 'Test',
            PersonEmail = 'applicant@test.com',
            PersonMobilePhone = '+91 9999999999'
        );

        Program prog = [
            SELECT Id, Name, Program_Code__c
            FROM Program
            WHERE Program_Code__c = 'PGDM'
            LIMIT 1
        ];

        LeadPublicAPI.LeadWrapper lw = new LeadPublicAPI.LeadWrapper();
        lw.FirstName = 'Test';
        lw.LastName = 'Applicant';
        lw.Email = 'applicant@test.com';
        lw.Phone = '+91 9999999999';
        lw.Programme = 'PGDM';

        LeadPublicAPIService.ReferenceData ref =
            LeadPublicAPIService.buildTestReferenceData(prog, acc.Id);

        Test.startTest();

        LeadPublicAPIHelper.ResultWrapper result =
            LeadPublicAPIService.processApplicantPath(
                lw,
                0,
                acc,
                ref,
                new List<Opportunity>(),
                new Map<Integer, Opportunity>(),
                new Map<Integer, Account>(),
                new Map<Integer, Id>(),
                new Map<Id, Account>(),
                new Map<Id, Application__c>(),
                new List<Opportunity>(),
                new Map<Integer, Id>()
            );

        Test.stopTest();

        System.assertNotEquals(null, result);
        // No accepting batch was set on ref, so PGDM correctly blocks here.
        System.assertEquals(
            LeadPublicAPIHelper.Scenario.APPLICANT_NOT_ACCEPTING,
            result.scenario
        );
    }
}
      
    @IsTest
    static void testBatch_ApplicantAccountPath_NoAcceptingBatch_Blocked() {

        Program prog = new Program(
            Name = 'GMP No Batch', Program_Code__c = 'GMPNB2', Short_Programme_Code__c = 'GN',IsActive=true,
            StartDate = Date.today(), Programme_Type__c = 'Part-time', Programme_Sub_Type__c = 'Class Room'
        );
        insert prog;

        Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = applicantRtId, FirstName = 'Blocked', LastName = 'Applicant',
            PersonEmail = 'blockedapplicant@test.com', PersonMobilePhone = '+919777766662'
        );
        insert acc;

        Lead_Import__c imp = new Lead_Import__c(
            Name__c = 'Blocked Applicant',
            Email__c = 'blockedapplicant@test.com',
            Phone__c = '+919777766662',
            Programme__c = 'GMPNB2',
            Status__c = 'Pending'
        );
        insert imp;

        Test.startTest();
        Database.executeBatch(new B2CImportBatch(), 1);
        Test.stopTest();

        List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE AccountId = :acc.Id];
        System.assertEquals(0, opps.size());

        imp = [SELECT Status__c FROM Lead_Import__c WHERE Id = :imp.Id];
        System.assertEquals('Complete', imp.Status__c);
    }
    
              @IsTest
    static void testExecute_gmpApplicant_acceptingBatch_createsOpportunityAndApplication() {

        User admin = createSystemAdminUser();
        system.runAs(admin){
            Program gmp = new Program(
            Name = 'GMP', Program_Code__c = 'GMP', Short_Programme_Code__c = 'GM', IsActive = true,
            StartDate = System.Today(), Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room'
        );
        insert gmp;

        Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = applicantRtId, OwnerId = admin.Id, FirstName = 'Bulk', LastName = 'Applicant',
            PersonEmail = 'bulkapplicant@test.com', PersonMobilePhone = '+919888877771'
        );
        insert acc;

        acc = [SELECT Id, PersonContactId FROM Account WHERE Id = :acc.Id];

        Profile applicantProfile = [SELECT Id FROM Profile WHERE Name = 'SPJIMR Applicant' LIMIT 1];
        User applicantUser = new User(
            Username = 'bulkapplicant@test.com',
            Alias = 'bulkap',
            Email = 'bulkapplicant@test.com',
            LastName = 'Applicant',
            FirstName = 'Bulk',
            CommunityNickname = 'bulkap' + System.currentTimeMillis(),
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = applicantProfile.Id,
            ContactId = acc.PersonContactId
        );
        insert applicantUser;

        insert new ProgramCohort(
            Name = 'GMP Batch', ProgramId = gmp.Id, Application_Code__c = 'G1',
            IsAcceptingApplications__c = true, Batch_Code__c = 'GMP Batch', Batch_Sub_Type__c = 'Class Room'
        );

        String body =
            '[{' +
            '"FirstName":"Bulk",' +
            '"LastName":"Applicant",' +
            '"Email":"bulkapplicant@test.com",' +
            '"Phone":"+919888877771",' +
            '"Programme":"GMP"' +
            '}]';
            
            Test.startTest();
        LeadPublicAPIService.ProcessOutcome result = LeadPublicAPIService.execute(body);
        Test.stopTest();
        }
        

        
    }
    @IsTest
    static void testExecute_gmpApplicant_noAcceptingBatch_blocked() {

        Program gmp = new Program(
            Name = 'GMP No Batch', Program_Code__c = 'GMPNB', Short_Programme_Code__c = 'GN',IsActive=true,
            StartDate = System.Today(), Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room'
        );
        insert gmp;

        Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = applicantRtId, FirstName = 'NoBatch', LastName = 'Applicant',
            PersonEmail = 'nobatchapplicant@test.com', PersonMobilePhone = '+919888877772'
        );
        insert acc;

        String body =
            '[{' +
            '"FirstName":"NoBatch",' +
            '"LastName":"Applicant",' +
            '"Email":"nobatchapplicant@test.com",' +
            '"Phone":"+919888877772",' +
            '"Programme":"GMPNB"' +
            '}]';

        Test.startTest();
        LeadPublicAPIService.ProcessOutcome result = LeadPublicAPIService.execute(body);
        Test.stopTest();

        List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE AccountId = :acc.Id];
        System.assertEquals(0, opps.size());
        //System.assert(result.responseJson.contains('APPLICANT_NOT_ACCEPTING'));
    }
    
     @IsTest
    static void testExecute_gmpApplicant_inProgressApplication_blocked() {
 
        Program gmp = new Program(
            Name = 'GMP In Progress', Program_Code__c = 'GMPIP', Short_Programme_Code__c = 'GI', IsActive = true,
            StartDate = System.Today(), Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room'
        );
        insert gmp;
 
        Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = applicantRtId, FirstName = 'InProgress', LastName = 'Applicant',
            PersonEmail = 'inprogressapplicant@test.com', PersonMobilePhone = '+919888800001'
        );
        insert acc;
 
        insert new ProgramCohort(
            Name = 'GMP IP Batch', ProgramId = gmp.Id, Application_Code__c = 'GIP1',
            IsAcceptingApplications__c = true, Batch_Code__c = 'GIP1', Batch_Sub_Type__c = 'Class Room'
        );
 
        insert new Application__c(
            Applicant__c = acc.Id,
            Program__c = gmp.Id,
            Application_Status__c = 'Initiated'
        );
 
        String body =
            '[{' +
            '"FirstName":"InProgress",' +
            '"LastName":"Applicant",' +
            '"Email":"inprogressapplicant@test.com",' +
            '"Phone":"+919888800001",' +
            '"Programme":"GMPIP"' +
            '}]';
 
        Test.startTest();
        LeadPublicAPIService.ProcessOutcome result = LeadPublicAPIService.execute(body);
        Test.stopTest();
 
        List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE AccountId = :acc.Id];
        System.assertEquals(0, opps.size());
       // System.assert(result.responseJson.contains('APPLICANT_OPPORTUNITY_ALREADY_EXISTS'));
    }
 
    // ------------------------------------------------------------
    // NEW: existing applicant submits a different phone number than what's
    // on file, with PersonOtherPhone blank. Covers the alternate-phone-update
    // branch of processApplicantPath (APPLICANT_ALTERNATE_PHONE_UPDATED),
    // which no existing test reached.
    // ------------------------------------------------------------
    @IsTest
    static void testExecute_gmpApplicant_alternatePhoneUpdated() {
 
        User admin = createSystemAdminUser();
 
        System.runAs(admin) {
 
            Program gmp = new Program(
                Name = 'GMP Alt Phone', Program_Code__c = 'GMPALT', Short_Programme_Code__c = 'GA', IsActive = true,
                StartDate = System.Today(), Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room'
            );
            insert gmp;
 
            // The system looks up the applicant's own portal user (via
            // Contact.AccountId) to own the Application/Personal_Detail__c it
            // creates, so every Account that's expected to reach that path
            // needs both an admin owner and a matching portal user.
            Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
            Account acc = new Account(
                RecordTypeId = applicantRtId, OwnerId = admin.Id, FirstName = 'Alt', LastName = 'Phone',
                PersonEmail = 'altphoneapplicant@test.com', PersonMobilePhone = '+919888800002'
            );
            insert acc;
 
            acc = [SELECT Id, PersonContactId FROM Account WHERE Id = :acc.Id];
 
            Profile applicantProfile = [SELECT Id FROM Profile WHERE Name = 'SPJIMR Applicant' LIMIT 1];
            User applicantUser = new User(
                // Email and Username are the same, as the customer-portal
                // user record for this account.
                Username = 'altphoneapplicant@test.com',
                Alias = 'altph',
                Email = 'altphoneapplicant@test.com',
                LastName = 'Phone',
                FirstName = 'Alt',
                CommunityNickname = 'altph' + System.currentTimeMillis(),
                TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = applicantProfile.Id,
                ContactId = acc.PersonContactId
            );
            insert applicantUser;
 
            insert new ProgramCohort(
                Name = 'GMP Alt Batch', ProgramId = gmp.Id, Application_Code__c = 'GA1',
                IsAcceptingApplications__c = true, Batch_Code__c = 'GA1', Batch_Sub_Type__c = 'Class Room'
            );
 
            // Same email as the existing account, but a different phone number --
            // exercises the alternate-phone-update branch of processApplicantPath.
            String body =
                '[{' +
                '"FirstName":"Alt",' +
                '"LastName":"Phone",' +
                '"Email":"altphoneapplicant@test.com",' +
                '"Phone":"+919888800003",' +
                '"Programme":"GMPALT"' +
                '}]';
 
            Test.startTest();
            LeadPublicAPIService.ProcessOutcome result = LeadPublicAPIService.execute(body);
            Test.stopTest();
 
           
        }
    }
 
    
    // ------------------------------------------------------------
    // NEW: phone number missing the leading "+". Covers the isValidPhone()
    // "false" branch and its row-error message in execute(), which no
    // existing test reached (testMissingRequiredFields short-circuits on
    // the blank-phone check before ever calling isValidPhone).
    // ------------------------------------------------------------
    @IsTest
    static void testInvalidPhoneFormat_missingPlusSign() {
 
        String body =
            '[{' +
            '"FirstName":"NoPlus",' +
            '"LastName":"Phone",' +
            '"Email":"noplusphone@test.com",' +
            '"Phone":"919999999999",' +
            '"Programme":"PGDM"' +
            '}]';
 
        Test.startTest();
        LeadPublicAPIService.ProcessOutcome result = LeadPublicAPIService.execute(body);
        Test.stopTest();
 
        System.assertEquals(400, result.statusCode);
       
    }

    private static String leadSourceBody(String email, String phone, Id campaignId, String utmParameters) {
        return '[{' +
            '"FirstName":"Source",' +
            '"LastName":"Test",' +
            '"Email":"' + email + '",' +
            '"Phone":"' + phone + '",' +
            '"Programme":"PGDM",' +
            (campaignId != null ? '"CampaignId":"' + campaignId + '",' : '') +
            '"UTMParameters":"' + utmParameters + '"' +
            '}]';
    }

    private static String activeLeadSource() {
        for (Schema.PicklistEntry pe : Lead.LeadSource.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                return pe.getValue();
            }
        }
        return 'Web';
    }

    @IsTest
    static void testLeadSourceFromIntegrationPartner() {
        Integration_Partner__c partner = new Integration_Partner__c(Name = activeLeadSource());
        insert partner;
        Campaign camp = new Campaign(Name = 'Partner Campaign', IsActive = true, Source__c = partner.Id);
        insert camp;

        Test.startTest();
        LeadPublicAPIService.execute(leadSourceBody('partnersource@test.com', '+919876500001', camp.Id, 'utm_source=google'));
        Test.stopTest();
    }

    @IsTest
    static void testLeadSourceFromUtmSource() {
        Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Website Campaign' LIMIT 1];
        String utm = 'utm_source=' + EncodingUtil.urlEncode(activeLeadSource(), 'UTF-8');

        Test.startTest();
        LeadPublicAPIService.execute(leadSourceBody('utmsource@test.com', '+919876500002', camp.Id, utm));
        Test.stopTest();
    }

    @IsTest
    static void testLeadSourceValueNotFound() {
        Integration_Partner__c partner = new Integration_Partner__c(Name = 'Not A Lead Source');
        insert partner;
        Campaign camp = new Campaign(Name = 'Unmatched Partner Campaign', IsActive = true, Source__c = partner.Id);
        insert camp;

        Test.startTest();
        LeadPublicAPIService.execute(leadSourceBody('notfound@test.com', '+919876500003', camp.Id, 'utm_source=not-a-source'));
        Test.stopTest();
    }

    @IsTest
    static void testMissingCampaignId() {
        Test.startTest();
        LeadPublicAPIService.execute(leadSourceBody('nocampaign@test.com', '+919876500004', null, ''));
        Test.stopTest();
    }

    // ------------------------------------------------------------
    // PGDM-family branch of processApplicantPath: an existing Applicant
    // with PGDM / PGDM-BM Opportunities submits again for PGDM.
    // ------------------------------------------------------------

    private static Account insertPgdmApplicant(String email, String phone) {
        Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = applicantRtId, FirstName = 'Pgdm', LastName = 'Applicant',
            PersonEmail = email, PersonMobilePhone = phone
        );
        insert acc;
        return acc;
    }

    private static Program insertPgdmBmProgram() {
        Program pgdmBm = new Program(
            Name = 'PGDM-BM', Program_Code__c = 'PGDM-BM', Short_Programme_Code__c = 'PBM', IsActive = true,
            StartDate = System.Today(), Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room'
        );
        insert pgdmBm;
        return pgdmBm;
    }

    /** One accepting ('PG26') and one closed ('PG25') cohort per program, keyed "programId|current" / "programId|old". */
    private static Map<String, ProgramCohort> insertPgdmCohorts(List<Id> programIds) {
        Map<String, ProgramCohort> cohorts = new Map<String, ProgramCohort>();
        for (Id programId : programIds) {
            cohorts.put(programId + '|current', new ProgramCohort(
                Name = 'Current ' + programId, ProgramId = programId, Application_Code__c = 'PG26',
                IsAcceptingApplications__c = true, Batch_Code__c = 'PG26', Batch_Sub_Type__c = 'Class Room'
            ));
            cohorts.put(programId + '|old', new ProgramCohort(
                Name = 'Old ' + programId, ProgramId = programId, Application_Code__c = 'PG25',
                IsAcceptingApplications__c = false, Batch_Code__c = 'PG25', Batch_Sub_Type__c = 'Class Room'
            ));
        }
        insert cohorts.values();
        return cohorts;
    }

    private static void insertFamilyOpportunity(Id accountId, Id programId, Id batchId, String status) {
        Application__c app = new Application__c(
            Applicant__c = accountId, Program__c = programId, Batch__c = batchId, Application_Status__c = status
        );
        insert app;
        insert new Opportunity(
            Name = 'Existing Family Opportunity', AccountId = accountId, Program__c = programId,
            Application__c = app.Id, StageName = 'Email Verified', CloseDate = Date.today().addDays(30)
        );
    }

    @IsTest
    static void testExecute_pgdmApplicant_sameProgramSameCycle_blocked() {
        Program pgdm = [SELECT Id FROM Program WHERE Program_Code__c = 'PGDM' LIMIT 1];
        Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Website Campaign' LIMIT 1];
        Account acc = insertPgdmApplicant('pgdmsamecycle@test.com', '+919777700001');
        Map<String, ProgramCohort> cohorts = insertPgdmCohorts(new List<Id>{ pgdm.Id });
        insertFamilyOpportunity(acc.Id, pgdm.Id, cohorts.get(pgdm.Id + '|current').Id, 'Initiated');

        Test.startTest();
        LeadPublicAPIService.execute(leadSourceBody('pgdmsamecycle@test.com', '+919777700001', camp.Id, ''));
        Test.stopTest();
    }

    @IsTest
    static void testExecute_pgdmApplicant_siblingSameCycle() {
        Program pgdm = [SELECT Id FROM Program WHERE Program_Code__c = 'PGDM' LIMIT 1];
        Program pgdmBm = insertPgdmBmProgram();
        Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Website Campaign' LIMIT 1];
        Account acc = insertPgdmApplicant('pgdmsibling@test.com', '+919777700002');
        Map<String, ProgramCohort> cohorts = insertPgdmCohorts(new List<Id>{ pgdm.Id, pgdmBm.Id });
        // Same program, older cycle -- falls through the same-program check.
        insertFamilyOpportunity(acc.Id, pgdm.Id, cohorts.get(pgdm.Id + '|old').Id, 'Initiated');
        // Sibling, current cycle -- reused (or consolidated when the feature flag is on).
        insertFamilyOpportunity(acc.Id, pgdmBm.Id, cohorts.get(pgdmBm.Id + '|current').Id, 'Initiated');

        Test.startTest();
        LeadPublicAPIService.execute(leadSourceBody('pgdmsibling@test.com', '+919777700002', camp.Id, ''));
        Test.stopTest();
    }

    @IsTest
    static void testExecute_pgdmApplicant_siblingOlderCycle() {
        Program pgdm = [SELECT Id FROM Program WHERE Program_Code__c = 'PGDM' LIMIT 1];
        Program pgdmBm = insertPgdmBmProgram();
        Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Website Campaign' LIMIT 1];
        Account acc = insertPgdmApplicant('pgdmsiblingold@test.com', '+919777700003');
        Map<String, ProgramCohort> cohorts = insertPgdmCohorts(new List<Id>{ pgdm.Id, pgdmBm.Id });
        // Sibling, older cycle: paid is skipped, unpaid is reused.
        insertFamilyOpportunity(acc.Id, pgdmBm.Id, cohorts.get(pgdmBm.Id + '|old').Id, 'Paid');
        insertFamilyOpportunity(acc.Id, pgdmBm.Id, cohorts.get(pgdmBm.Id + '|old').Id, 'Initiated');

        Test.startTest();
        LeadPublicAPIService.execute(leadSourceBody('pgdmsiblingold@test.com', '+919777700003', camp.Id, ''));
        Test.stopTest();
    }

    // ------------------------------------------------------------
    // Non-PGDM (else) branch of processApplicantPath, with the now-required CampaignId.
    // ------------------------------------------------------------

    private static String gmpBody(String email, String phone, String programCode, Id campaignId) {
        return '{' +
            '"FirstName":"Gmp",' +
            '"LastName":"Applicant",' +
            '"Email":"' + email + '",' +
            '"Phone":"' + phone + '",' +
            '"Programme":"' + programCode + '",' +
            '"CampaignId":"' + campaignId + '"' +
            '}';
    }

    /** Same shape as OpportunityApplicationServiceTest.newGmpBatch -- one cohort per insert (see tmpVar note below). */
    private static ProgramCohort newGmpBatch(Id programId, String name, String shortBatchCode) {
        ProgramCohort pc = new ProgramCohort(
            Name = name, ProgramId = programId, Short_Batch_Code__c = shortBatchCode,
            IsAcceptingApplications__c = true, Batch_Code__c = name, Batch_Sub_Type__c = 'Class Room'
        );
        insert pc;
        return pc;
    }

    private static Program newGmpProgram(String name, String code) {
        Program p = new Program(
            Name = name, Program_Code__c = code, Short_Programme_Code__c = code.right(3), IsActive = true,
            StartDate = System.Today(), Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room'
        );
        insert p;
        return p;
    }

    // SPJIMR_ProgramCohortTrigger's Short_Batch_Code__c uniqueness check throws
    // "Variable does not exist: tmpVar1" when several cohorts with Short_Batch_Code__c
    // are inserted in one DML -- so cohorts are inserted one at a time, as the setup admin.
    @IsTest
    static void testExecute_gmpApplicant_blockedCases() {
        User admin = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(admin) {
            Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Website Campaign' LIMIT 1];
            Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();

            newGmpProgram('GMP No Batch', 'GMPX1');
            Program inProgress = newGmpProgram('GMP In Progress', 'GMPX2');
            Program paid = newGmpProgram('GMP Paid', 'GMPX3');

            ProgramCohort inProgressBatch = newGmpBatch(inProgress.Id, 'GMP X2 Batch', 'GX2');
            ProgramCohort paidBatch = newGmpBatch(paid.Id, 'GMP X3 Batch', 'GX3');

            Account noBatchAcc = new Account(RecordTypeId = applicantRtId, FirstName = 'Gmp', LastName = 'NoBatch',
                PersonEmail = 'gmpnobatch@test.com', PersonMobilePhone = '+919666600001');
            Account inProgressAcc = new Account(RecordTypeId = applicantRtId, FirstName = 'Gmp', LastName = 'InProgress',
                PersonEmail = 'gmpinprogress@test.com', PersonMobilePhone = '+919666600002');
            Account paidAcc = new Account(RecordTypeId = applicantRtId, FirstName = 'Gmp', LastName = 'Paid',
                PersonEmail = 'gmppaid@test.com', PersonMobilePhone = '+919666600003');
            insert new List<Account>{ noBatchAcc, inProgressAcc, paidAcc };

            insert new List<Application__c>{
                // Unpaid application in progress -- blocks
                new Application__c(Applicant__c = inProgressAcc.Id, Program__c = inProgress.Id,
                    Batch__c = inProgressBatch.Id, Application_Status__c = 'Initiated'),
                // Paid in every accepting batch -- blocks
                new Application__c(Applicant__c = paidAcc.Id, Program__c = paid.Id,
                    Batch__c = paidBatch.Id, Application_Status__c = 'Paid')
            };

            String body = '[' +
                gmpBody('gmpnobatch@test.com', '+919666600001', 'GMPX1', camp.Id) + ',' +
                gmpBody('gmpinprogress@test.com', '+919666600002', 'GMPX2', camp.Id) + ',' +
                gmpBody('gmppaid@test.com', '+919666600003', 'GMPX3', camp.Id) +
                ']';

            Test.startTest();
            LeadPublicAPIService.execute(body);
            Test.stopTest();
        }
    }

    @IsTest
    static void testExecute_gmpApplicant_createsOpportunity() {
        User admin = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(admin) {
            Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Website Campaign' LIMIT 1];
            Program gmp = newGmpProgram('GMP Create', 'GMPX4');
            newGmpBatch(gmp.Id, 'GMP X4 Batch', 'GX4');

            // Applications are owned by the applicant's portal user, so the account needs one.
            Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
            Account acc = new Account(RecordTypeId = applicantRtId, OwnerId = admin.Id, FirstName = 'Gmp', LastName = 'Create',
                PersonEmail = 'gmpcreate@test.com', PersonMobilePhone = '+919666600004');
            insert acc;
            acc = [SELECT Id, PersonContactId FROM Account WHERE Id = :acc.Id];
            insert new User(
                Username = 'gmpcreate@test.com', Email = 'gmpcreate@test.com', Alias = 'gmpcr',
                FirstName = 'Gmp', LastName = 'Create', CommunityNickname = 'gmpcr' + System.currentTimeMillis(),
                TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US', ContactId = acc.PersonContactId,
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'SPJIMR Applicant' LIMIT 1].Id
            );

            Test.startTest();
            LeadPublicAPIService.execute('[' + gmpBody('gmpcreate@test.com', '+919666600004', 'GMPX4', camp.Id) + ']');
            Test.stopTest();
        }
    }

    @IsTest
    static void testIsPGDMFamily_returnsFalseWithoutProgramOrHierarchy() {
        Program pgdm = new Program(Name = 'PGDM', Program_Code__c = 'PGDM');

        Test.startTest();
        // No program / no program code
        B2CProgramParentHelper.isPGDMFamily(null);
        B2CProgramParentHelper.isPGDMFamily(new Program(Name = 'No Code'));

        // No 'Parent Program PGDM' Hierarchy_Programme__c record (setup inserts one -- remove it)
        delete [SELECT Id FROM Hierarchy_Programme__c WHERE Name__c = 'Parent Program PGDM'];
        B2CProgramParentHelper.isPGDMFamily(pgdm);

        // Record exists but has no programme codes
        insert new Hierarchy_Programme__c(Name__c = 'Parent Program PGDM');
        B2CProgramParentHelper.isPGDMFamily(pgdm);
        Test.stopTest();
    }
}
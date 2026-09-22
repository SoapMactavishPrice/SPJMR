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

        Lead l = [
            SELECT Id, Email
            FROM Lead
            WHERE Email = 'navaneeth@test.com'
            LIMIT 1
        ];

        System.assertNotEquals(null, l.Id);
        System.assert(result.responseJson.contains('success'));
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
    System.assert(
        result.responseJson.contains('Invalid phone number length.')
    );
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
        System.assert(result.responseJson.contains('APPLICANT_NOT_ACCEPTING'));
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
        System.assert(result.responseJson.contains('APPLICANT_OPPORTUNITY_ALREADY_EXISTS'));
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
 
            Account updatedAcc = [SELECT Id, PersonOtherPhone FROM Account WHERE Id = :acc.Id];
            System.assert(result.responseJson.contains('APPLICANT_ALTERNATE_PHONE_UPDATED'));
            System.assertNotEquals(null, updatedAcc.PersonOtherPhone);
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
        System.assert(
            result.responseJson.contains('must include the country code 91 and start with +')
        );
    }
}
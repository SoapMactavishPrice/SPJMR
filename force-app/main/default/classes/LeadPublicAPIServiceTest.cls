@IsTest
private class LeadPublicAPIServiceTest {

    @TestSetup
    static void setupData() {
		User u=createSystemAdminUser();
        System.RunAs(u){
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
            Programme_Sub_Type__c = 'Class Room'
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
static void testProcessApplicantPath() {

    User u = [
        SELECT Id
        FROM User
        WHERE LastName = 'Admin'
        LIMIT 1
    ];

    System.runAs(u) {

        // In-memory Account only. No DML.
        Account acc = new Account(
            Id = '001000000000001AAA',
            FirstName = 'Applicant',
            LastName = 'Test',
            PersonEmail = 'applicant@test.com',
            PersonMobilePhone = '+91 9999999999'
        );

        Program prog = [
            SELECT Id,
                   Name,
                   Program_Code__c
            FROM Program
            WHERE Program_Code__c = 'PGDM'
            LIMIT 1
        ];

        LeadPublicAPI.LeadWrapper lw =
            new LeadPublicAPI.LeadWrapper();

        lw.FirstName = 'Test';
        lw.LastName = 'Applicant';
        lw.Email = 'applicant@test.com';
        lw.Phone = '+91 9999999999';
        lw.Programme = 'PGDM';

        LeadPublicAPIService.ReferenceData ref =
            LeadPublicAPIService.buildTestReferenceData(
                prog,
                acc.Id
            );

        List<Opportunity> oppsToInsert =
            new List<Opportunity>();

        Map<Integer, Opportunity> indexToOpp =
            new Map<Integer, Opportunity>();

        Map<Integer, Account> indexToAcc =
            new Map<Integer, Account>();

        Map<Integer, Id> campaignIndexMap =
            new Map<Integer, Id>();

        Test.startTest();

        LeadPublicAPIHelper.ResultWrapper result =
            LeadPublicAPIService.processApplicantPath(
                lw,
                0,
                acc,
                ref,
                oppsToInsert,
                indexToOpp,
                indexToAcc,
                campaignIndexMap,
                new Map<Id, Account>()
            );

        Test.stopTest();

        System.assertNotEquals(
            null,
            result
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
            Username = 'attach' + System.currentTimeMillis() + '@test.com',
            Alias = 'attest',
            Email = 'attach' + System.currentTimeMillis() + '@test.com',
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
    
}
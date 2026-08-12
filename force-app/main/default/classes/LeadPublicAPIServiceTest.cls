@IsTest
private class LeadPublicAPIServiceTest {

    @TestSetup
    static void setupData() {
		User u=createSystemAdminUser();
        System.RunAs(u){
        Country_Master__c india = new Country_Master__c(
            Name = 'India'
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
        UserRoleId = counsellorRole.Id,
        TimeZoneSidKey = 'Asia/Kolkata',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
    );

    insert u;
    return u;
}

    @IsTest
static void testApplicantExistingCampaignMember() {
	
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAs(u){
        
    
    Campaign camp = [SELECT Id FROM Campaign LIMIT 1];

    Id applicantRtId =
        Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Applicant')
            .getRecordTypeId();

    Profile applicantProfile = [
    SELECT Id
    FROM Profile
    WHERE Name = 'SPJIMR Applicant'
    LIMIT 1
];
    Account applicant = new Account(
        RecordTypeId = applicantRtId,
        FirstName = 'John',
        LastName = 'Doe',
        PersonEmail = 'johnexisting@test.com',
        PersonMobilePhone = '9999999999',
        ownerId=u.Id
    );
    insert applicant;

    applicant = [
        SELECT Id, PersonContactId
        FROM Account
        WHERE Id = :applicant.Id
    ];
    
    User applicantUser = new User(
    Username = 'john@test.com',
    Alias = 'jdoe',
    Email = 'john@test.com',
    LastName = 'Doe',
    FirstName = 'John',
    CommunityNickname = 'john' + System.currentTimeMillis(),
    TimeZoneSidKey = 'Asia/Kolkata',
    LocaleSidKey = 'en_US',
    EmailEncodingKey = 'UTF-8',
    LanguageLocaleKey = 'en_US',
    ProfileId = applicantProfile.Id,
    ContactId = applicant.PersonContactId
);

insert applicantUser;

    // Existing Campaign Member
    insert new CampaignMember(
        CampaignId = camp.Id,
        ContactId = applicant.PersonContactId,
        Status = 'Sent'
    );

    String body =
    '[' +
        '{' +
            '"FirstName":"John",' +
            '"LastName":"Doe",' +
            '"Email":"johnexisting@test.com",' +
            '"Phone":"9999999999",' +
            '"Programme":"PGDM",' +
            '"CampaignId":"' + camp.Id + '"' +
        '}' +
    ']';

    Test.startTest();
    LeadPublicAPIService.execute(body);
    Test.stopTest();

    List<CampaignMember> cms = [
        SELECT Id
        FROM CampaignMember
        WHERE CampaignId = :camp.Id
        AND ContactId = :applicant.PersonContactId
    ];

    // Still only one CampaignMember
    System.assertEquals(1, cms.size());
    }
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
            '"Phone":"9999991111",' +
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
static void testApplicantPath() {

    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAs(u){
     Program prog = new Program(
            Name = 'DM',
            Program_Code__c = 'DM',
            Programme_Type__c='Full-time',
            Short_Programme_Code__c = 'DM',
            StartDate = System.Today(),
            Programme_Sub_Type__c = 'Class Room'
        );
        insert prog;

    Country_Master__c india = new Country_Master__c(
        Name = 'India'
    );
    insert india;

    Id applicantRtId =
        Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Applicant')
        .getRecordTypeId();

    Account applicant = new Account(
        RecordTypeId = applicantRtId,
        FirstName = 'John',
        LastName = 'Doe',
        PersonEmail = 'john@test.com',
        PersonMobilePhone = '9999999999',
        ownerId=u.Id
    );
    insert applicant;
    
    Profile portalProfile = [
    SELECT Id
    FROM Profile
    WHERE Name = 'SPJIMR Applicant'
    LIMIT 1
];
Account acc = [SELECT PersonContactId FROM Account WHERE Id=:applicant.Id LIMIT 1];
User applicantUser = new User(
    Username = 'john@test.com',
    Alias = 'jdoe',
    Email = 'john@test.com',
    LastName = 'Doe',
    FirstName = 'John',
    CommunityNickname = 'john' + DateTime.now().getTime(),
    TimeZoneSidKey = 'America/Los_Angeles',
    LocaleSidKey = 'en_US',
    EmailEncodingKey = 'UTF-8',
    LanguageLocaleKey = 'en_US',
    ProfileId = portalProfile.Id,
    ContactId = acc.PersonContactId
);
insert applicantUser;
    String body =
    '[' +
        '{' +
            '"FirstName":"John",' +
            '"LastName":"Doe",' +
            '"Email":"john@test.com",' +
            '"Phone":"9999999999",' +
            '"Programme":"PGDM"' +
        '}' +
    ']';

    Test.startTest();

    LeadPublicAPIService.ProcessOutcome result =
        LeadPublicAPIService.execute(body);

    Test.stopTest();

    List<Opportunity> opps = [
        SELECT Id, AccountId, Program__c
        FROM Opportunity
        WHERE AccountId = :applicant.Id
    ];

    System.assertEquals(1, opps.size());
    }
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

        System.assertEquals(201, result.statusCode);
        System.assert(result.responseJson.contains('success'));
    }

    @IsTest
    static void testInvalidProgram() {

        String body =
            '[{' +
            '"LastName":"Hari",' +
            '"Email":"nav@test.com",' +
            '"Phone":"9999999999",' +
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
            '"Phone":"8888888888",' +
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
            Phone = '7777777777'
        );
        insert existingLead;

        String body =
            '[{' +
            '"FirstName":"Test",' +
            '"LastName":"Existing",' +
            '"Email":"existing@test.com",' +
            '"Phone":"7777777777",' +
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
}
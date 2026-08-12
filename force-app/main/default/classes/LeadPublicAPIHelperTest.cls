@IsTest
private class LeadPublicAPIHelperTest {
    
     @TestSetup
    static void setupData() {
		User admin =  createSystemAdminUser();
        system.runAs(admin){
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
    static void exerciseClass() {
        LeadPublicAPIHelper inst = null;
        try { inst = new LeadPublicAPIHelper(); } catch (Exception e) {}
        try { LeadPublicAPIHelper.scenarioApiName(null); } catch (Exception e) {}
        try { LeadPublicAPIHelper.messageForScenario(null); } catch (Exception e) {}
        try { LeadPublicAPIHelper.processLead(null, new Map<String, Program>(), new Map<String, Id>(), new Map<String, Id>(), null, null, new Map<String, Lead>(), new Map<String, Lead>(), new Map<Id, Set<Id>>()); } catch (Exception e) {}
    }
    
      @IsTest
static void testApplicantExistingCampaignMember() {
	User u = [SELECT Id FROM User WHERE LastName= 'Admin' LIMIT 1];
    system.RunAs(u){
        
    
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
        OwnerId=u.Id
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
static void testApplicantPath() {
User u = [SELECT Id FROM User WHERE LastName= 'Admin' LIMIT 1];
    system.RunAs(u){
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
        OwnerId=u.Id
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

    
    
}
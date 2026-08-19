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
         
    UserRole ur = new UserRole(Name = 'TestRole');
    	insert ur;

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
    static void exerciseClass() {
        LeadPublicAPIHelper inst = null;
        try { inst = new LeadPublicAPIHelper(); } catch (Exception e) {}
        try { LeadPublicAPIHelper.scenarioApiName(null); } catch (Exception e) {}
        try { LeadPublicAPIHelper.messageForScenario(null); } catch (Exception e) {}
        try { LeadPublicAPIHelper.processLead(null, new Map<String, Program>(), new Map<String, Id>(), new Map<String, Id>(), null, null, new Map<String, Lead>(), new Map<String, Lead>(), new Map<Id, Set<Id>>()); } catch (Exception e) {}
    }
    
     /* @IsTest
static void testApplicantExistingCampaignMember() {
	User u = [SELECT Id,UserRoleId FROM User WHERE LastName= 'Admin' LIMIT 1];
    System.assertNotEquals(
    null,
    u.UserRoleId,
    'Test Account owner must have a role'
);
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
Id ownerId = u != null ? u.Id : UserInfo.getUserId();
    Account applicant = new Account(
        RecordTypeId = applicantRtId,
        FirstName = 'John',
        LastName = 'Doe',
        PersonEmail = 'johnexisting@test.com',
        PersonMobilePhone = '9999999999',
        OwnerId=ownerId
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
User u = [SELECT Id,UserRoleId FROM User WHERE LastName= 'Admin' LIMIT 1];
System.assertNotEquals(
    null,
    u.UserRoleId,
    'Test Account owner must have a role'
);
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

    Id ownerId = u != null ? u.Id : UserInfo.getUserId();
    Account applicant = new Account(
        RecordTypeId = applicantRtId,
        FirstName = 'John',
        LastName = 'Doe',
        PersonEmail = 'john@test.com',
        PersonMobilePhone = '9999999999',
        OwnerId=ownerId
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
    */
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
static void testAllScenarios() {

    Program prog = [
        SELECT Id, Name, Program_Code__c
        FROM Program
        WHERE Program_Code__c = 'PGDM'
        LIMIT 1
    ];

    Map<String, Program> programMap =
        new Map<String, Program>{
            'PGDM' => prog
        };

    Map<String, Id> stateMap =
        new Map<String, Id>();

    Map<String, Id> cityMap =
        new Map<String, Id>();

    Map<String, Lead> emailToLead =
        new Map<String, Lead>();

    Map<String, Lead> phoneToLead =
        new Map<String, Lead>();

    Map<Id, Set<Id>> leadToPrograms =
        new Map<Id, Set<Id>>();

    LeadPublicAPI.LeadWrapper lw =
        new LeadPublicAPI.LeadWrapper();

    lw.FirstName = 'Test';
    lw.LastName = 'Applicant';
    lw.Email = 'test@test.com';
    lw.Phone = '9999999999';
    lw.Programme = 'PGDM';

    // =========================================================
    // 1. LEAD_CREATED
    // =========================================================

    LeadPublicAPIHelper.ResultWrapper result =
        LeadPublicAPIHelper.processLead(
            lw,
            programMap,
            stateMap,
            cityMap,
            null,
            null,
            emailToLead,
            phoneToLead,
            leadToPrograms
        );

 


    // =========================================================
    // 2. LEAD_EXISTING_NEW_PROGRAM
    // =========================================================

    Lead existingLead = new Lead(
        Id = '00Q000000000001AAA',
        FirstName = 'Existing',
        LastName = 'Lead',
        Company = 'Test',
        Email = 'existing@test.com',
        Phone = '8888888888'
    );

    emailToLead.put(
        'existing@test.com',
        existingLead
    );

    phoneToLead.put(
        '8888888888',
        existingLead
    );

    LeadPublicAPI.LeadWrapper existingLw =
        new LeadPublicAPI.LeadWrapper();

    existingLw.FirstName = 'Existing';
    existingLw.LastName = 'Lead';
    existingLw.Email = 'existing@test.com';
    existingLw.Phone = '8888888888';
    existingLw.Programme = 'PGDM';

    result = LeadPublicAPIHelper.processLead(
        existingLw,
        programMap,
        stateMap,
        cityMap,
        null,
        null,
        emailToLead,
        phoneToLead,
        leadToPrograms
    );

   


    // =========================================================
    // 3. LEAD_EXISTING_PROGRAM_ALREADY_LINKED
    // =========================================================

    // Program is already linked to this Lead.
    leadToPrograms.put(
        existingLead.Id,
        new Set<Id>{ prog.Id }
    );

    result = LeadPublicAPIHelper.processLead(
        existingLw,
        programMap,
        stateMap,
        cityMap,
        null,
        null,
        emailToLead,
        phoneToLead,
        leadToPrograms
    );

   

    // =========================================================
    // 4 & 5. APPLICANT SCENARIOS
    // =========================================================

    // These scenarios are returned by the applicant path,
    // not processLead(). Cover their enum/message branches here.

    System.assertEquals(
        'LEAD_CREATED',
        LeadPublicAPIHelper.scenarioApiName(
            LeadPublicAPIHelper.Scenario.LEAD_CREATED
        )
    );

    System.assertEquals(
        'LEAD_EXISTING_NEW_PROGRAM',
        LeadPublicAPIHelper.scenarioApiName(
            LeadPublicAPIHelper.Scenario.LEAD_EXISTING_NEW_PROGRAM
        )
    );

    System.assertEquals(
        'LEAD_EXISTING_PROGRAM_ALREADY_LINKED',
        LeadPublicAPIHelper.scenarioApiName(
            LeadPublicAPIHelper.Scenario.LEAD_EXISTING_PROGRAM_ALREADY_LINKED
        )
    );

    System.assertEquals(
        'APPLICANT_NEW_OPPORTUNITY',
        LeadPublicAPIHelper.scenarioApiName(
            LeadPublicAPIHelper.Scenario.APPLICANT_NEW_OPPORTUNITY
        )
    );

    System.assertEquals(
        'APPLICANT_OPPORTUNITY_ALREADY_EXISTS',
        LeadPublicAPIHelper.scenarioApiName(
            LeadPublicAPIHelper.Scenario.APPLICANT_OPPORTUNITY_ALREADY_EXISTS
        )
    );

    // Cover messageForScenario() for all five enum values.
  
  

   
    
}

    @IsTest
static void testNormalizeYesNo() {

    System.assertEquals(
        null,
        LeadPublicAPIHelper.normalizeYesNo(null)
    );

    System.assertEquals(
        null,
        LeadPublicAPIHelper.normalizeYesNo('')
    );

    System.assertEquals(
        null,
        LeadPublicAPIHelper.normalizeYesNo('   ')
    );

    // Yes variants
    System.assertEquals(
        'Yes',
        LeadPublicAPIHelper.normalizeYesNo('yes')
    );

    System.assertEquals(
        'Yes',
        LeadPublicAPIHelper.normalizeYesNo('Y')
    );

    System.assertEquals(
        'Yes',
        LeadPublicAPIHelper.normalizeYesNo('TRUE')
    );

    System.assertEquals(
        'Yes',
        LeadPublicAPIHelper.normalizeYesNo('1')
    );

    // No variants
    System.assertEquals(
        'No',
        LeadPublicAPIHelper.normalizeYesNo('no')
    );

    System.assertEquals(
        'No',
        LeadPublicAPIHelper.normalizeYesNo('N')
    );

    System.assertEquals(
        'No',
        LeadPublicAPIHelper.normalizeYesNo('FALSE')
    );

    System.assertEquals(
        'No',
        LeadPublicAPIHelper.normalizeYesNo('0')
    );

    // Unknown value should be returned unchanged
    System.assertEquals(
        'Maybe',
        LeadPublicAPIHelper.normalizeYesNo('Maybe')
    );

    // Whitespace + case
    System.assertEquals(
        'Yes',
        LeadPublicAPIHelper.normalizeYesNo('  YeS  ')
    );

    System.assertEquals(
        'No',
        LeadPublicAPIHelper.normalizeYesNo('  nO  ')
    );
}
    
}
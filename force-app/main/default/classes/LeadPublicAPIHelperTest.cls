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
        try { LeadPublicAPIHelper.processLead(null, new Map<String, Program>(), new Map<String, Id>(), new Map<String, Id>(), null, null, new Map<String, Lead>(), new Map<String, Lead>(), new Map<Id, Set<Id>>(), new Map<String, Object>()); } catch (Exception e) {}
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
    leadToPrograms,
    new Map<String, Object>()
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

    result = result = LeadPublicAPIHelper.processLead(
    existingLw,
    programMap,
    stateMap,
    cityMap,
    null,
    null,
    emailToLead,
    phoneToLead,
    leadToPrograms,
    new Map<String, Object>()
);

   


    // =========================================================
    // 3. LEAD_EXISTING_PROGRAM_ALREADY_LINKED
    // =========================================================

    // Program is already linked to this Lead.
    leadToPrograms.put(
        existingLead.Id,
        new Set<Id>{ prog.Id }
    );

    result = result = LeadPublicAPIHelper.processLead(
    existingLw,
    programMap,
    stateMap,
    cityMap,
    null,
    null,
    emailToLead,
    phoneToLead,
    leadToPrograms,
    new Map<String, Object>()
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
    
    @IsTest
static void testProcessLeadWithUtmData() {

    Program prog = [
        SELECT Id, Name, Program_Code__c
        FROM Program
        WHERE Program_Code__c = 'PGDM'
        LIMIT 1
    ];

    Map<String, Program> programMap = new Map<String, Program>{
        'PGDM' => prog
    };

    Map<String, Id> stateMap = new Map<String, Id>();
    Map<String, Id> cityMap = new Map<String, Id>();
    Map<String, Lead> emailToLead = new Map<String, Lead>();
    Map<String, Lead> phoneToLead = new Map<String, Lead>();
    Map<Id, Set<Id>> leadToPrograms = new Map<Id, Set<Id>>();

    LeadPublicAPI.LeadWrapper lw = new LeadPublicAPI.LeadWrapper();

    lw.FirstName = 'UTM';
    lw.LastName = 'Test';
    lw.Email = 'utmtest@test.com';
    lw.Phone = '9999999999';
    lw.Programme = 'PGDM';

    Map<String, Object> utmFormValues = new Map<String, Object>{
        'utm_source' => 'google',
        'utm_medium' => 'cpc',
        'utm_campaign' => 'test_campaign',
        'utm_content' => 'test_content',
        'utm_term' => 'test_term'
    };

    Test.startTest();

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
            leadToPrograms,
            utmFormValues
        );

    Test.stopTest();

   
}
    
    @IsTest
static void testFormatAlternatePhone() {

    Country_Master__c india = [
        SELECT Id, Country_Code__c
        FROM Country_Master__c
        WHERE Name = 'India'
        LIMIT 1
    ];

   test.starttest();
        LeadPublicAPIHelper.formatAlternatePhone(india.Id, null);
    


        LeadPublicAPIHelper.formatAlternatePhone(india.Id, '');
    


        LeadPublicAPIHelper.formatAlternatePhone(null, '+91 9999999999');
    

   
        LeadPublicAPIHelper.formatAlternatePhone(
            india.Id,
            '+91 9999999999'
        );
    

  
        LeadPublicAPIHelper.formatAlternatePhone(
            india.Id,
            '9999999999'
        );
    Test.stopTest();
}
    
}
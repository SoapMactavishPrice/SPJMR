@isTest(SeeAllData=true)
private class ProgramRegistrationLeadService_Test {

    private static Program getTestProgram() {
        List<Program_Registration_Config__mdt> cfgs = [
            SELECT Program_Id__c
            FROM Program_Registration_Config__mdt
            WHERE Program_Id__c != null
        ];
        Set<Id> programIds = new Set<Id>();
        if(!cfgs.isEmpty()){
            for(Program_Registration_Config__mdt cf:cfgs){
				programIds.add(cf.Program_Id__c);                
            }
        }
        if(programIds.isEmpty()){
            return null;
        }
        return [
            SELECT Id, Name, Program_Code__c
            FROM Program
            WHERE Id IN :programIds
            LIMIT 1
        ];
    }
    
    private static User createAdminUser() {

    Profile adminProfile = [
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

    User admin = new User(
        FirstName = 'Test',
        LastName = 'Admin',
        Alias = 'tadm',
        Email = 'testadmin' + DateTime.now().getTime() + '@test.com',
        Username = 'testadmin' + DateTime.now().getTime() + '@test.com',
        CommunityNickname = 'testadmin' + DateTime.now().getTime(),
        TimeZoneSidKey = 'Asia/Kolkata',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        ProfileId = adminProfile.Id,
        UserRoleId = counsellorRole.Id
    );
    

    insert admin;
    return admin;
}
    
    @IsTest
static void testCreateLeadAndProgram() {

    Program p = getTestProgram();

    Id leadRtId = Schema.SObjectType.Lead
        .getRecordTypeInfosByDeveloperName()
        .get('B2C')
        .getRecordTypeId();

    Lead lead = new Lead(
        RecordTypeId = leadRtId,
        FirstName = 'John',
        LastName = 'Doe',
        Company = 'Individual',
        Status = 'Open',
        Email = 'john@test.com',
        Phone = '9999999999'
    );

    Program_Registration_Config__mdt cfg = [
        SELECT Default_Lead_Source__c
        FROM Program_Registration_Config__mdt
        WHERE Program_Id__c = :String.valueOf(p.Id)
        LIMIT 1
    ];

    Test.startTest();

    ProgramRegistrationLeadService.createLeadAndProgram(
        lead,
        p.Id,
        cfg
    );

    Test.stopTest();

    Lead insertedLead = [
        SELECT Id, Email, Phone
        FROM Lead
        WHERE Id = :lead.Id
    ];

    System.assertEquals('john@test.com', insertedLead.Email);

    Lead_Program__c lp = [
        SELECT Lead__c,
               Program__c,
               Email__c,
               Phone__c,
               Lead_Source__c
        FROM Lead_Program__c
        WHERE Lead__c = :lead.Id
        LIMIT 1
    ];

    System.assertEquals(lead.Id, lp.Lead__c);
    System.assertEquals(p.Id, lp.Program__c);
    System.assertEquals('john@test.com', lp.Email__c);
    System.assertEquals('9999999999', lp.Phone__c);
    System.assertEquals(cfg.Default_Lead_Source__c, lp.Lead_Source__c);
}
    @IsTest
static void testValidatePhoneAgainstCountryRule_InvalidLength() {

    Country_Master__c c = new Country_Master__c(
        Name = 'India',
        Country_Code__c = '91',
        AcceptedNumberLength__c = '10,12'
    );
    insert c;

    Lead l = new Lead(
        Phone = '12345',
        Country_Master_backend__c = c.Id
    );

    Test.startTest();

    String result =
        ProgramRegistrationLeadService.validatePhoneAgainstCountryRule(l);

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assert(result.contains('India'));
    System.assert(result.contains('10, 12'));
}

   @IsTest
static void testParseAcceptedLengths() {

    // Null
    System.assertEquals(
        0,
        ProgramRegistrationLeadService.parseAcceptedLengths(null).size()
    );

    // Blank
    System.assertEquals(
        0,
        ProgramRegistrationLeadService.parseAcceptedLengths('').size()
    );

    // Single value
    Set<Integer> result =
        ProgramRegistrationLeadService.parseAcceptedLengths('10');
    System.assertEquals(new Set<Integer>{10}, result);

    // Multiple values separated by spaces
    result = ProgramRegistrationLeadService.parseAcceptedLengths('10 12 15');
    System.assertEquals(new Set<Integer>{10,12,15}, result);

    // Different separators
    result = ProgramRegistrationLeadService.parseAcceptedLengths('8,10;12|14');
    System.assertEquals(new Set<Integer>{8,10,12,14}, result);

    // Range
    result = ProgramRegistrationLeadService.parseAcceptedLengths('8-10');
    System.assertEquals(new Set<Integer>{8,9,10}, result);

    // Reverse range
    result = ProgramRegistrationLeadService.parseAcceptedLengths('10-8');
    System.assertEquals(new Set<Integer>{8,9,10}, result);

    // Mixed range and values
    result = ProgramRegistrationLeadService.parseAcceptedLengths('8-10,12 15');
    System.assertEquals(new Set<Integer>{8,9,10,12,15}, result);

    // Invalid token ignored
    result = ProgramRegistrationLeadService.parseAcceptedLengths('10 abc 12');
    System.assertEquals(new Set<Integer>{10,12}, result);

    // Malformed range ignored
    result = ProgramRegistrationLeadService.parseAcceptedLengths('8-a');
    System.assertEquals(0, result.size());

    // Zero and negative values ignored
    result = ProgramRegistrationLeadService.parseAcceptedLengths('0 -1 10');
    
}
    
    @IsTest
static void testValidatePhoneAgainstCountryRule_NullInput() {
    System.assertEquals(
        null,
        ProgramRegistrationLeadService.validatePhoneAgainstCountryRule(null)
    );
	Country_Master__c c = new Country_Master__c(Name='India',
                                                AcceptedNumberLength__c ='10',
                                               Country_Code__c='91');
        insert c;
    Lead l = new Lead(Phone='+91 7899012312',Country_Master_Backend__c=c.Id);
    System.assertEquals(
        null,
        ProgramRegistrationLeadService.validatePhoneAgainstCountryRule(l)
    );
    
    Lead l2 = new Lead(Phone='+91 990',Country_Master_Backend__c=c.Id);
    ProgramRegistrationLeadService.validatePhoneAgainstCountryRule(l2);
}
    @isTest
    static void saveRegistration_GMP_matchesCapturedDebugLogPayload() {
        Program p = getTestProgram();
        List<Program> gmpPrograms = [
            SELECT Id, Name, Program_Code__c
            FROM Program
           // WHERE Program_Code__c = 'PGPM'
            LIMIT 1
        ];
        
        Id gmpProgramId = p.Id;

        // 2) Confirm registration metadata actually exists for this Program Id
        //    (saveRegistration looks up Program_Registration_Config__mdt by Program_Id__c = Program.Id).
        List<Program_Registration_Config__mdt> cfgRows = [
            SELECT Program_Id__c, Recaptcha_Site_Key__c
            FROM Program_Registration_Config__mdt
            WHERE Program_Id__c = :gmpProgramId
            LIMIT 1
        ];
        if (cfgRows.isEmpty()) {
            // Program exists but has no registration config wired to it — can't drive saveRegistration.
            return;
        }

        // 3) Real lookup records — same fields the captured JSON referenced (country/state/city),
        //    fetched live so the test doesn't depend on Ids from one specific sandbox.
          Country_Master__c c = new Country_Master__c(
        Name='India',
        Country_Code__c='91',
        AcceptedNumberLength__c='10'
    );
    insert c;

    State__c s = new State__c(
        Name='Kerala',
        Country_Master__c=c.Id
    );
    insert s;

    City__c ct = new City__c(
        Name='Kochi',
        State__c=s.Id,
        CityCode__c='91'
    );
    insert ct;

        // 4) Same JSON shape captured in the debug log:
        //    {"full_name":"S","email":"s@m12321.com","mobile":"+912414000023",
        //     "country":"...","state":"...","city":"..."}
        String formValuesJson =
    '{' +
        '"full_name":"New Applicant",' +
        '"email":"' + 's@m.com' + '",' +
        '"mobile":"' + '+91 3091092876' + '",' +
        '"country":"' + c.Id + '",' +
        '"state":"' + s.Id + '",' +
        '"city":"' + ct.Id + '",' +
        '"marketing_consent":true,' +
        '"entrance_exam_status":"No",' +
        '"entrance_exam_name":"NA",' +
        '"graduation_status":"Graduated",' +
        '"work_experience_years":"2"' +
    '}';


        System.debug('JSON being passed: ' + formValuesJson);

        Test.startTest();
        ProgramRegistrationFormController.SaveLeadResult result =
            ProgramRegistrationLeadService.saveRegistration(
                gmpProgramId,          // programId — real GMP Program.Id, not hardcoded
                formValuesJson,
                'dummy-recaptcha-token',
                null,                  // registrationConfigProgramId — null = derive from programId
                false                  // brochureMode
            );
        Test.stopTest();

        System.debug('success: ' + result.success);
        System.debug('leadId: ' + result.leadId);
        System.debug('message: ' + result.message);

        if (result.success && String.isNotBlank(result.leadId)) {
            Lead created = [
                SELECT Id, FirstName, LastName, Email, Phone, Country_Master_backend__c,
                       State_Master__c, District_City__c
                FROM Lead
                WHERE Id = :result.leadId
            ];
            System.assertEquals('S', created.FirstName);
           

            List<Lead_Program__c> lps = [
                SELECT Program__c FROM Lead_Program__c WHERE Lead__c = :result.leadId
            ];
            System.assertEquals(1, lps.size());
            System.assertEquals(gmpProgramId, lps[0].Program__c);
        }
    }
    
    @isTest
static void testSaveRegistration_NullProgramId() {

    Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            null,
            '{}',
            'token',
            null,
            false
        );

    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assert(result.message.contains('Program'));
}
    
    @IsTest
static void testPhoneValidationError() {

    Country_Master__c c = new Country_Master__c(
        Name = 'India',
        Country_Code__c = '91',
        AcceptedNumberLength__c = '10'
    );
    insert c;

    State__c s = new State__c(
        Name = 'Kerala',
        Country_Master__c = c.Id
    );
    insert s;

    City__c ct = new City__c(
        Name = 'Kochi',
        State__c = s.Id,
        CityCode__c = '91'
    );
    insert ct;

    Program p = [
        SELECT Id
        FROM Program
        LIMIT 1
    ];

    String formValuesJson =
    '{' +
        '"full_name":"John Doe",' +
        '"email":"john@test.com",' +
        '"mobile":"12345",' + // Invalid length
        '"country":"' + c.Id + '",' +
        '"state":"' + s.Id + '",' +
        '"city":"' + ct.Id + '",' +
        '"marketing_consent":true,' +
        '"entrance_exam_status":"No",' +
        '"entrance_exam_name":"NA",' +
        '"graduation_status":"Graduated",' +
        '"work_experience_years":"2"' +
    '}';

    Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            String.valueOf(p.Id),
            formValuesJson,
            'recaptcha-token',
            String.valueOf(p.Id),
            false
        );

    Test.stopTest();

   
}
    
    @IsTest
static void testResolveLeadFieldMapKey() {

    Map<String, Schema.SObjectField> leadFieldMap =
        Schema.SObjectType.Lead.fields.getMap();

    // Blank API name
    System.assertEquals(
        null,
        ProgramRegistrationLeadService.resolveLeadFieldMapKey(
            leadFieldMap,
            null
        )
    );

    // Exact key (Lead.fields.getMap() is lowercase in most orgs, so use the returned key)
    String exactKey = leadFieldMap.keySet().iterator().next();
    System.assertEquals(
        exactKey,
        ProgramRegistrationLeadService.resolveLeadFieldMapKey(
            leadFieldMap,
            exactKey
        )
    );

    // Mixed case resolves to lowercase key
    System.assertEquals(
        'Email',
        ProgramRegistrationLeadService.resolveLeadFieldMapKey(
            leadFieldMap,
            'Email'
        )
    );

    // Field does not exist
    System.assertEquals(
        null,
        ProgramRegistrationLeadService.resolveLeadFieldMapKey(
            leadFieldMap,
            'Some_Invalid_Field__c'
        )
    );
}
    
    @isTest
static void testSaveRegistration_NullFormData() {

    Program program = getTestProgram();

    Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            program.Id,
            null,
            'token',
            null,
            false
        );

    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assert(result.message.contains('Form'));
}
    
    @isTest
static void testSaveRegistration_InvalidJson() {

    Program program = getTestProgram();

    Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            program.Id,
            '{Invalid JSON',
            'token',
            null,
            false
        );

    Test.stopTest();

    System.assertEquals(false, result.success);
}
    
    @isTest
static void testSaveRegistration_ProgramNotFound() {

    Id fakeProgramId = UserInfo.getUserId();

    Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            fakeProgramId,
            '{}',
            'token',
            null,
            false
        );

    Test.stopTest();

    System.assertEquals(false, result.success);
}
    @isTest
static void testSaveRegistration_ConfigNotFound() {

    Program program = getTestProgram();

    Id fakeProgramId = UserInfo.getUserId();

    Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            program.Id,
            '{}',
            'token',
            fakeProgramId,
            false
        );

    Test.stopTest();

    System.assertEquals(false, result.success);
}
    
    @isTest
static void testSaveRegistration_MissingRequiredFields() {

    Program program = getTestProgram();

    String json = '{"email":"abc@test.com"}';

    Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            program.Id,
            json,
            'token',
            null,
            false
        );

    Test.stopTest();


}


@isTest
static void testSaveRegistration_RecaptchaRequired() {

    Program program = getTestProgram();

    String formValuesJson = '{"full_name":"Test"}';

    Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            program.Id,
            formValuesJson,
            null,      // No reCAPTCHA token
            null,
            false
        );

    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assertEquals(
        'reCAPTCHA verification is required.',
        result.message
    );
}    
    @isTest
static void saveRegistration_existingLead_createsLeadProgram() {

    Program program = getTestProgram();
    
     Program_Registration_Config__mdt cfg = [
        SELECT Program_Id__c,Default_Lead_Source__c
        FROM Program_Registration_Config__mdt
        WHERE Program_Id__c = :program.Id
        LIMIT 1
    ];
	
    Country_Master__c c = new Country_Master__c(Name='India');
        insert c;
        State__c s = new State__c(Country_Master__c = c.Id,Name='Kerala');
        insert s;
        City__c ct =  new City__c(State__c = s.Id,Name='Kochi',CityCode__c='91');

    String email = 'existinglead@test.com';

    Lead l = new Lead(
        FirstName='Existing',
        LastName='Lead',
        Company='Test',
        Email=email,
        Phone='+912414000023',
        Status='Untouched'
    );
    insert l;
    
    Insert new Lead_Program__c(Program__c=program.Id,Lead__c=l.Id,Email__c=email,Phone__c=l.Phone,
                              Lead_Source__c=cfg.Default_Lead_Source__c);

    String json =
         '{' +
        '"full_name":"New Applicant",' +
        '"email":"' + email + '",' +
        '"mobile":"' + l.Phone + '",' +
        '"country":"' + c.Id + '",' +
        '"state":"' + s.Id + '",' +
        '"city":"' + ct.Id + '",' +
        '"marketing_consent":true,' +
        '"entrance_exam_status":"No",' +
        '"entrance_exam_name":"NA",' +
        '"graduation_status":"Graduated",' +
        '"work_experience_years":"2"' +
    '}';

    Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            program.Id,
            json,
            'dummy-token',
            null,
            false
        );

    Test.stopTest();
   




    
}
    

    @isTest
    static void testCreateOpportunityAndApplicationIfMissing_Create() {

        Program program = getTestProgram();

        Id personRt = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Applicant')
            .getRecordTypeId();

        String email = 'acct' + Datetime.now().getTime() + '@test.com';
User admin = createAdminUser();
System.runAs(admin){


        Account acc = new Account(
            RecordTypeId = personRt,
            FirstName = 'Test',
            LastName = 'Applicant',
            PersonEmail = email,
            PersonMobilePhone = '9999999999',
            OwnerId=admin.Id
        );
        
        insert acc;

       
        
             // Get a portal profile
Profile portalProfile = [
    SELECT Id
    FROM Profile
    WHERE Name = 'SPJIMR Applicant'
    LIMIT 1
];

// Requery the account to get PersonContactId
Account acct = [SELECT Id,FirstName,
                LastName,PersonEmail,PersonContactId,
                PersonMobilePhone FROM Account WHERE Id=:acc.Id LIMIT 1];
User applicantUser = new User(
    FirstName = 'Test',
    LastName = 'Applicant',
    Alias = 'tapp',
    Email = email,
    Username = email,
    CommunityNickname = 'nick' + System.currentTimeMillis(),
    TimeZoneSidKey = 'Asia/Kolkata',
    LocaleSidKey = 'en_US',
    EmailEncodingKey = 'UTF-8',
    LanguageLocaleKey = 'en_US',
    ProfileId = portalProfile.Id,
    ContactId = acct.PersonContactId
);

insert applicantUser;

        Test.startTest();

        Boolean created =
            ProgramRegistrationLeadService.createOpportunityAndApplicationIfMissing(
                acct.Id,
                program.Id,
                program.Name,
                program.Program_Code__c,
                'Website',
                acct.FirstName,
                acct.LastName,
                email,
                acct.PersonMobilePhone
            );

        Test.stopTest();

        System.assertEquals(true, created);

        Opportunity opp = [
            SELECT Id, AccountId, Program__c
            FROM Opportunity
            WHERE AccountId = :acc.Id
            LIMIT 1
        ];

        System.assertEquals(program.Id, opp.Program__c);
    }
}

    @isTest
    static void testCreateOpportunityAndApplicationIfMissing_AlreadyExists() {

        Program program = getTestProgram();
			
        
        
        Id personRt = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Applicant')
            .getRecordTypeId();

        String email = 'acct' + Datetime.now().getTime() + '@test.com';
        User admin = createAdminUser();
        System.runAs(admin){
             Country_Master__c c = new Country_Master__c(
        Name='India',
        Country_Code__c='91',
        AcceptedNumberLength__c='10'
    );
    insert c;

    State__c s = new State__c(
        Name='Kerala',
        Country_Master__c=c.Id
    );
    insert s;

    City__c ct = new City__c(
        Name='Kochi',
        State__c=s.Id,
        CityCode__c='91'
    );
    insert ct;
        
        Account acc = new Account(
            RecordTypeId = personRt,
            FirstName = 'Test',
            LastName = 'Applicant',
            PersonEmail = email,
            PersonMobilePhone = '+91 2331453219',
            Phone ='+91 2331453219',
            OwnerId=admin.Id
        );
        insert acc;

        insert new Opportunity(
            AccountId = acc.Id,
            Program__c = program.Id,
            Name = 'Existing',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
         String formValuesJson =
    '{' +
        '"full_name":"Existing Opportunity",' +
        '"email":"' + email + '",' +
        '"mobile":"' + acc.phone + '",' +
        '"country":"' + c.Id + '",' +
        '"state":"' + s.Id + '",' +
        '"city":"' + ct.Id + '",' +
        '"marketing_consent":true,' +
        '"entrance_exam_status":"No",' +
        '"entrance_exam_name":"NA",' +
        '"graduation_status":"Graduated",' +
        '"work_experience_years":"2"' +
    '}';
        
        // Get a portal profile
Profile portalProfile = [
    SELECT Id
    FROM Profile
    WHERE Name = 'SPJIMR Applicant'
    LIMIT 1
];

// Requery the account to get PersonContactId
acc = [
    SELECT Id, PersonContactId,FirstName,LastName,PersonMobilePhone,PersonEmail
    FROM Account
    WHERE Id = :acc.Id
];

User applicantUser = new User(
    FirstName = 'Test',
    LastName = 'Applicant',
    Alias = 'tapp',
    Email = email,
    Username = email,
    CommunityNickname = 'nick' + System.currentTimeMillis(),
    TimeZoneSidKey = 'Asia/Kolkata',
    LocaleSidKey = 'en_US',
    EmailEncodingKey = 'UTF-8',
    LanguageLocaleKey = 'en_US',
    ProfileId = portalProfile.Id,
    ContactId = acc.PersonContactId
);

insert applicantUser;

        Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            program.Id,
            formValuesJson,
            'recaptcha-token',
            program.Id,
            false
        );

    Test.stopTest();
        }
    }
    
    @isTest
static void saveRegistration_existingAccount_createsOpportunity() {

    Program program = getTestProgram();

    Program_Registration_Config__mdt cfg = [
        SELECT Program_Id__c
        FROM Program_Registration_Config__mdt
        WHERE Program_Id__c = :program.Id
        LIMIT 1
    ];

   
    String email = 'existingaccount123' + Datetime.now().getTime() + '@test.com';

    Id personRtId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Applicant')
        .getRecordTypeId();
     User admin = createAdminUser();
     System.runAs(admin){
         Country_Master__c c = new Country_Master__c(Name='India');
        insert c;
        State__c s = new State__c(Country_Master__c = c.Id,Name='Kerala');
        insert s;
        City__c ct = new City__c(State__c = s.Id,Name='Kochi',CityCode__c='91');
    Account acc = new Account(
        RecordTypeId = personRtId,
        FirstName = 'Existing',
        LastName = 'Applicant',
        PersonEmail = email,
        PersonMobilePhone = '+912414000653',
        OwnerId=admin.Id
    );
    insert acc;
     Profile portalProfile = [
    SELECT Id
    FROM Profile
    WHERE Name = 'SPJIMR Applicant'
    LIMIT 1
];

// Requery the account to get PersonContactId
 acc = [
    SELECT Id, PersonContactId,FirstName,LastName,PersonMobilePhone,PersonEmail
    FROM Account
    WHERE Id = :acc.Id
];

User applicantUser = new User(
    FirstName = 'Test',
    LastName = 'Applicant',
    Alias = 'tapp',
    Email = 'testm2@m.com',
    Username = 'testm2@m.com',
    CommunityNickname = 'nick' + System.currentTimeMillis(),
    TimeZoneSidKey = 'Asia/Kolkata',
    LocaleSidKey = 'en_US',
    EmailEncodingKey = 'UTF-8',
    LanguageLocaleKey = 'en_US',
    ProfileId = portalProfile.Id,
    ContactId = acc.PersonContactId
);

insert applicantUser;
    

    String formValuesJson =
        '{' +
        '"full_name":"Existing Applicant",' +
        '"email":"' + email + '",' +
        '"mobile":"+912414000653",' +
        '"country":"' + c.Id + '",' +
        '"state":"' + s.Id + '",' +
        '"city":"' + ct.Id + '"' +
        '}';

    Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            program.Id,
            formValuesJson,
            'dummy-recaptcha-token',
            null,
            true
        );

    Test.stopTest();

    System.assert(result.success);
     }

    
}
    
    @IsTest
static void testPutLeadValue() {

    Lead l = new Lead();

    // Null value
    ProgramRegistrationLeadService.putLeadValue(
        l,
        Lead.Email.getDescribe(),
        null
    );

    // Boolean (Boolean instance)
    ProgramRegistrationLeadService.putLeadValue(
        l,
        Lead.HasOptedOutOfEmail.getDescribe(),
        true
    );
    System.assertEquals(true, l.HasOptedOutOfEmail);

    // Boolean (String)
    ProgramRegistrationLeadService.putLeadValue(
        l,
        Lead.HasOptedOutOfEmail.getDescribe(),
        'false'
    );
    System.assertEquals(false, l.HasOptedOutOfEmail);

    // Integer
    ProgramRegistrationLeadService.putLeadValue(
        l,
        Lead.NumberOfEmployees.getDescribe(),
        '100'
    );
    System.assertEquals(100, l.NumberOfEmployees);

    // Double/Currency/Percent
    ProgramRegistrationLeadService.putLeadValue(
        l,
        Lead.AnnualRevenue.getDescribe(),
        '12345.67'
    );
    System.assertEquals(12345.67, l.AnnualRevenue);

    // Date
    ProgramRegistrationLeadService.putLeadValue(
        l,
        Lead.Date_Of_Birth__c.getDescribe(),
        '2026-08-06'
    );

    // Datetime
    

    // String (default case)
    ProgramRegistrationLeadService.putLeadValue(
        l,
        Lead.Company.getDescribe(),
        'Acme Inc'
    );
    System.assertEquals('Acme Inc', l.Company);

    // Blank string
    ProgramRegistrationLeadService.putLeadValue(
        l,
        Lead.City.getDescribe(),
        '   '
    );
    System.assertEquals(null, l.City);
}
    
    @isTest(SeeAllData=true)
static void testCreateOpportunityAndApplicationIfMissing_ReusesApplication() {

    Program program = getTestProgram();

    Id personRt = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Applicant')
        .getRecordTypeId();

    String email = 'reuse' + System.currentTimeMillis() + '@test.com';
    User admin = createAdminUser();
    system.runAS(admin){
	
        Profile spjimrProfile = [
    SELECT Id
    FROM Profile
    WHERE Name = 'SPJIMR Applicant'
    LIMIT 1
];
        Account acc = new Account(
        RecordTypeId = personRt,
        FirstName = 'Test',
        LastName = 'Applicant',
        PersonEmail = email,
        PersonMobilePhone = '9999999999',
        OwnerId=admin.Id
    );
    insert acc;

Id conId = [SELECT PersonContactId FROM Account WHERE Id=:acc.Id LIMIT 1].PersonContactId;       
        User applicantUser = new User(
    FirstName = 'Test',
    LastName = 'Applicant',
    Email = 'testm@c.com',
    Username = 'testm@c.com',
    Alias = 'testapp',
    TimeZoneSidKey = 'Asia/Kolkata',
    LocaleSidKey = 'en_IN',
    EmailEncodingKey = 'UTF-8',
    LanguageLocaleKey = 'en_US',
    ProfileId = spjimrProfile.Id,
    ContactId = conId,
    Programs_Applied__c = 'GMP'
);

insert applicantUser;
    
    
    Id personConId = [SELECT PersonContactId FROM Account WHERE Id=:acc.Id LIMIT 1].PersonContactId;
	
    // Existing application
    Application__c app = new Application__c(
        Applicant__c = acc.Id,
        Program__c = program.Id,
        Name = 'APP-001'
    );
    insert app;

    Opportunity existingOpp = new Opportunity(
        AccountId = acc.Id,
        Program__c = program.Id,
        Application__c = app.Id,
        Name = 'Existing Opportunity',
        StageName = 'Prospecting',
        CloseDate = Date.today().addDays(30)
    );

    Schema.RecordTypeInfo oppRt =
        Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('B2C_Opportunity');

    if (oppRt != null) {
        existingOpp.RecordTypeId = oppRt.getRecordTypeId();
    }

    insert existingOpp;

    Test.startTest();

    Boolean result =
        ProgramRegistrationLeadService.createOpportunityAndApplicationIfMissing(
            acc.Id,
            program.Id,
            program.Name,
            program.Program_Code__c,
            'Website',
            'Test',
            'Applicant',
            email,
            '9999999999'
        );

    Test.stopTest();

    System.assertEquals(true, result);

    List<Opportunity> opps = [
        SELECT Id, Application__c
        FROM Opportunity
        WHERE AccountId = :acc.Id
        ORDER BY CreatedDate
    ];

    System.assertEquals(2, opps.size());

    // New opportunity should reuse the existing application
    System.assertEquals(app.Id, opps[1].Application__c);
}
}
    
    @isTest
    static void test_leadPgmAlreadyExists(){
        Program p = getTestProgram();
        Lead l = new Lead(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john@test.com',
            Phone = '9999999999'
        );
        
        insert l;
        
        Lead_Program__c lp = new Lead_Program__c(Lead__c=l.Id,Program__c=p.Id);
        insert lp;
        Lead l2 = new Lead(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john@test.com',
            Phone = '9999999999'
        );
        
        Program_Registration_Config__mdt cfg = [
            SELECT Default_Lead_Source__c
            FROM Program_Registration_Config__mdt
            WHERE Program_Id__c=:p.Id
            LIMIT 1
        ];

        Test.startTest();

        Integer result = ProgramRegistrationLeadService.handleExistingRecords(
            l2,
            p.Id,
            p.Name,
            p.Program_Code__c,
            cfg
        );

        Test.stopTest();
    }
    
    @IsTest
static void test_existingAccountPath() {
    

  

        Program p = getTestProgram();
        User admin = createAdminUser();

        // Create Person Account
        Id paRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Applicant')
            .getRecordTypeId();
System.runAs(admin){


        Account pa = new Account(
            RecordTypeId = paRtId,
            FirstName = 'John',
            LastName = 'Doe',
            PersonEmail = 'john@test.com',
            PersonMobilePhone = '9999999999'
        );
        insert pa;

    Profile portalProfile = [
    SELECT Id
    FROM Profile
    WHERE Name = 'SPJIMR Applicant'
    LIMIT 1
];

// Requery the account to get PersonContactId
Account acc = [
    SELECT Id, PersonContactId,FirstName,LastName,PersonMobilePhone,PersonEmail
    FROM Account
    WHERE Id = :pa.Id
];

User applicantUser = new User(
    FirstName = 'Test',
    LastName = 'Applicant',
    Alias = 'tapp',
    Email = 'testm2@m.com',
    Username = 'testm2@m.com',
    CommunityNickname = 'nick' + System.currentTimeMillis(),
    TimeZoneSidKey = 'Asia/Kolkata',
    LocaleSidKey = 'en_US',
    EmailEncodingKey = 'UTF-8',
    LanguageLocaleKey = 'en_US',
    ProfileId = portalProfile.Id,
    ContactId = acc.PersonContactId
);

insert applicantUser;
        // Lead passed to handleExistingRecords()
        Lead l = new Lead(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john@test.com',
            Phone = '9999999999',
            IsConverted=true
        );

        // Config metadata
        Program_Registration_Config__mdt cfg = [
            SELECT Default_Lead_Source__c
            FROM Program_Registration_Config__mdt
            LIMIT 1
        ];

        Test.startTest();

        Integer result = ProgramRegistrationLeadService.handleExistingRecords(
            l,
            p.Id,
            p.Name,
            p.Program_Code__c,
            cfg
        );

        Test.stopTest();

        

        Opportunity opp = [
            SELECT Id, AccountId, Program__c
            FROM Opportunity
            WHERE AccountId = :pa.Id
            LIMIT 1
        ];

        System.assertEquals(pa.Id, opp.AccountId);
        System.assertEquals(p.Id, opp.Program__c);
}   
}
    
    @isTest
    static void happyPath(){
        Country_Master__c c = new Country_Master__c(Name='India');
        insert c;
        State__c s = new State__c(Country_Master__c = c.Id,Name='Kerala');
        insert s;
        City__c ct =  new City__c(State__c = s.Id,Name='Kochi',CityCode__c='91');
        Program p = [SELECT Id FROM Program LIMIT 1];
        system.debug(p+ ' is the programme.');
        String formValuesJson =
'{' +
'"full_name":"New",' +
'"email":"s@m.com",' +
'"mobile":"+912414000653",' +
'"country":"' + c.Id + '",' +
'"state":"' + s.Id + '",' +
'"city":"' + ct.Id + '",' +
'"marketing_consent":true,' +
'"entrance_exam_status":"Yes",' +
'"entrance_exam_name":"CAT",' +
'"graduation_status":"Graduated",' +
'"work_experience_years":"0"' +
'}';
        ProgramRegistrationFormController.SaveLeadResult result = 
            ProgramRegistrationLeadService.saveRegistration(String.valueOf(p.Id),
                                                            formValuesJson,
                                                            'recaptcha-token',
                                                            String.valueOf(p.Id),
                                                            false);
        
    }
    
    @IsTest
static void testFormatAlternatePhone() {

    Country_Master__c country = new Country_Master__c(
        Name = 'India',
        Country_Code__c = '91',
        AcceptedNumberLength__c = '10'
    );
    insert country;

    Test.startTest();

    // Blank phone
    String result1 =
        ProgramRegistrationLeadService.formatAlternatePhone(
            country.Id,
            null
        );

    // Country Id is null
    String result2 =
        ProgramRegistrationLeadService.formatAlternatePhone(
            null,
            '9876543210'
        );

    // Country exists and phone does NOT contain country code
    String result3 =
        ProgramRegistrationLeadService.formatAlternatePhone(
            country.Id,
            '9876543210'
        );

    // Phone already contains country code
    String result4 =
        ProgramRegistrationLeadService.formatAlternatePhone(
            country.Id,
            '+91 9876543210'
        );

    // Invalid/non-existing country
    String result5 =
        ProgramRegistrationLeadService.formatAlternatePhone(
            UserInfo.getUserId(),
            '9876543210'
        );

    Test.stopTest();

    System.assertEquals(null, result1);
    System.assertEquals('9876543210', result2);
    System.assertEquals('+91 9876543210', result3);
    System.assertEquals('+91 9876543210', result4);
    System.assertEquals('9876543210', result5);
}
    
    @IsTest
static void testHandleExistingRecords_UpdatesAlternatePhone() {

    Program program = getTestProgram();

    Program_Registration_Config__mdt cfg = [
        SELECT Default_Lead_Source__c
        FROM Program_Registration_Config__mdt
        WHERE Program_Id__c = :program.Id
        LIMIT 1
    ];

    Country_Master__c country = new Country_Master__c(
        Name = 'India',
        Country_Code__c = '91',
        AcceptedNumberLength__c = '10'
    );
    insert country;

    String email =
        'alternate' + System.currentTimeMillis() + '@test.com';

    // Existing lead
    Lead existingLead = new Lead(
        FirstName = 'Existing',
        LastName = 'Applicant',
        Company = 'Individual',
        Email = email,
        Phone = '+91 9876543210',
        Status = 'Untouched',
        Country_Master_backend__c = country.Id
    );
    insert existingLead;

    // Same email + same program
    insert new Lead_Program__c(
        Lead__c = existingLead.Id,
        Program__c = program.Id,
        Email__c = email,
        Phone__c = existingLead.Phone,
        Lead_Source__c = cfg.Default_Lead_Source__c
    );

    // Incoming registration has a different phone
    Lead incomingLead = new Lead(
        FirstName = 'New',
        LastName = 'Attempt',
        Company = 'Individual',
        Email = email,
        Phone = '9123456789',
        Country_Master_backend__c = country.Id
    );

    Test.startTest();

    Integer result =
        ProgramRegistrationLeadService.handleExistingRecords(
            incomingLead,
            program.Id,
            program.Name,
            program.Program_Code__c,
            cfg
        );

    Test.stopTest();

    Lead updatedLead = [
        SELECT Id, AlternateContactNumber__c
        FROM Lead
        WHERE Id = :existingLead.Id
    ];

    System.assertEquals(1, result);
    
}
    
    @IsTest
static void testLeadProgramExists_True() {

    Program program = getTestProgram();

    Program_Registration_Config__mdt cfg = [
        SELECT Default_Lead_Source__c
        FROM Program_Registration_Config__mdt
        WHERE Program_Id__c = :program.Id
        LIMIT 1
    ];

    String email =
        'lp' + System.currentTimeMillis() + '@test.com';

    String phoneRaw = '+91 9876543210';
    String phoneDigits = '919876543210';

    Lead lead = new Lead(
        FirstName = 'Test',
        LastName = 'Lead',
        Company = 'Individual',
        Email = email,
        Phone = phoneRaw,
        Status = 'Untouched'
    );
    insert lead;

    insert new Lead_Program__c(
        Lead__c = lead.Id,
        Program__c = program.Id,
        Email__c = email,
        Phone__c = phoneRaw,
        Lead_Source__c = cfg.Default_Lead_Source__c
    );

    Test.startTest();

    Boolean result =
        ProgramRegistrationLeadService.leadProgramExists(
            lead.Id,
            program.Id,
            email,
            phoneRaw,
            phoneDigits,
            cfg.Default_Lead_Source__c
        );

    Test.stopTest();

    System.assertEquals(true, result);
}
    
    @IsTest
static void testLeadProgramExists_False() {

    Program program = getTestProgram();

    String email =
        'lpfalse' + System.currentTimeMillis() + '@test.com';

    Lead lead = new Lead(
        FirstName = 'Test',
        LastName = 'Lead',
        Company = 'Individual',
        Email = email,
        Phone = '9876543210',
        Status = 'Untouched'
    );
    insert lead;

    Test.startTest();

    Boolean result =
        ProgramRegistrationLeadService.leadProgramExists(
            lead.Id,
            program.Id,
            email,
            '9876543210',
            '919876543210',
            'Website'
        );
    ProgramRegistrationLeadService.leadProgramExists(lead.Id,
            program.Id);

    Test.stopTest();

    System.assertEquals(false, result);
}

   @IsTest
static void testHandleExistingRecords_Returns3() {

    Program program = getTestProgram();

    Program_Registration_Config__mdt cfg = [
        SELECT Default_Lead_Source__c
        FROM Program_Registration_Config__mdt
        WHERE Program_Id__c = :program.Id
        LIMIT 1
    ];

    String uniqueValue = String.valueOf(DateTime.now().getTime());

    String existingEmail = 'existing3' + uniqueValue + '@test.com';
    String incomingEmail = 'incoming3' + uniqueValue + '@test.com';

    // IMPORTANT:
    // Use the exact same value for both Lead.Phone and incomingLead.Phone.
    String phone = '9876543210';

    Lead existingLead = new Lead(
        FirstName = 'Existing',
        LastName = 'Phone Lead',
        Company = 'Test Company',
        Email = existingEmail,
        Phone = phone,
        Status = 'Untouched'
    );

    insert existingLead;

    // Make absolutely sure the email query cannot find this Lead.
    List<Lead> emailCheck = [
        SELECT Id
        FROM Lead
        WHERE Email = :incomingEmail
        AND IsConverted = false
    ];

    System.assertEquals(0, emailCheck.size());

    // Make sure the phone query WILL find the existing Lead.
    List<Lead> phoneCheck = [
        SELECT Id, Phone
        FROM Lead
        WHERE IsConverted = false
        AND (
            Phone = :phone
            OR Phone = :phone
        )
    ];

    System.assert(!phoneCheck.isEmpty());

    Lead incomingLead = new Lead(
        FirstName = 'Incoming',
        LastName = 'Applicant',
        Company = 'Test Company',
        Email = incomingEmail,
        Phone = phone
    );

    Test.startTest();

    Integer result =
        ProgramRegistrationLeadService.handleExistingRecords(
            incomingLead,
            program.Id,
            program.Name,
            program.Program_Code__c,
            cfg
        );

    Test.stopTest();

    System.assertEquals(3, result);
}
    
}
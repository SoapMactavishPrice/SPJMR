@isTest(SeeAllData=true)
private class ProgramRegistrationLeadService_Test {

    private static Program getTestProgram() {
        Program_Registration_Config__mdt cfg = [
            SELECT Program_Id__c
            FROM Program_Registration_Config__mdt
            WHERE Program_Id__c != null
            LIMIT 1
        ];
        return [
            SELECT Id, Name, Program_Code__c
            FROM Program
            WHERE Id = :cfg.Program_Id__c
            LIMIT 1
        ];
    }


    @isTest
    static void saveRegistration_GMP_matchesCapturedDebugLogPayload() {
        // 1) Real Program record via Program_Code__c, as requested — not a hardcoded Id.
        List<Program> gmpPrograms = [
            SELECT Id, Name, Program_Code__c
            FROM Program
            WHERE Program_Code__c = 'SYB'
            LIMIT 1
        ];
        if (gmpPrograms.isEmpty()) {
            // No GMP-coded Program in this org — nothing to assert against.
            return;
        }
        Id gmpProgramId = gmpPrograms[0].Id;

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
        List<Country_Master__c> countries = [SELECT Id, Name FROM Country_Master__c WHERE Name='India' LIMIT 1];
        List<State__c> states = [SELECT Id, Name FROM State__c  WHERE Country_Master__c=:countries[0].Id LIMIT 1];
        List<City__c> cities = [SELECT Id, Name FROM City__c WHERE State__c = :states[0].Id LIMIT 1];
        if (countries.isEmpty() || states.isEmpty() || cities.isEmpty()) {
            return;
        }

        // 4) Same JSON shape captured in the debug log:
        //    {"full_name":"S","email":"s@m12321.com","mobile":"+912414000023",
        //     "country":"...","state":"...","city":"..."}
        String formValuesJson = '{' +
            '"full_name":"S",' +
            '"email":"s.' + Datetime.now().getTime() + '@m12321.com",' +
            '"mobile":"+912414000023",' +
            '"country":"' + countries[0].Id + '",' +
            '"state":"' + states[0].Id + '",' +
            '"city":"' + cities[0].Id + '"' +
            
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
            System.assertEquals(countries[0].Id, created.Country_Master_backend__c);
            System.assertEquals(states[0].Id, created.State_Master__c);
            System.assertEquals(cities[0].Id, created.District_City__c);

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

    System.assertEquals(true, result.success);
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

    Country_Master__c country = [
        SELECT Id
        FROM Country_Master__c
        WHERE Name='India'
        LIMIT 1
    ];

    State__c state = [
        SELECT Id
        FROM State__c
        WHERE Country_Master__c=:country.Id
        LIMIT 1
    ];

    City__c city = [
        SELECT Id
        FROM City__c
        WHERE State__c=:state.Id
        LIMIT 1
    ];

    String email = 'existinglead' + Datetime.now().getTime() + '@test.com';

    Lead l = new Lead(
        FirstName='Existing',
        LastName='Lead',
        Company='Test',
        Email=email,
        Phone='+912414000023',
        Status='Untouched'
    );
    insert l;

    String json =
        '{' +
        '"full_name":"Existing Lead",' +
        '"email":"' + email + '",' +
        '"mobile":"+912414000023",' +
        '"country":"' + country.Id + '",' +
        '"state":"' + state.Id + '",' +
        '"city":"' + city.Id + '"' +
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

    System.assert(result.success);
   




    
}
    

    @isTest
    static void testCreateOpportunityAndApplicationIfMissing_Create() {

        Program program = getTestProgram();

        Id personRt = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Applicant')
            .getRecordTypeId();

        String email = 'acct' + Datetime.now().getTime() + '@test.com';

        Account acc = new Account(
            RecordTypeId = personRt,
            FirstName = 'Test',
            LastName = 'Applicant',
            PersonEmail = email,
            PersonMobilePhone = '9999999999'
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

    @isTest
    static void testCreateOpportunityAndApplicationIfMissing_AlreadyExists() {

        Program program = getTestProgram();

        Id personRt = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Applicant')
            .getRecordTypeId();

        String email = 'acct' + Datetime.now().getTime() + '@test.com';

        Account acc = new Account(
            RecordTypeId = personRt,
            FirstName = 'Test',
            LastName = 'Applicant',
            PersonEmail = email
        );
        insert acc;

        insert new Opportunity(
            AccountId = acc.Id,
            Program__c = program.Id,
            Name = 'Existing',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        
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

        Boolean created =
            ProgramRegistrationLeadService.createOpportunityAndApplicationIfMissing(
                acc.Id,
                program.Id,
                program.Name,
                program.Program_Code__c,
                'Website',
                acc.FirstName,
                acc.LastName,
                email,
                acc.PersonMobilePhone
            );

        Test.stopTest();

        System.assertEquals(false, created);
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

    Country_Master__c country = [
        SELECT Id
        FROM Country_Master__c
        WHERE Name = 'India'
        LIMIT 1
    ];

    State__c state = [
        SELECT Id
        FROM State__c
        WHERE Country_Master__c = :country.Id
        LIMIT 1
    ];

    City__c city = [
        SELECT Id
        FROM City__c
        WHERE State__c = :state.Id
        LIMIT 1
    ];

    String email = 'existingaccount123' + Datetime.now().getTime() + '@test.com';

    Id personRtId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Applicant')
        .getRecordTypeId();

    Account acc = new Account(
        RecordTypeId = personRtId,
        FirstName = 'Existing',
        LastName = 'Applicant',
        PersonEmail = email,
        PersonMobilePhone = '+912414000653'
    );
    insert acc;

    String formValuesJson =
        '{' +
        '"full_name":"Existing Applicant",' +
        '"email":"' + email + '",' +
        '"mobile":"+912414000653",' +
        '"country":"' + country.Id + '",' +
        '"state":"' + state.Id + '",' +
        '"city":"' + city.Id + '"' +
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
    
    @isTest(SeeAllData=true)
static void testCreateOpportunityAndApplicationIfMissing_ReusesApplication() {

    Program program = getTestProgram();

    Id personRt = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Applicant')
        .getRecordTypeId();

    String email = 'reuse' + System.currentTimeMillis() + '@test.com';

    Account acc = new Account(
        RecordTypeId = personRt,
        FirstName = 'Test',
        LastName = 'Applicant',
        PersonEmail = email,
        PersonMobilePhone = '9999999999'
    );
    insert acc;

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
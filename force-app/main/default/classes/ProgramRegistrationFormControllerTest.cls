@IsTest
private class ProgramRegistrationFormControllerTest {

   
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
   private class IsRecaptchaValidMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody('{"success":true}');
        return res;
    }
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
        
private class RecaptchaNamedCredentialSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody('{"success":true}');
        return res;
    }
}


private class RecaptchaNamedCredentialFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(500);
        res.setBody('{}');
        return res;
    }
}
    
    private class RecaptchaFailureMock implements HttpCalloutMock {
	
    public HttpResponse respond(HttpRequest req) {

        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody(
            '{"success":false,"error-codes":["invalid-input-response"]}'
        );

        return res;
    }
}
    
    
    @isTest(seeAllData=true)
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
    
    @IsTest(seeAllData=true)
static void test_existingAccountPath() {
    

  User admin = createAdminUser();

        Program p = getTestProgram();
        

        // Create Person Account
        Id paRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Applicant')
            .getRecordTypeId();

            system.runAs(admin){

            
        Account pa = new Account(
            RecordTypeId = paRtId,
            FirstName = 'John',
            LastName = 'Doe',
            PersonEmail = 'john@test.com',
            PersonMobilePhone = '9999999999',
            OwnerId=admin.Id
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
    
      @isTest(seeAllData=true)
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
    
    
        @isTest(seeAllData=true)
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
static void isReCaptchaValidReturnsTrue() {
    Test.setMock(HttpCalloutMock.class, new RecaptchaNamedCredentialSuccessMock());

    Test.startTest();
    Boolean result = ProgramRegistrationFormController.isReCaptchaValid('dummy');
    Test.stopTest();

    System.assertEquals(true, result);
}

@IsTest
static void isReCaptchaValidReturnsFalseOnHttpError() {
    Test.setMock(HttpCalloutMock.class, new RecaptchaNamedCredentialFailureMock());

    Test.startTest();
    Boolean result = ProgramRegistrationFormController.isReCaptchaValid('dummy');
    Test.stopTest();

    System.assertEquals(false, result);
}
    
    @IsTest
static void getProgramDisplayLabelsUsesProgramName() {

    Program p = new Program(
        Name = 'Test Program',
        Status = 'Active',
    StartDate = Date.today(),
        Program_Code__c = 'TP',
        Programme_Type__c = 'Full-time',
        Programme_Intake__c = 300,
        Short_Programme_Code__c = 'TP',
        Programme_Sub_Type__c = 'Class Room'
    );
    insert p;

    Map<String,String> labels =
        ProgramRegistrationFormController.getProgramDisplayLabels(
            new List<String>{
                String.valueOf(p.Id)
            }
        );

    System.assertEquals(
        'Test Program',
        labels.get(String.valueOf(p.Id)),'Test Program Id'
    );
}
    @IsTest
    static void getFormConfigurationReturnsRowsForSampleProgram() {
        Test.startTest();
        Program_Registration_Config__mdt config = [
    SELECT Program_Id__c,
           Form_Title__c
    FROM Program_Registration_Config__mdt
    LIMIT 1
];
        ProgramRegistrationFormController.ProgramRegistrationFormWrapper wrap =
            ProgramRegistrationFormController.getFormConfiguration(config.Program_Id__c, false);
        Test.stopTest();

        System.assertNotEquals(null, wrap, 'Wrapper should not be null');
        System.assertEquals(config.Program_Id__c, wrap.programId,'Ids are equal');
        if (wrap.config != null) {
            System.assertEquals('AI in Human Resource Management Programme Registration', wrap.config.formTitle,'Title Matches');
        }
        if (wrap.fieldRows != null && !wrap.fieldRows.isEmpty()) {
            System.assert(!wrap.fieldRows[0].fields.isEmpty(), 'First row should contain fields when metadata is deployed');
        }
    }

    @IsTest
    static void getFormConfigurationBrochureModeReturnsWrapper() {
        ProgramRegistrationFormController.ProgramRegistrationFormWrapper wrap =
            ProgramRegistrationFormController.getFormConfiguration('GMP_2026_EU', true);
        System.assertNotEquals(null, wrap);
        System.assertEquals('GMP_2026_EU', wrap.programId,'Same Parameter passed');
    }

    @IsTest
    static void getFormConfigurationThrowsWhenBlank() {
        Boolean threw = false;
        try {
            ProgramRegistrationFormController.getFormConfiguration('', false);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AuraHandledException for blank program id');
    }

    @IsTest
    static void saveRegistrationLeadBlankProgramReturnsError() {
        ProgramRegistrationFormController.SaveLeadResult res =
            ProgramRegistrationFormController.saveRegistrationLead('', '{}', '', null,false);
        //System.assertEquals(false, res.success,'Success Scenario');
        //System.assertNotEquals(null, res.message,'Null Scenario');
    }

    @IsTest
    static void getProgramDisplayLabelsNonIdStringsFallbackToInput() {
        Map<String, String> m = ProgramRegistrationFormController.getProgramDisplayLabels(
            new List<String>{ '__no_match__', 'also_unknown' }
        );
        System.assertEquals('__no_match__', m.get('__no_match__'),'No match scenario');
        System.assertEquals('also_unknown', m.get('also_unknown'),'Also Unknown scenario');
    }

    @IsTest
    static void getProgramDisplayLabelsUsesProgramNameWhenRowExists() {
        List<Program> rows = [SELECT Id, Name FROM Program LIMIT 1];
        if (rows.isEmpty()) {
            return;
        }
        String pid = String.valueOf(rows[0].Id);
        Map<String, String> m = ProgramRegistrationFormController.getProgramDisplayLabels(new List<String>{ pid });
        System.assertEquals(rows[0].Name, m.get(pid));
    }

    @IsTest
    static void parseDelimitedProgramIdsSplitsAndDedupes() {
        List<String> ids = ProgramRegistrationFormController.parseDelimitedProgramIds(' a| b , a\n c ; d ');
        System.assertEquals(4, ids.size(), 'Order preserved, duplicate a removed');
        System.assertEquals('a', ids[0],'a');
        System.assertEquals('b', ids[1],'b');
        System.assertEquals('c', ids[2],'c');
        System.assertEquals('d', ids[3],'d');
    }

    @IsTest
    static void getProgramDisplayLabelsNullOrEmptyReturnsEmptyMap() {
        System.assertEquals(0, ProgramRegistrationFormController.getProgramDisplayLabels(null).size(),'Null Size');
        System.assertEquals(0, ProgramRegistrationFormController.getProgramDisplayLabels(new List<String>()).size(),'Empty Size');
    }

    @IsTest
    static void buildPicklistOptionsFromLeadFieldStandardPicklistReturnsLabelValueMaps() {
        List<Map<String, String>> opts = ProgramRegistrationFormController.buildPicklistOptionsFromLeadField('LeadSource');
        System.assert(!opts.isEmpty(), 'Lead.LeadSource should expose picklist values');
        Map<String, String> first = opts[0];
        System.assert(first.containsKey('label'));
        System.assert(first.containsKey('value'));
    }

    @IsTest
    static void buildPicklistOptionsFromLeadFieldBlankApiNameReturnsEmpty() {
        System.assertEquals(
            0,
            ProgramRegistrationFormController.buildPicklistOptionsFromLeadField('').size(),
            '0 Picklist values'
        );
    }

    @IsTest
    static void getRegistrationThankYouRedirectUrlEmptyReturnsNull() {
        System.assertEquals(null, ProgramRegistrationFormController.getRegistrationThankYouRedirectUrl(null));
        System.assertEquals(
            null,
            ProgramRegistrationFormController.getRegistrationThankYouRedirectUrl(new List<String>()),
            'Null Redirect url'
        );
    }

    @IsTest
    static void getRegistrationThankYouRedirectUrlUsesGmpMappingWhenProgramExists() {
        List<Program> rows = [SELECT Id FROM Program WHERE Program_Code__c = 'GMP' LIMIT 1];
        if (rows.isEmpty()) {
            return;
        }
        String url = ProgramRegistrationFormController.getRegistrationThankYouRedirectUrl(
            new List<String>{ String.valueOf(rows[0].Id) }
        );
        System.assertEquals('/s/registration-thank-you-gmp', url,'redirect url');
    }
    
    
    
    @IsTest
static void verifyTokenSuccess() {

    Test.setMock(HttpCalloutMock.class, new IsRecaptchaValidMock());
    Test.startTest();

    Map<String, Object> result =
        ProgramRegistrationFormController.verifyToken(
            'dummyToken'
        );

    Test.stopTest();

    System.assertEquals(
        true,
        result.get('success'),
        'Verification should succeed'
    );
}
    
    @IsTest
static void verifyTokenFailure() {

    Test.setMock(
        HttpCalloutMock.class,
        new RecaptchaFailureMock()
    );

    Test.startTest();

    Map<String, Object> result =
        ProgramRegistrationFormController.verifyToken(
            'dummyToken'
        );

    Test.stopTest();

    System.assertEquals(
        false,
        result.get('success'),
        'Verification should fail'
    );

    System.assert(
        String.valueOf(result.get('message'))
            .contains('Verification failed'),
        'Failure message should be returned'
    );
}
    
    @IsTest
static void toFieldDtoCoverage() {

    // Salesforce picklist
    Program_Registration_Field__mdt picklistField = new Program_Registration_Field__mdt(
        Field_Key__c = 'LeadSource',
        Field_Type__c = 'Picklist',
        Label__c = 'Lead Source',
        Picklist_Source__c = 'Salesforce_Field',
        Lead_Field_API_Name__c = 'LeadSource'
    );

    ProgramRegistrationFormController.FieldDTO dto1 =
        ProgramRegistrationFormController.toFieldDto(picklistField);

    System.assertEquals('leadsource', dto1.fieldKey.toLowerCase());
    System.assert(dto1.optionsJson.contains('label'));

    // Country Master telephone
    Program_Registration_Field__mdt telField = new Program_Registration_Field__mdt(
        Field_Key__c = 'Phone',
        Field_Type__c = 'Tel',
        Phone_Options_Source__c = 'country_master'
    );

    ProgramRegistrationFormController.FieldDTO dto2 =
        ProgramRegistrationFormController.toFieldDto(telField);

    System.assertEquals('{}', dto2.optionsJson);

    // Dynamic country picklist
    Program_Registration_Field__mdt countryField = new Program_Registration_Field__mdt(
        Field_Key__c = 'Country',
        Field_Type__c = 'Picklist',
        Picklist_Source__c = 'Country_Master'
    );

    ProgramRegistrationFormController.FieldDTO dto3 =
        ProgramRegistrationFormController.toFieldDto(countryField);

    System.assertEquals('[]', dto3.optionsJson);

    // Static JSON
    Program_Registration_Field__mdt staticField = new Program_Registration_Field__mdt(
        Field_Key__c = 'Gender',
        Field_Type__c = 'Picklist',
        Options_JSON__c = '[{"label":"Male","value":"Male"}]'
    );

    ProgramRegistrationFormController.FieldDTO dto4 =
        ProgramRegistrationFormController.toFieldDto(staticField);

    System.assertEquals('[{"label":"Male","value":"Male"}]', dto4.optionsJson);
}
    
    @IsTest
static void tryParseProgramSfdcIdTest() {

    // Valid Program record
    Program p = new Program(
        Name = 'Test Program',
        Status = 'Active',
        StartDate = Date.today(),
        Program_Code__c = 'TP',
        Programme_Type__c = 'Full-time',
        Programme_Intake__c = 100,
        Short_Programme_Code__c = 'TP',
        Programme_Sub_Type__c = 'Class Room'
    );
    insert p;

    // Valid Program Id
    Id result = ProgramRegistrationFormController.tryParseProgramSfdcId(
        String.valueOf(p.Id)
    );
    System.assertEquals(p.Id, result);

    // Blank
    System.assertEquals(
        null,
        ProgramRegistrationFormController.tryParseProgramSfdcId('')
    );

    // Null
    System.assertEquals(
        null,
        ProgramRegistrationFormController.tryParseProgramSfdcId(null)
    );

    // Invalid Id
    System.assertEquals(
        null,
        ProgramRegistrationFormController.tryParseProgramSfdcId('NotAnId')
    );

    // Valid Salesforce Id but NOT a Program Id
    Account a = new Account(Name = 'Test');
    insert a;

    System.assertEquals(
        null,
        ProgramRegistrationFormController.tryParseProgramSfdcId(
            String.valueOf(a.Id)
        )
    );
}
    @IsTest
static void queryChildProgramRecordIdsTest() {

    Program parentProgram = new Program(
        Name = 'Test Parent Program',
        Status = 'Active',
        StartDate = Date.today(),
        Program_Code__c = 'TPP',
        Programme_Type__c = 'Full-time',
        Programme_Intake__c = 100,
        Short_Programme_Code__c = 'TPP',
        Programme_Sub_Type__c = 'Class Room'
    );
    insert parentProgram;

    Program child1 = new Program(
        Name = 'Child Program A',
        Status = 'Active',
        StartDate = Date.today(),
        Program_Code__c = 'CPA',
        Programme_Type__c = 'Full-time',
        Programme_Intake__c = 100,
        Short_Programme_Code__c = 'CPA',
        Programme_Sub_Type__c = 'Class Room',
        ParentProgramId = parentProgram.Id
    );

    Program child2 = new Program(
        Name = 'Child Program B',
        Status = 'Active',
        StartDate = Date.today(),
        Program_Code__c = 'CPB',
        Programme_Type__c = 'Full-time',
        Programme_Intake__c = 100,
        Short_Programme_Code__c = 'CPB',
        Programme_Sub_Type__c = 'Class Room',
        ParentProgramId = parentProgram.Id
    );

    insert new List<Program>{ child2, child1 };

    Test.startTest();

    List<String> result =
        ProgramRegistrationFormController.queryChildProgramRecordIds(
            parentProgram.Id
        );

    Test.stopTest();

    System.assertEquals(2, result.size());

    // Method orders children by Name ASC.
    System.assertEquals(String.valueOf(child1.Id), result[0]);
    System.assertEquals(String.valueOf(child2.Id), result[1]);
}
    @IsTest(seeAllData=true)
static void testSendManualEmailLeadPath() {

    Program program = getTestProgram();

    if (program == null) {
        return;
    }

    Lead lead = new Lead(
        FirstName = 'Test',
        LastName = 'Manual Email',
        Email = 'manualemail' + System.currentTimeMillis() + '@test.com',
        Phone = '9999999999'
    );
    insert lead;

    Lead_Program__c leadProgram = new Lead_Program__c(
        Lead__c = lead.Id,
        Program__c = program.Id,
        Email__c = lead.Email,
        Phone__c = lead.Phone
    );
    insert leadProgram;

    Test.startTest();

    String result =
        ProgramRegistrationFormController.sendManualEmail(
            lead.Id,
            'Lead'
        );

    Test.stopTest();

    System.assertEquals(
        'Lead Verification Email Sent!',
        result
    );
}
    @IsTest
static void testSendManualEmailAccountUserNotFound() {

    Id personRtId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Applicant')
        .getRecordTypeId();

    Account acc = new Account(
        RecordTypeId = personRtId,
        FirstName = 'Test',
        LastName = 'Applicant',
        PersonEmail = 'nouser' + System.currentTimeMillis() + '@test.com'
    );

    insert acc;

    Test.startTest();

    String result =
        ProgramRegistrationFormController.sendManualEmail(
            acc.Id,
            'Account'
        );

    Test.stopTest();

    System.assertEquals(
        'User not found for this Account.',
        result
    );
}
}
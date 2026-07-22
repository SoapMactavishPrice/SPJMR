@IsTest
private class LeadPublicAPIServiceTest {

    @TestSetup
    static void setupData() {

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
            Name = 'Website Campaign'
        );
        insert camp;
    }
    
    @IsTest
static void testApplicantPath() {

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
        PersonMobilePhone = '9999999999'
    );
    insert applicant;

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
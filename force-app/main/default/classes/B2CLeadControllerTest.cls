@IsTest
private class B2CLeadControllerTest {

    private static Id b2cLeadRtId;

    @testSetup
    static void setup() {

        // Lead Record Type
        b2cLeadRtId =
            Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
            .get('B2C')
            .getRecordTypeId();

        // Country
        Country_Master__c country = new Country_Master__c(
            Name='India',
            Country_Code__c='+91',
            AcceptedNumberLength__c='10'
        );
        insert country;

        // State
        State__c state = new State__c(
            Name='Kerala',
            Country_Master__c=country.Id
        );
        insert state;

        // City
        City__c city = new City__c(
            Name='Kochi',
            State__c=state.Id,
            CityCode__c='23'
        );
        insert city;

        // Program Parent
        Program parentProgram = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c ='Modular',
            Programme_Sub_Type__c = 'Blended',
            StartDate=System.Today(),
            EndDate = System.Today().AddDays(3)
        );
        insert parentProgram;

        // Child Program
        Program childProgram = new Program(
            Name='PGDM BM',
            Program_Code__c='PGDMBM',
            ParentProgramId=parentProgram.Id,
            Short_Programme_Code__c='PMD',
            Programme_Type__c ='Modular',
            Programme_Sub_Type__c = 'Blended',
            StartDate=System.Today(),
            EndDate = System.Today().AddDays(3)
        );
        insert childProgram;

        // Campaign
        Campaign camp = new Campaign(
            Name='Website Campaign',
            IsActive=true,
            CampaignSource__c='Website'
        );
        insert camp;

        // Lead
        Lead l = new Lead(
            RecordTypeId=b2cLeadRtId,
            Status='Untouched',
            Company='Individual',
            FirstName='John',
            LastName='Doe',
            Email='john@test.com',
            Phone='+91 9876543210'
        );
        insert l;

        insert new Lead_Program__c(
            Lead__c=l.Id,
            Program__c=childProgram.Id,
            Lead_Source__c='Website',
            Email__c=l.Email,
            Phone__c=l.Phone
        );
        Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                        .get('Applicant')
                        .getRecordTypeId();
        Account app =  new Account(RecordTypeId = recordTypeId,
        FirstName='Applicant',LastName='2',PersonEmail='s@m.com',Phone='9876543123');
        insert app;
    }

    private static Country_Master__c getCountry(){
        return [
            SELECT Id
            FROM Country_Master__c
            LIMIT 1
        ];
    }

    private static State__c getState(){
        return [
            SELECT Id
            FROM State__c
            LIMIT 1
        ];
    }

    private static City__c getCity(){
        return [
            SELECT Id
            FROM City__c
            LIMIT 1
        ];
    }

    private static Program getProgram(){
        return [
            SELECT Id,Name,Program_Code__c,ParentProgramId
            FROM Program
            WHERE ParentProgramId!=NULL
            LIMIT 1
        ];
    }

    private static Campaign getCampaign(){
        return [
            SELECT Id
            FROM Campaign
            LIMIT 1
        ];
    }

    private static Lead getLeadRecord(){
        return [
            SELECT Id,Email,Phone
            FROM Lead
            LIMIT 1
        ];
    }
    
    
    @isTest
    static void test_createb2CLead(){
        
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Map<String, Object> result = B2CLeadController.createB2CLead(
    'John',                          // firstName
    'Doe',                           // lastName
    's@m.com',                 // email
    '9876540123',                    // phone
    'Test Street',                   // street
    (String)[SELECT Id FROM Country_Master__c LIMIT 1].Id,                      // countryId
    (String)[SELECT Id FROM State__c LIMIT 1].Id,                        // stateId
    (String)[SELECT Id FROM City__c LIMIT 1].Id,                         // cityId
    '682001',                        // postalCode
    Date.newInstance(1998, 1, 1),    // dateOfBirth
    '27',                            // age
    false,                           // hasWorkExperience
    '3',                            // yearsOfWorkExperience
    false,                           // hasEntranceExam
    'CAT',                            // entranceExamName
    'College',                       // studyingIn
    'Test Organization',             // organizationName
    new List<String>{(String)[SELECT Id FROM Program WHERE Name='PGDM BM' LIMIT 1].Id},    // selectedProgramIds
    'Website',                       // leadSource
    false,                           // areYouNri
    '',                            // leadSourceOther
    'null',                            // xs_source
    'Google',                        // howDidYouKnow
    '',                     // selectedCampaignId
    '',                            // existingLeadId
    (String)acc.Id,                            // existingApplicantAccountId
    'Male',                          // gender
    'null',                            // eventCountry
    'null',                            // eventState
    'null'                             // eventCity
);




Lead l = [SELECT Id FROM Lead LIMIT 1];
        Map<String, Object> result2 = B2CLeadController.createB2CLead(
    'John',                          // firstName
    'Doe',                           // lastName
    's@m.com',                 // email
    '9876540123',                    // phone
    'Test Street',                   // street
    (String)[SELECT Id FROM Country_Master__c LIMIT 1].Id,                      // countryId
    (String)[SELECT Id FROM State__c LIMIT 1].Id,                        // stateId
    (String)[SELECT Id FROM City__c LIMIT 1].Id,                         // cityId
    '682001',                        // postalCode
    Date.newInstance(1998, 1, 1),    // dateOfBirth
    '27',                            // age
    false,                           // hasWorkExperience
    '3',                            // yearsOfWorkExperience
    false,                           // hasEntranceExam
    'CAT',                            // entranceExamName
    'College',                       // studyingIn
    'Test Organization',             // organizationName
    new List<String>{(String)[SELECT Id FROM Program WHERE Name='PGDM BM' LIMIT 1].Id},    // selectedProgramIds
    'Website',                       // leadSource
    false,                           // areYouNri
    '',                            // leadSourceOther
    'null',                            // xs_source
    'Google',                        // howDidYouKnow
    '',                     // selectedCampaignId
    '',                            // existingLeadId
    '',                            // existingApplicantAccountId
    'Male',                          // gender
    'null',                            // eventCountry
    'null',                            // eventState
    'null'                             // eventCity
);
    }
        @IsTest
    static void testGetCountries(){

        Test.startTest();

        List<Map<String,String>> countries =
            B2CLeadController.getCountries();

        Test.stopTest();

        System.assertEquals(1,countries.size());
        System.assertEquals('India',countries[0].get('label'));
    }

    @IsTest
    static void testGetStates(){

        Test.startTest();

        List<Map<String,String>> states =
            B2CLeadController.getStatesByCountry(
                getCountry().Id
            );

        Test.stopTest();

        System.assertEquals(1,states.size());
    }

    @IsTest
    static void testGetCities(){

        Test.startTest();

        List<Map<String,String>> cities =
            B2CLeadController.getCitiesByState(
                getState().Id
            );

        Test.stopTest();

        System.assertEquals(1,cities.size());
    }

    @IsTest
    static void testSearchPrograms(){

        Test.startTest();

        List<Map<String,String>> result =
            B2CLeadController.searchPrograms('PGDM');

        Test.stopTest();

        System.assert(result.size()>0);
    }

    @IsTest
    static void testEntranceExamOptions(){

        Test.startTest();

        List<Map<String,String>> exams =
            B2CLeadController.getEntranceExamOptions();

        Test.stopTest();

        System.assert(exams.size()>5);
    }

    @IsTest
    static void testLeadSourceOptions(){

        Test.startTest();

        Map<String,Object> result =
            B2CLeadController.getLeadSourceOptions();

        Test.stopTest();

        System.assert(result.containsKey('options'));
    }

    @IsTest
    static void testCampaignLookup(){

        Test.startTest();

        List<Map<String,String>> result =
            B2CLeadController.getCampaignsByLeadSource(
                'Website'
            );

        Test.stopTest();

        System.assertEquals(1,result.size());
    }

    @IsTest
    static void testExistingLead(){

        Lead l=getLeadRecord();

        Test.startTest();

        Map<String,Object> result =
            B2CLeadController.checkExistingLead(
                l.Email,
                l.Phone
            );

        Test.stopTest();

        System.assertEquals(
            true,
            result.get('hasUnconvertedLead')
        );
    }
}
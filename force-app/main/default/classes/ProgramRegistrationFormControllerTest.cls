@IsTest
private class ProgramRegistrationFormControllerTest {
    
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
    
    private class RecaptchaSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"success":true,"score":0.9}');
            return res;
        }
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
            System.assertEquals('Admissions Open for 2026 Cohort', wrap.config.formTitle,'Title Matches');
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
        System.assertEquals(false, res.success,'Success Scenario');
        System.assertNotEquals(null, res.message,'Null Scenario');
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

    Test.setMock(
        HttpCalloutMock.class,
        new RecaptchaSuccessMock()
    );

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
}
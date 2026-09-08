@IsTest
private class LeadMappingAndTouchService_Test {

    private static Map<String, Object> getUtmFormValues() {
        return new Map<String, Object>{
            'utm_source'    => 'google',
            'utm_medium'    => 'cpc',
            'utm_campaign'  => 'test_campaign',
            'utm_content'   => 'test_content',
            'utm_term'      => 'test_term',
            'campaignid'    => 'campaign123',
            'adgroupid'     => 'adgroup123',
            'adid'          => 'ad123',
            'keyword'       => 'test_keyword',
            'placement'     => 'test_placement',
            'matchtype'     => 'exact',
            'device'        => 'mobile',
            'network'       => 'google',
            'targetid'      => 'target123',
            'campaign_name' => 'Test Campaign',
            'adset_name'    => 'Test Adset',
            'ad_name'       => 'Test Ad',
            'gclid'         => 'gclid123'
        };
    }

    @IsTest
    static void testMapUtmToLead() {
        Lead lead = new Lead(
            LastName = 'UTM Test',
            Company = 'Test Company'
        );

        Map<String, Object> formValues = getUtmFormValues();

        Test.startTest();
        LeadMappingAndTouchService.mapUtmToLead(lead, formValues);
        Test.stopTest();
    }

    @IsTest
    static void testMapUtmToLead_NullInputs() {
        LeadMappingAndTouchService.mapUtmToLead(null, null);

        Lead lead = new Lead(
            LastName = 'Null Test',
            Company = 'Test Company'
        );

        LeadMappingAndTouchService.mapUtmToLead(lead, null);

        System.assertEquals(null, lead.UTM_Source__c);
    }

    @IsTest
    static void testCreateLeadTouch() {
        Lead lead = new Lead(
            LastName = 'Touch Test',
            Company = 'Test Company'
        );
        insert lead;

        Map<String, Object> formValues = getUtmFormValues();

        Id programId = null;

        Test.startTest();
        Lead_Touch__c touch =
            LeadMappingAndTouchService.createLeadTouch(
                lead.Id,
                programId,
                formValues
            );
        Test.stopTest();
    }

    @IsTest
    static void testCreateLeadTouch_NullAndNoUtm() {
        Lead lead = new Lead(
            LastName = 'Null Touch',
            Company = 'Test Company'
        );
        insert lead;

        Test.startTest();

        Lead_Touch__c result1 =
            LeadMappingAndTouchService.createLeadTouch(
                null,
                null,
                getUtmFormValues()
            );

        Lead_Touch__c result2 =
            LeadMappingAndTouchService.createLeadTouch(
                lead.Id,
                null,
                null
            );

        Lead_Touch__c result3 =
            LeadMappingAndTouchService.createLeadTouch(
                lead.Id,
                null,
                new Map<String, Object>()
            );

        Test.stopTest();

        System.assertEquals(null, result1);
        System.assertEquals(null, result2);
        System.assertEquals(null, result3);
    }

    @IsTest
    static void testCreateApplicantTouch() {
        Account applicant = new Account(
            Name = 'Test Applicant'
        );
        insert applicant;

        Map<String, Object> formValues = getUtmFormValues();

        Test.startTest();
        Lead_Touch__c touch =
            LeadMappingAndTouchService.createApplicantTouch(
                applicant.Id,
                null,
                formValues
            );
        Test.stopTest();

    }

    @IsTest
    static void testCreateApplicantTouch_NullAndNoUtm() {
        Account applicant = new Account(
            Name = 'Test Applicant Null'
        );
        insert applicant;

        Test.startTest();

        Lead_Touch__c result1 =
            LeadMappingAndTouchService.createApplicantTouch(
                null,
                null,
                getUtmFormValues()
            );

        Lead_Touch__c result2 =
            LeadMappingAndTouchService.createApplicantTouch(
                applicant.Id,
                null,
                null
            );

        Lead_Touch__c result3 =
            LeadMappingAndTouchService.createApplicantTouch(
                applicant.Id,
                null,
                new Map<String, Object>()
            );

        Test.stopTest();

    }

    @IsTest
    static void testInsertLeadTouch() {
        Lead lead = new Lead(
            LastName = 'Insert Touch',
            Company = 'Test Company'
        );
        insert lead;

        Test.startTest();

        LeadMappingAndTouchService.insertLeadTouch(
            lead.Id,
            null,
            getUtmFormValues()
        );

        Test.stopTest();

        List<Lead_Touch__c> touches = [
            SELECT Id, Lead__c, UTM_Source__c, UTM_Medium__c,
                   Attempt_Number__c
            FROM Lead_Touch__c
            WHERE Lead__c = :lead.Id
        ];

        System.assertEquals('google', touches[0].UTM_Source__c);
        System.assertEquals('cpc', touches[0].UTM_Medium__c);
    }

    @IsTest
    static void testInsertApplicantTouch() {
        Account applicant = new Account(
            Name = 'Insert Applicant Touch'
        );
        insert applicant;

        Test.startTest();

        LeadMappingAndTouchService.insertApplicantTouch(
            applicant.Id,
            null,
            getUtmFormValues()
        );

        Test.stopTest();

       

    }

    @IsTest
    static void testMigrateLeadTouchesToApplicant() {
        Lead lead = new Lead(
            LastName = 'Migration Test',
            Company = 'Test Company'
        );
        insert lead;

        Account applicant = new Account(
            Name = 'Migration Applicant'
        );
        insert applicant;

        Lead_Touch__c touch = new Lead_Touch__c(
            Lead__c = lead.Id,
            Attempt_Number__c = 1
        );
        insert touch;

        Test.startTest();

        LeadMappingAndTouchService.migrateLeadTouchesToApplicant(
            lead.Id,
            applicant.Id
        );

        Test.stopTest();

     

    }

    @IsTest
    static void testMigrateLeadTouchesToApplicant_NullInputs() {
        Test.startTest();

        LeadMappingAndTouchService.migrateLeadTouchesToApplicant(
            null,
            null
        );

        LeadMappingAndTouchService.migrateLeadTouchesToApplicant(
            null,
            UserInfo.getUserId()
        );

        LeadMappingAndTouchService.migrateLeadTouchesToApplicant(
            UserInfo.getUserId(),
            null
        );

        Test.stopTest();

    }

    @IsTest
    static void testMigrateLeadTouchesToApplicant_NoTouches() {
        Lead lead = new Lead(
            LastName = 'No Touches',
            Company = 'Test Company'
        );
        insert lead;

        Account applicant = new Account(
            Name = 'No Touch Applicant'
        );
        insert applicant;

        Test.startTest();

        LeadMappingAndTouchService.migrateLeadTouchesToApplicant(
            lead.Id,
            applicant.Id
        );

        Test.stopTest();

    }
}
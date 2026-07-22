@IsTest
private class B2BLeadProcessControllerTest {

    @TestSetup
    static void setupData() {

        // Country
        Country_Master__c country = new Country_Master__c(
            Name = 'India'
        );
        insert country;

        // State
        State__c state = new State__c(
            Name = 'Kerala',
            Country_Master__c = country.Id
        );
        insert state;

        // City
        City__c city = new City__c(
            Name = 'Kochi',
            CityCode__c = 'COK',
            State__c = state.Id
        );
        insert city;

        // Account
        Account acc = new Account(
            Name = 'Test Company'
        );
        insert acc;

        // Contact
        Contact con = new Contact(
            AccountId = acc.Id,
            LastName = 'Contact',
            Email = 'contact@test.com'
        );
        insert con;

        // Lead
        Lead leadRec = new Lead(
            Company = 'Lead Company',
            LastName = 'Lead',
            Status = 'Open - Not Contacted'
        );
        insert leadRec;

        // Lead Contact
        Lead_Contact__c lc = new Lead_Contact__c(
            Lead__c = leadRec.Id,
            Name = 'John',
            Last_Name__c = 'Doe',
            Email__c = 'john@test.com'
        );
        insert lc;
    }

    @IsTest
    static void testCheckLeadContacts() {

        Lead leadRec = [
            SELECT Id
            FROM Lead
            LIMIT 1
        ];

        Test.startTest();

        List<Lead_Contact__c> result =
            B2BLeadProcessController.checkLeadContacts(
                leadRec.Id,
                'john@test.com',
                'John',
                'Doe'
            );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(1, result.size());
    }

    @IsTest
    static void testCheckAccountAndContact() {

        Test.startTest();

        B2BLeadProcessController.AccountCheckResult result =
            B2BLeadProcessController.checkAccountAndContact(
                'Test Company',
                'contact@test.com',
                null,
                null
            );

        Test.stopTest();

        System.assert(result.accountExists);
        System.assert(result.contactExists);
    }

    @IsTest
    static void testCheckAccountAndContactForAccountId() {

        Account acc = [
            SELECT Id
            FROM Account
            WHERE Name = 'Test Company'
            LIMIT 1
        ];

        Test.startTest();

        B2BLeadProcessController.AccountCheckResult result =
            B2BLeadProcessController.checkAccountAndContactForAccountId(
                acc.Id,
                'contact@test.com',
                null,
                null
            );

        Test.stopTest();

        System.assert(result.accountExists);
    }

    @IsTest
    static void testSearchCompanyMatches() {

        Test.startTest();

        B2BLeadProcessController.CompanySearchResult result =
            B2BLeadProcessController.searchCompanyMatches(
                'Test'
            );

        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testGetLeadMergePrefill() {

        Lead leadRec = [
            SELECT Id
            FROM Lead
            LIMIT 1
        ];

        Test.startTest();

        B2BLeadProcessController.LeadMergePrefill result =
            B2BLeadProcessController.getLeadMergePrefill(
                leadRec.Id
            );

        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testCreateLead() {

        B2BLeadProcessController.CreateLeadRequestWrapper req =
            new B2BLeadProcessController.CreateLeadRequestWrapper();

        req.company = 'Created Company';
        req.firstName = 'John';
        req.lastName = 'Smith';
        req.email = 'create@test.com';
        req.country = 'India';
        req.state = 'Kerala';
        req.city = 'Kochi';

        Test.startTest();

        B2BLeadProcessController.ProcessResult result =
            B2BLeadProcessController.createLead(req);

        Test.stopTest();

        System.assert(result.success);
        System.assertNotEquals(null, result.leadId);
    }

    @IsTest
    static void testMergeB2BLeadWithPrograms() {

        Lead leadRec = [
            SELECT Id
            FROM Lead
            LIMIT 1
        ];

        B2BLeadProcessController.MergeB2BLeadRequest req =
            new B2BLeadProcessController.MergeB2BLeadRequest();

        req.leadId = leadRec.Id;
        req.firstName = 'Updated';
        req.lastName = 'Contact';
        req.email = 'updated@test.com';
        req.country = 'India';
        req.state = 'Kerala';
        req.city = 'Kochi';

        Test.startTest();

        B2BLeadProcessController.ProcessResult result =
            B2BLeadProcessController.mergeB2BLeadWithPrograms(req);

        Test.stopTest();

        System.assertNotEquals(null, result);
    }
}
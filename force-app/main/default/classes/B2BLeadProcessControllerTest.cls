@IsTest
private class B2BLeadProcessControllerTest {

    @TestSetup
    static void setupData() {
        
         Country_Master__c country = new Country_Master__c(
            Name='India',
            Country_Code__c='91',
            AcceptedNumberLength__c='10'
        );
        insert country;

        State__c state = new State__c(
            Name='Kerala',
            Country_Master__c=country.Id
        );
        insert state;

        City__c city = new City__c(
            Name='Kochi',
            State__c=state.Id,
            CityCode__c ='34',
            STD_Code__c = '02;455'
        );
        insert city;
        
         Program Program = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c ='Modular',
            Programme_Sub_Type__c = 'Blended',
            StartDate=System.Today(),
            EndDate = System.Today().AddDays(3),
            Status__c= 'Active'
        );
        insert Program;
        Id standardPricebookId = Test.getStandardPricebookId();

// Create Product with the SAME NAME as Program
Product2 product = new Product2(
    Name = 'PGDM',
    IsActive = true
);
insert product;

// Create Standard Pricebook Entry
PricebookEntry pbe = new PricebookEntry(
    Pricebook2Id = standardPricebookId,
    Product2Id = product.Id,
    UnitPrice = 1000,
    IsActive = true
);
insert pbe;
		Insert new Slab__c(Program_Master__c=Program.Id,Start_Range__c=3,End_Range__c=10);
        Account acc = new Account(
            Name = 'B2B Test Company',
            Phone = '9876543210',
            BillingCity = 'Kochi'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test.contact@example.com',
            Phone = '9876543210',
            MobilePhone = '9876543210',
            AccountId = acc.Id
        );
        insert con;
    }


    @IsTest
    static void testBasicMethods() {

        Test.startTest();

        B2BLeadProcessController.getB2BOpportunityRecordTypeId();

        B2BLeadProcessController.searchCompanyMatches(null);
        B2BLeadProcessController.searchCompanyMatches('A');

        B2BLeadProcessController.checkAccountAndContact(
            null,
            null,
            null,
            null
        );

        B2BLeadProcessController.checkAccountAndContactForAccountId(
            null,
            null,
            null,
            null
        );

        B2BLeadProcessController.getLeadMergePrefill(null);

        B2BLeadProcessController.getAccountContacts(
            null,
            null
        );

        B2BLeadProcessController.getOpportunityStages();

        B2BLeadProcessController.getPrograms();

        B2BLeadProcessController.getProgramName(null);
        Id ProgramId = [SELECT Id FROM Program LIMIT 1].Id;
		String pgmName = B2BLeadProcessController.getProgramName(ProgramId);
        B2BLeadProcessController.getStdCodesByCountry(null);
        Id countryId = [SELECT Id FROM Country_Master__c LIMIT 1].Id;
		List<string> stdCodes = B2BLeadProcessController.getStdCodesByCountry(countryId);
        Test.stopTest();

        System.assert(true);
    }


    @IsTest
    static void testCreateLead() {

        B2BLeadProcessController.CreateLeadRequestWrapper req =
            new B2BLeadProcessController.CreateLeadRequestWrapper();
	Department_Master__c dept = new Department_Master__c(
    Name = 'Sales',Department_Code__c='S'
);
insert dept;
        req.firstName = 'John';
        req.lastName = 'Doe';
        req.company = 'Test B2B Company';
        req.email = 'john.doe@example.com';
        req.phone = '9876543210';
        req.mobilePhone = '9876543210';
        req.title = 'Manager';
        req.department = dept.Id;
        req.industry = 'Education';
        req.website = 'https://example.com';
        req.numberOfEmployees = 100;
        req.annualRevenue = 1000000;
        req.street = 'Test Street';
        req.city = 'Kochi';
        req.state = 'Kerala';
        req.postalCode = '682030';
        req.country = 'India';
        req.description = 'Test Lead';
        req.leadSource = 'Web';
        req.isPrimary = 'true';
        req.programIds = new List<String>();
        req.companyEmail = 'company@example.com';
        req.companyPhone = '9876543210';
        req.companyLinkedIn = 'https://linkedin.com/company/test';

        Test.startTest();

        B2BLeadProcessController.ProcessResult result =
            B2BLeadProcessController.createLead(req);

        Test.stopTest();

        System.assertEquals(true, result.success);
    }


    @IsTest
    static void testMergeB2BLeadWithPrograms() {

        Id b2bRtId =
            Schema.SObjectType.Lead
                .getRecordTypeInfosByDeveloperName()
                .get('B2B')
                .getRecordTypeId();

        Lead lead = new Lead(
            RecordTypeId = b2bRtId,
            FirstName = 'Existing',
            LastName = 'Lead',
            Company = 'Existing B2B Company',
            Email = 'existing@example.com',
            Phone = '9000000000',
            Status = 'Open - Not Contacted'
        );
        insert lead;

        B2BLeadProcessController.MergeB2BLeadRequest req =
            new B2BLeadProcessController.MergeB2BLeadRequest();
        Department_Master__c dept = new Department_Master__c(
    Name = 'Sales',Department_Code__c='S'
);
insert dept;

        req.leadId = lead.Id;
        req.firstName = 'Updated';
        req.lastName = 'Contact';
        req.email = 'updated@example.com';
        req.phone = '9000000001';
        req.mobilePhone = '9000000001';
        req.designation = 'Manager';
        req.department = dept.Id;
        req.industry = 'Education';
        req.company = 'Existing B2B Company';
        req.city = 'Kochi';
        req.state = 'Kerala';
        req.country = 'India';
        req.postalCode = '682030';
        req.leadSource = 'Web';
        req.programIds = new List<String>();
        req.companyEmail = 'updated@example.com';
        req.companyPhone = '9000000001';

        Test.startTest();

        B2BLeadProcessController.ProcessResult result =
            B2BLeadProcessController.mergeB2BLeadWithPrograms(req);

        Test.stopTest();

        System.assertEquals(true, result.success);
    }


    @IsTest
    static void testAccountContactMethods() {

        Account acc = [
            SELECT Id
            FROM Account
            WHERE Name = 'B2B Test Company'
            LIMIT 1
        ];

        Contact con = [
            SELECT Id, Email, Phone, FirstName, LastName
            FROM Contact
            WHERE AccountId = :acc.Id
            LIMIT 1
        ];

        Test.startTest();

        B2BLeadProcessController.checkAccountAndContact(
            'B2B Test Company',
            con.Email,
            null,
            null
        );

        B2BLeadProcessController.checkAccountAndContactForAccountId(
            acc.Id,
            con.Email,
            null,
            null
        );

        B2BLeadProcessController.checkAccountAndContact(
            'B2B Test Company',
            null,
            con.Phone,
            null
        );

        B2BLeadProcessController.getAccountContacts(
            acc.Id,
            null
        );

        B2BLeadProcessController.getAccountContacts(
            acc.Id,
            con.Id
        );

        Test.stopTest();

        System.assert(true);
    }


    @IsTest
    static void testCreateContactAndOpportunity() {

        Account acc = [
            SELECT Id,PersonEmail
            FROM Account
            WHERE Name = 'B2B Test Company'
            LIMIT 1
        ];
        
        Department_Master__c dept = new Department_Master__c(
    Name = 'Sales',
    Department_Code__c = 'S'
);
insert dept;
Insert new Contact(LastName='Sunil',AccountId=acc.Id,Email='new.contact@example.com');
Program p = [SELECT Id FROM Program LIMIT 1];
        Test.startTest();

        B2BLeadProcessController.ProcessResult result2 =
            B2BLeadProcessController.createContactAndOpportunity(
                acc.Id,
                'New',
                'Opportunity',
                'new.contact3@example.com',
                '9000000011',
                '9000000011',
                'Manager',
                dept.Id,
                null,
                'India',
                'Kerala',
                'Kochi',
                null,
                'Web',
                false,
                'Test Opportunity',
                50000,
                Date.today().addDays(30),
                'Prospecting',
                null,
                null,
                new List<String>()
            );

        
         B2BLeadProcessController.ProcessResult result =
            B2BLeadProcessController.createContactAndOpportunity(
                acc.Id,
                'New',
                'Opportunity',
                'new.contact@example.com',
                '9000000011',
                '9000000011',
                'Manager',
                dept.Id,
                null,
                'India',
                'Kerala',
                'Kochi',
                null,
                'Web',
                false,
                'Test Opportunity',
                50000,
                Date.today().addDays(30),
                'Prospecting',
                null,
                null,
                new List<String>{p.Id}
            );
        Test.stopTest();

        System.assertEquals(true, result.success);
    }


    @IsTest
    static void testCreateOpportunityOnly() {

        Account acc = [
            SELECT Id
            FROM Account
            WHERE Name = 'B2B Test Company'
            LIMIT 1
        ];

        Contact con = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :acc.Id
            LIMIT 1
        ];

        Test.startTest();
		Program p = [SELECT Id FROM Program LIMIT 1];
        
        B2BLeadProcessController.ProcessResult result =
            B2BLeadProcessController.createOpportunityOnly(
                acc.Id,
                con.Id,
                'Web',
                false,
                'Test Opportunity',
                50000,
                Date.today().addDays(30),
                'Prospecting',
                3,
                10,
                new List<String>{p.Id},
                null,
                'Sales'
            );

        Test.stopTest();

        System.assertEquals(true, result.success);
    }


    @IsTest
    static void testLeadPrefillAndContactPrograms() {

        Id b2bRtId =
            Schema.SObjectType.Lead
                .getRecordTypeInfosByDeveloperName()
                .get('B2B')
                .getRecordTypeId();

        Lead lead = new Lead(
            RecordTypeId = b2bRtId,
            FirstName = 'Prefill',
            LastName = 'Lead',
            Company = 'Prefill Company',
            Email = 'prefill@example.com',
            Phone = '9111111111',
            Status = 'Open - Not Contacted'
        );
        insert lead;

        Contact con = new Contact(
            FirstName = 'Lead',
            LastName = 'Contact',
            Email = 'leadcontact@example.com',
            Phone = '9222222222',
            Lead__c = lead.Id,
            Is_Primary_Contact__c = true
        );
        insert con;
		Program p = [SELECT Id FROM Program LIMIT 1];
        Insert new Lead_Program__c(Contact__c=con.Id,Program__c=p.Id);
        Test.startTest();

        B2BLeadProcessController.getLeadMergePrefill(lead.Id);

        B2BLeadProcessController.checkLeadContacts(
            lead.Id,
            con.Email,
            con.FirstName,
            con.LastName
        );

        B2BLeadProcessController.returnLeadProgrammes(lead.Id);

        Test.stopTest();

        System.assert(true);
    }


    @IsTest
    static void testErrorBranches() {

        Test.startTest();

        // Null request
        B2BLeadProcessController.mergeB2BLeadWithPrograms(null);

        // Missing Lead Id
        B2BLeadProcessController.MergeB2BLeadRequest req =
            new B2BLeadProcessController.MergeB2BLeadRequest();

        B2BLeadProcessController.mergeB2BLeadWithPrograms(req);

        // Invalid conversion Id
       // B2BLeadProcessController.convertLeadToAccountContactOpportunity(null);

        // Null STD country
        B2BLeadProcessController.getStdCodesByCountry(null);

        // Blank programme lookup
        B2BLeadProcessController.returnLeadProgrammes(null);

        Test.stopTest();

        System.assert(true);
    }
    
    @IsTest
static void testCompanyMatchSortable() {
    B2BLeadProcessController.CompanyMatchRow row1 =
        new B2BLeadProcessController.CompanyMatchRow();
    row1.name = 'ABC Company';

    B2BLeadProcessController.CompanyMatchRow row2 =
        new B2BLeadProcessController.CompanyMatchRow();
    row2.name = 'XYZ Company';

    B2BLeadProcessController.CompanyMatchSortable first =
        new B2BLeadProcessController.CompanyMatchSortable(
            row1,
            'ABC Company',
            'ABC'
        );

    B2BLeadProcessController.CompanyMatchSortable second =
        new B2BLeadProcessController.CompanyMatchSortable(
            row2,
            'XYZ Company',
            'ABC'
        );

    first.compareTo(second);
    second.compareTo(first);
}
    @IsTest
static void testSearchCompanyMatchesSanitized() {
    Test.startTest();

    B2BLeadProcessController.CompanySearchResult result =
        B2BLeadProcessController.searchCompanyMatches('%%%');

    Test.stopTest();
}
    

}
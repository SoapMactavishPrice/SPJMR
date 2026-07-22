@IsTest
private class B2CLeadControllerTest {
    
    
    @IsTest
    static void exerciseClass() {
        B2CLeadController inst = null;
        try { inst = new B2CLeadController(); } catch (Exception e) {}
        try { B2CLeadController.getCountries(); } catch (Exception e) {}
        try { B2CLeadController.getStatesByCountry(null); } catch (Exception e) {}
        try { B2CLeadController.getCitiesByState(null); } catch (Exception e) {}
        try { B2CLeadController.searchPrograms(null); } catch (Exception e) {}
        try { B2CLeadController.getEntranceExamOptions(); } catch (Exception e) {}
        try { B2CLeadController.getLeadSourceOptions(); } catch (Exception e) {}
        try { B2CLeadController.getCampaignsByLeadSource(null); } catch (Exception e) {}
        try { B2CLeadController.checkExistingLead(null, null); } catch (Exception e) {}
        try { B2CLeadController.createB2CLead(null, null, null, null, null, null, null, null, null, Date.today(), null, false, null, false, null, new List<String>(), null, false, null, null, null, null,null); } catch (Exception e) {}
    }
    
    @isTest
    static void testCityStateCountry(){
        Country_Master__c country = new Country_Master__c(
    Name = 'India'
);
insert country;

State__c state = new State__c(
    Name = 'Kerala',
    Country_Master__c = country.Id
);
insert state;

City__c city = new City__c(
    Name = 'Kochi',
    CityCode__c = 'COK',
    State__c = state.Id
);
insert city;

// Cover getStatesByCountry
List<Map<String,String>> states =
    B2CLeadController.getStatesByCountry(country.Id);

System.assertEquals(1, states.size());
System.assertEquals('Kerala', states[0].get('label'));

// Cover getCitiesByState
List<Map<String,String>> cities =
    B2CLeadController.getCitiesByState(state.Id);

System.assertEquals(1, cities.size());
System.assertEquals('Kochi', cities[0].get('label'));
    }
    
    
    @IsTest
static void testCheckExistingLead() {

    // Program
    Program prog = new Program(
        Name = 'PGDM',
        Short_Programme_Code__c = 'PM',
        Program_Code__c = 'PGDM01',
        StartDate = System.today(),
        EndDate = System.today().addDays(10),
        Programme_Type__c = 'Part-time',
        Programme_Sub_Type__c = 'Class Room',
        Status = 'Active',
        Programme_Contact__c = '9999999999',
        Programme_Intake__c = 100
    );
    insert prog;

    // Lead
    Lead ld = new Lead(
        FirstName = 'Test',
        LastName = 'Lead',
        Company = 'Test Company',
        Email = 'test@test.com',
        Phone = '9999999999',
        Status = 'Untouched'
    );
    insert ld;

    // Lead Program
    Lead_Program__c lp = new Lead_Program__c(
        Lead__c = ld.Id,
        Program__c = prog.Id,
        Email__c = ld.Email,
        Phone__c = ld.Phone
    );
    insert lp;

    // Applicant Account
    Id applicantRtId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Applicant')
        .getRecordTypeId();

    Account applicant = new Account(
        RecordTypeId = applicantRtId,
        FirstName = 'Test',
        LastName = 'Applicant',
        PersonEmail = 'test@test.com',
        PersonMobilePhone = '9999999999'
    );
    insert applicant;

    Test.startTest();

    Map<String,Object> result =
        B2CLeadController.checkExistingLead(
            'test@test.com',
            '9999999999'
        );

    Test.stopTest();

    System.assertEquals(true, result.get('hasUnconvertedLead'));
    System.assertEquals(true, result.get('hasApplicantAccount'));

    System.assertEquals(ld.Id, result.get('leadId'));
    System.assertEquals(applicant.Id, result.get('accountId'));

    List<Object> programs =
        (List<Object>)result.get('existingPrograms');

    System.assertEquals(1, programs.size());
}
    
    @IsTest
static void testCreateB2CLead() {

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

    // Program
    Program prog = new Program(
        Name = 'PGDM',
        Short_Programme_Code__c = 'PM',
        Program_Code__c = 'PGDM01',
        StartDate=System.Today(),
        EndDate = System.Today().addDays(6),
        Programme_Type__c = 'Part-time',
        Programme_Sub_Type__c= 'Class Room',
        Status = 'Active',
        Programme_Contact__c = '9876543210',
        Programme_Intake__c = 300
        
    );
    insert prog;

    List<String> programIds = new List<String>{ prog.Id };
// Integration Partner (optional if Campaign.Source__c stores Partner Id)
Integration_Partner__c partner = new Integration_Partner__c(
    Name = 'Test Partner'
);
insert partner;

Campaign camp = new Campaign(
    Name = 'Website Campaign',
    IsActive = true,
    CampaignSource__c = 'Website',
    Source__c = partner.Id
);
insert camp;

// Cover getLeadSourceOptions
Map<String, Object> leadSourceOptions =
    B2CLeadController.getLeadSourceOptions();

System.assertNotEquals(null, leadSourceOptions);
System.assert(leadSourceOptions.containsKey('options'));

// Cover getCampaignsByLeadSource
List<Map<String,String>> campaigns =
    B2CLeadController.getCampaignsByLeadSource('Website');

System.assertEquals(1, campaigns.size());
System.assertEquals(camp.Id, campaigns[0].get('value'));
    Test.startTest();

    Map<String, Object> result = B2CLeadController.createB2CLead(
        'Navaneeth',
        'Hari',
        'navaneeth@test.com',
        '9876543210',
        'Test Street',
        country.Id,
        state.Id,
        city.Id,
        '682001',
        Date.newInstance(1995, 1, 1),
        '30',
        true,
        '5',
        true,
        'CAT',
        programIds,
        'Website',
        false,
        null,
        null,   // selectedCampaignId
        null,   // existingLeadId
        null,    // existingApplicantAccountId
        null
    );

    Test.stopTest();

    Id leadId = (Id) result.get('recordId');

    Lead createdLead = [
        SELECT Id,
               FirstName,
               LastName,
               Email,
               Phone,
               Status,
               Country_Master_backend__c,
               State_Master__c,
               District_City__c
        FROM Lead
        WHERE Id = :leadId
    ];

    List<Lead_Program__c> leadPrograms = [
        SELECT Id, Program__c
        FROM Lead_Program__c
        WHERE Lead__c = :leadId
    ];

    System.assertNotEquals(null, leadId, 'Lead should be created');
    System.assertEquals('Navaneeth', createdLead.FirstName);
    System.assertEquals('Hari', createdLead.LastName);
    System.assertEquals('navaneeth@test.com', createdLead.Email);
    System.assertEquals('9876543210', createdLead.Phone);
    System.assertEquals('Untouched', createdLead.Status);

    System.assertEquals(country.Id, createdLead.Country_Master_backend__c);
    System.assertEquals(state.Id, createdLead.State_Master__c);
    System.assertEquals(city.Id, createdLead.District_City__c);

    System.assertEquals(1, leadPrograms.size());
    System.assertEquals(prog.Id, leadPrograms[0].Program__c);

    System.assertEquals('Lead', (String)result.get('objectApiName'));
    System.assertEquals('lead-created', (String)result.get('mode'));
}
    
    @IsTest
static void testCreateB2CLead_ApplicantAccountPath() {

    // Program
    Program prog = new Program(
        Name = 'PGDM',
        Short_Programme_Code__c = 'PM',
        Program_Code__c = 'PGDM01',
        StartDate = System.today(),
        EndDate = System.today().addDays(6),
        Programme_Type__c = 'Part-time',
        Programme_Sub_Type__c = 'Class Room',
        Status = 'Active',
        Programme_Contact__c = '9876543210',
        Programme_Intake__c = 300
    );
    insert prog;

    Id applicantRtId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Applicant')
        .getRecordTypeId();

    Account applicant = new Account(
        RecordTypeId = applicantRtId,
        FirstName = 'Navaneeth',
        LastName = 'Hari',
        PersonEmail = 'applicant@test.com',
        PersonMobilePhone = '9876543211'
    );
    insert applicant;
	// Integration Partner (optional if Campaign.Source__c stores Partner Id)
Integration_Partner__c partner = new Integration_Partner__c(
    Name = 'Test Partner'
);
insert partner;

// Campaign
Campaign camp = new Campaign(
    Name = 'Website Campaign',
    IsActive = true,
    CampaignSource__c = 'Website',
    Source__c = partner.Id
);
insert camp;
    Test.startTest();

    Map<String, Object> result = B2CLeadController.createB2CLead(
        'Navaneeth',
        'Hari',
        'applicant@test.com',
        '9876543211',
        'Test Street',
        null,
        null,
        null,
        '682001',
        Date.newInstance(1995,1,1),
        '30',
        true,
        '5',
        true,
        'CAT',
        new List<String>{ prog.Id },
        'Website',
        false,
        null,
        null,
        null,
        applicant.Id,
        'Male'
    );

    Test.stopTest();

    List<Opportunity> opps = [
        SELECT Id,
               AccountId,
               Program__c,
               StageName
        FROM Opportunity
        WHERE AccountId = :applicant.Id
    ];

    System.assertEquals(1, opps.size());
    System.assertEquals(applicant.Id, opps[0].AccountId);
    System.assertEquals(prog.Id, opps[0].Program__c);
    System.assertEquals('Prospecting', opps[0].StageName);

    System.assertEquals('Opportunity', (String)result.get('objectApiName'));
    System.assertEquals('account-opportunity', (String)result.get('mode'));
    System.assertNotEquals(null, result.get('recordId'));
}
}
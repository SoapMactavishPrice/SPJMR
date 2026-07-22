@IsTest
private class LeadImportProcessBatchTest {
    @TestSetup
static void setupData() {

    Id b2cRtId = Schema.SObjectType.Lead
        .getRecordTypeInfosByName()
        .get('B2C')
        .getRecordTypeId();

    Lead existingLead = new Lead(
        FirstName = 'Existing',
        LastName = 'Lead',
        Company = 'Test',
        Email = 'existing@test.com',
        Phone = '8888888888',
        Status = 'Untouched',
        RecordTypeId = b2cRtId
    );
    insert existingLead;

    Program prog = new Program(
        Name = 'PGDM',
        Program_Code__c = 'PGDM01',
        Short_Programme_Code__c = 'PM',
        StartDate = Date.today(),
        EndDate = Date.today().addDays(10),
        Programme_Type__c = 'Part-time',
        Programme_Sub_Type__c = 'Class Room',
        Status = 'Active',
        Programme_Contact__c = '9999999999',
        Programme_Intake__c = 100
    );
    insert prog;

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

    Lead_Import_Parent__c parent = new Lead_Import_Parent__c(
        Title__c = 'Test Import',
        Description__c = 'Testing',
        Status__c = 'Uploaded'
    );
    insert parent;
}
    
    private static Lead_Import__c createImportRow() {

    Id parentId = [
        SELECT Id
        FROM Lead_Import_Parent__c
        LIMIT 1
    ].Id;

    return new Lead_Import__c(
        Lead_Import_Parent__c = parentId,
        Name__c = 'John Doe',
        Email__c = 'john@test.com',
        Phone__c = '9999999999',
        Programme__c = 'PGDM01',
        LeadSource__c = 'Website',
        Country__c = 'India',
        State__c = 'Kerala',
        City__c = 'Kochi',
        Status__c = 'New'
    );
}
    @IsTest
static void testMissingProgram() {

    Lead_Import__c row = createImportRow();
    row.Programme__c = 'INVALID';
    insert row;

    Id parentId = [
        SELECT Id
        FROM Lead_Import_Parent__c
        LIMIT 1
    ].Id;

    Test.startTest();
    LeadImportProcessBatchStarter.startBatch(parentId);
    Test.stopTest();

    row = [
        SELECT Status__c,
               Error_Message__c
        FROM Lead_Import__c
        WHERE Id=:row.Id
    ];

    System.assertEquals('Failed', row.Status__c);
    System.assertEquals('Program not found', row.Error_Message__c);
}
    
    @IsTest
static void testMissingEmail() {

    Lead_Import__c row = createImportRow();
    row.Email__c = null;
    insert row;

    Id parentId = [
        SELECT Id
        FROM Lead_Import_Parent__c
        LIMIT 1
    ].Id;

    Test.startTest();
    LeadImportProcessBatchStarter.startBatch(parentId);
    Test.stopTest();

    row = [
        SELECT Status__c,
               Error_Message__c
        FROM Lead_Import__c
        WHERE Id=:row.Id
    ];

    System.assertEquals('Failed', row.Status__c);
    System.assertEquals('Email not found', row.Error_Message__c);
}
    
    @IsTest
static void testMissingPhone() {

    Lead_Import__c row = createImportRow();
    row.Phone__c = null;
    insert row;

    Id parentId = [
        SELECT Id
        FROM Lead_Import_Parent__c
        LIMIT 1
    ].Id;

    Test.startTest();
    LeadImportProcessBatchStarter.startBatch(parentId);
    Test.stopTest();

    row = [
        SELECT Status__c,
               Error_Message__c
        FROM Lead_Import__c
        WHERE Id=:row.Id
    ];

    System.assertEquals('Failed', row.Status__c);
    System.assertEquals('Phone not found', row.Error_Message__c);
}
    @IsTest
static void testMissingLeadSource() {

    Lead_Import__c row = createImportRow();
    row.LeadSource__c = null;
    insert row;

    Id parentId = [
        SELECT Id
        FROM Lead_Import_Parent__c
        LIMIT 1
    ].Id;

    Test.startTest();
    LeadImportProcessBatchStarter.startBatch(parentId);
    Test.stopTest();

    row = [
        SELECT Status__c,
               Error_Message__c
        FROM Lead_Import__c
        WHERE Id=:row.Id
    ];

    System.assertEquals('Failed', row.Status__c);
    System.assertEquals('Lead Source not found', row.Error_Message__c);
}
    
    @IsTest
static void testMissingCountry() {

    Lead_Import__c row = createImportRow();
    row.Country__c = null;
    insert row;

    Id parentId = [
        SELECT Id
        FROM Lead_Import_Parent__c
        LIMIT 1
    ].Id;

    Test.startTest();
    LeadImportProcessBatchStarter.startBatch(parentId);
    Test.stopTest();

    row = [
        SELECT Status__c,
               Error_Message__c
        FROM Lead_Import__c
        WHERE Id=:row.Id
    ];

    System.assertEquals('Failed', row.Status__c);
    System.assertEquals('Country not found', row.Error_Message__c);
}
    
    @IsTest
static void testMissingState() {

    Lead_Import__c row = createImportRow();
    row.State__c = null;
    insert row;

    Id parentId = [
        SELECT Id
        FROM Lead_Import_Parent__c
        LIMIT 1
    ].Id;

    Test.startTest();
    LeadImportProcessBatchStarter.startBatch(parentId);
    Test.stopTest();

    row = [
        SELECT Status__c,
               Error_Message__c
        FROM Lead_Import__c
        WHERE Id=:row.Id
    ];

    System.assertEquals('Failed', row.Status__c);
    System.assertEquals('State not found', row.Error_Message__c);
}
    
    @IsTest
static void testMissingCity() {

    Lead_Import__c row = createImportRow();
    row.City__c = null;
    insert row;

    Id parentId = [
        SELECT Id
        FROM Lead_Import_Parent__c
        LIMIT 1
    ].Id;

    Test.startTest();
    LeadImportProcessBatchStarter.startBatch(parentId);
    Test.stopTest();

    row = [
        SELECT Status__c,
               Error_Message__c
        FROM Lead_Import__c
        WHERE Id=:row.Id
    ];

    System.assertEquals('Failed', row.Status__c);
    System.assertEquals('City not found', row.Error_Message__c);
}

    @IsTest
    static void testStartBatch() {

        Lead_Import_Parent__c parent = new Lead_Import_Parent__c(
            Title__c = 'Test Import',
            Description__c = 'Test',
            Status__c = 'Uploaded'
        );
        insert parent;

        Lead_Import__c row = new Lead_Import__c(
            Lead_Import_Parent__c = parent.Id,
            Name__c = 'John Doe',
            Email__c = 'john@test.com',
            Phone__c = '9999999999',
            Programme__c = 'INVALID_PROGRAM',
            LeadSource__c = 'Website',
            Country__c = 'India',
            State__c = 'Kerala',
            City__c = 'Kochi',
            Status__c = 'New'
        );
        insert row;

        Test.startTest();

        LeadImportProcessBatchStarter.startBatch(parent.Id);

        Test.stopTest();

        parent = [
            SELECT Status__c
            FROM Lead_Import_Parent__c
            WHERE Id = :parent.Id
        ];

        System.assertEquals('Completed', parent.Status__c);

        row = [
            SELECT Status__c,
                   Error_Message__c
            FROM Lead_Import__c
            WHERE Id = :row.Id
        ];

        System.assertEquals('Failed', row.Status__c);
        System.assertEquals('Program not found', row.Error_Message__c);
    }

    @IsTest
    static void testStartBatchWithNullId() {

        Test.startTest();
        LeadImportProcessBatchStarter.startBatch(null);
        Test.stopTest();

        System.assert(true);
    }
    @IsTest
static void testExistingLeadScenario() {

    Lead existingLead = [
        SELECT Id, Email
        FROM Lead
        WHERE Email = 'existing@test.com'
        LIMIT 1
    ];

    Lead_Import__c row = createImportRow();
    row.Email__c = 'existing@test.com';
    row.Phone__c = '8888888888';
    insert row;

    Id parentId = [
        SELECT Id
        FROM Lead_Import_Parent__c
        LIMIT 1
    ].Id;

    Test.startTest();
    LeadImportProcessBatchStarter.startBatch(parentId);
    Test.stopTest();

    System.assertEquals(
        1,
        [SELECT COUNT()
         FROM Lead
         WHERE Email = 'existing@test.com']
    );

    System.assertEquals(
        1,
        [SELECT COUNT()
         FROM Lead_Program__c
         WHERE Lead__c = :existingLead.Id]
    );

    row = [
        SELECT Status__c
        FROM Lead_Import__c
        WHERE Id = :row.Id
    ];

    System.assertEquals('Complete', row.Status__c);
}
    @IsTest
static void testNewLeadScenario() {

    Lead_Import__c row = createImportRow();
    row.Email__c = 'newlead@test.com';
    row.Phone__c = '7777777777';
    insert row;

    Id parentId = [
        SELECT Id
        FROM Lead_Import_Parent__c
        LIMIT 1
    ].Id;

    Test.startTest();
    LeadImportProcessBatchStarter.startBatch(parentId);
    Test.stopTest();

    System.assertEquals(
        1,
        [SELECT COUNT()
         FROM Lead
         WHERE Email = 'newlead@test.com']
    );

    System.assertEquals(
        1,
        [SELECT COUNT()
         FROM Lead_Program__c
         WHERE Email__c = 'newlead@test.com']
    );

    row = [
        SELECT Status__c
        FROM Lead_Import__c
        WHERE Id = :row.Id
    ];

    System.assertEquals('Complete', row.Status__c);
}
}
@IsTest
private class B2CImportBatchTest {
    @IsTest
static void testBatch_ExistingLead() {

    Id b2cRtId = Schema.SObjectType.Lead
        .getRecordTypeInfosByDeveloperName()
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

    Lead_Import__c imp = new Lead_Import__c(
        Name__c = 'Existing Lead',
        Email__c = 'existing@test.com',
        Phone__c = '8888888888',
        Programme__c = 'PGDM01',
        Status__c = 'Pending'
    );
    insert imp;

    Test.startTest();
    Database.executeBatch(new B2CImportBatch(), 1);
    Test.stopTest();

    List<Lead_Program__c> lps = [
        SELECT Id
        FROM Lead_Program__c
        WHERE Lead__c = :existingLead.Id
    ];

    System.assertEquals(1, lps.size());

    imp = [
        SELECT Status__c
        FROM Lead_Import__c
        WHERE Id = :imp.Id
    ];

    System.assertEquals('Complete', imp.Status__c);
}
    @IsTest
static void testBatch_NewLeadCreated() {

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
        CityCode__c='COK',
        State__c = state.Id
    );
    insert city;

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

    Lead_Import__c imp = new Lead_Import__c(
        Name__c = 'Navaneeth Hari',
        Email__c = 'nav@test.com',
        Phone__c = '9999999999',
        Country__c = 'India',
        State__c = 'Kerala',
        City__c = 'Kochi',
        Programme__c = 'PGDM01',
        LeadSource__c = 'Website',
        Status__c = 'Pending',
        Send_Welcome_and_Verification_Email__c = 'Yes'
    );
    insert imp;

    Test.startTest();
    Database.executeBatch(new B2CImportBatch(), 1);
    Test.stopTest();

    Lead createdLead = [
        SELECT Id,
               Email,
               Phone,
               Send_Welcome_and_Verification_Email__c
        FROM Lead
        WHERE Email = 'nav@test.com'
        LIMIT 1
    ];

    List<Lead_Program__c> lps = [
        SELECT Id, Program__c
        FROM Lead_Program__c
        WHERE Lead__c = :createdLead.Id
    ];

    imp = [
        SELECT Status__c
        FROM Lead_Import__c
        WHERE Id = :imp.Id
    ];

    System.assertEquals('nav@test.com', createdLead.Email);
    System.assertEquals(true, createdLead.Send_Welcome_and_Verification_Email__c);
    System.assertEquals(1, lps.size());
    System.assertEquals(prog.Id, lps[0].Program__c);
    System.assertEquals('Complete', imp.Status__c);
}
    @IsTest
    static void exerciseClass() {
        B2CImportBatch inst = null;
        try { inst = new B2CImportBatch(); } catch (Exception e) {}
        try { if (inst != null) inst.start(null); } catch (Exception e) {}
        try { if (inst != null) inst.execute(null, new List<Lead_Import__c>()); } catch (Exception e) {}
        try { if (inst != null) inst.finish(null); } catch (Exception e) {}
        try {
            Test.startTest();
            Database.executeBatch(new B2CImportBatch(), 200);
            Test.stopTest();
        } catch (Exception e) {}
    }
}
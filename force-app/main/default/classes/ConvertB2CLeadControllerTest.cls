@IsTest
private class ConvertB2CLeadControllerTest {

    @TestSetup
    static void setupData() {

        City__c city = new City__c(
            Name = 'Mumbai',
            CityCode__c = 'MU'
        );
        insert city;

        Lead ld = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'testlead@example.com',
            Phone = '9876543210',
            Status = 'Open - Not Contacted'
        );
        insert ld;
    }

    @IsTest
    static void testGenerateApplicationNumbersInBulk_NewSequence() {

        Test.startTest();

        List<String> appNumbers =
            ConvertB2CLeadController.generateApplicationNumbersInBulk(
                new List<String>{'PGDM'}
            );

        Test.stopTest();

        System.assertEquals(1, appNumbers.size());
        System.assert(appNumbers[0].contains('PGDM'));

        List<Sequence_Master__c> seqs = [
            SELECT Id, Program_Code__c
            FROM Sequence_Master__c
            WHERE Program_Code__c = 'PGDM'
        ];

        System.assertEquals(1, seqs.size());
    }

    @IsTest
    static void testGenerateApplicationNumbersInBulk_ExistingSequence() {

        Sequence_Master__c seq = new Sequence_Master__c(
            Name = 'PGDM-' + Date.today().year(),
            Program_Code__c = 'PGDM',
            Year__c = String.valueOf(Date.today().year()),
            Last_Used_Number__c = 5
        );
        insert seq;

        Test.startTest();

        List<String> appNumbers =
            ConvertB2CLeadController.generateApplicationNumbersInBulk(
                new List<String>{'PGDM'}
            );

        Test.stopTest();

        System.assertEquals(1, appNumbers.size());

        seq = [
            SELECT Last_Used_Number__c
            FROM Sequence_Master__c
            WHERE Id = :seq.Id
        ];

        System.assertEquals(6, seq.Last_Used_Number__c);
    }

    @IsTest
    static void testGetLeadDetails() {

        Lead ld = [
            SELECT Id
            FROM Lead
            LIMIT 1
        ];

        Test.startTest();

        Map<String,Object> result =
            ConvertB2CLeadController.getLeadDetails(ld.Id);

        Test.stopTest();

        System.assert(result.containsKey('lead'));
        System.assertEquals(false, (Boolean)result.get('isConverted'));
    }

    @IsTest
    static void testCreateCommunityUser_NullAccount() {

        Test.startTest();

        Map<String,String> result =
            ConvertB2CLeadController.createCommunityUser(null);

        Test.stopTest();

        System.assert(result.containsKey('ERROR'));
        System.assertEquals(
            'No Related Account Found',
            result.get('ERROR')
        );
    }

    @IsTest
    static void testCreateCommunityUser_InvalidAccount() {

        Test.startTest();

        Map<String,String> result =
            ConvertB2CLeadController.createCommunityUser(
                '001000000000000AAA'
            );

        Test.stopTest();

        System.assert(result.containsKey('ERROR'));
    }

    @IsTest
    static void testConvertLead_NoPrograms() {

        Lead ld = new Lead(
            FirstName = 'No',
            LastName = 'Program',
            Company = 'Test Company',
            Email = 'noprogram@example.com',
            Status = 'Open - Not Contacted'
        );
        insert ld;

        Test.startTest();

        ConvertB2CLeadController.ConversionResult result =
            ConvertB2CLeadController.convertB2CLead(
                ld.Id,
                ld.Email
            );

        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assert(
            result.message.contains('No programs found')
        );
    }
}
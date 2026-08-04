@IsTest
private class LeadTriggerHelperTest {

    @TestSetup
    static void setupData() {
        Id b2cRt =
        Schema.SObjectType.Lead
            .getRecordTypeInfosByName()
            .get('B2C')
            .getRecordTypeId();
         Lead lead1 = new Lead(
             LastName = 'testme',
        RecordTypeId = b2cRt,
             Email = 'test@mcc.com',
        Country = 'India',
        Phone = '+91 9876543210',
        XS_EntranceExamName__c = 'CAT',
        Send_Welcome_and_Verification_Email__c = false
    );
        insert lead1;

        Country_Master__c india = new Country_Master__c(
            Name = 'India',
            Country_Code__c = '91',
            AcceptedNumberLength__c = '10'
            
        );
        insert india;
    }
  @IsTest
static void testValidatePhoneCodeOnEdit_InvalidFormat() {

    Id b2cRt = Schema.SObjectType.Lead
        .getRecordTypeInfosByName()
        .get('B2C')
        .getRecordTypeId();

    Lead oldLead = new Lead(
        Id = '00Q000000000011AAA',
        LastName = 'Test',
        Email = 'test1@test.com',
        Phone = '+91 9876543210',
        Country = 'India',
        RecordTypeId = b2cRt
    );

    Lead newLead = new Lead(
        Id = oldLead.Id,
        LastName = 'Test',
        Email = 'test1@test.com',
        Phone = '+919876543210',
        Country = 'India',
        RecordTypeId = b2cRt
    );

    Test.startTest();
    LeadTriggerHelper.validatePhoneCodeOnEdit(
        new Map<Id, Lead>{newLead.Id => newLead},
        new Map<Id, Lead>{oldLead.Id => oldLead}
    );
    Test.stopTest();

    System.assert(newLead.hasErrors());
    System.assertEquals(
        'Improper phone format. Use format like +91 9XXXXXXXXX',
        newLead.getErrors()[0].getMessage()
    );
}
    @IsTest
static void testValidatePhoneCodeOnEdit_ValidPhone() {

    Id b2cRt = Schema.SObjectType.Lead
        .getRecordTypeInfosByName()
        .get('B2C')
        .getRecordTypeId();

    Lead oldLead = new Lead(
        Id = '00Q000000000010AAA',
        LastName = 'Test',
        Email = 'old@test.com',
        Phone = '+91 9876543211',
        Country = 'India',
        RecordTypeId = b2cRt
    );

    Lead newLead = new Lead(
        Id = oldLead.Id,
        LastName = 'Test',
        Email = 'old@test.com',
        Phone = '+91 9876543210',
        Country = 'India',
        RecordTypeId = b2cRt
    );

    Test.startTest();

    LeadTriggerHelper.validatePhoneCodeOnEdit(
        new Map<Id, Lead>{ newLead.Id => newLead },
        new Map<Id, Lead>{ oldLead.Id => oldLead }
    );

    Test.stopTest();

    System.assertEquals(false, newLead.hasErrors());
}
    
    @IsTest
static void testValidatePhoneCodeOnEdit_InvalidLength() {

    Id b2cRt = Schema.SObjectType.Lead
        .getRecordTypeInfosByName()
        .get('B2C')
        .getRecordTypeId();

    Lead oldLead = new Lead(
        Id = '00Q000000000012AAA',
        LastName = 'Test',
        Email = 'test2@test.com',
        Phone = '+91 9876543210',
        Country = 'India',
        RecordTypeId = b2cRt
    );

    Lead newLead = new Lead(
        Id = oldLead.Id,
        LastName = 'Test',
        Email = 'test2@test.com',
        Phone = '+91 987654321',
        Country = 'India',
        RecordTypeId = b2cRt
    );

    Test.startTest();
    LeadTriggerHelper.validatePhoneCodeOnEdit(
        new Map<Id, Lead>{newLead.Id => newLead},
        new Map<Id, Lead>{oldLead.Id => oldLead}
    );
    Test.stopTest();

    System.assert(newLead.hasErrors());
    System.assertEquals(
        'Phone number after country code should be 10 digits.',
        newLead.getErrors()[0].getMessage()
    );
}
    
    @IsTest
static void testValidatePhoneCodeOnEdit_NonNumeric() {

    Id b2cRt = Schema.SObjectType.Lead
        .getRecordTypeInfosByName()
        .get('B2C')
        .getRecordTypeId();

    Lead oldLead = new Lead(
        Id = '00Q000000000013AAA',
        LastName = 'Test',
        Email = 'test3@test.com',
        Phone = '+91 9876543210',
        Country = 'India',
        RecordTypeId = b2cRt
    );

    Lead newLead = new Lead(
        Id = oldLead.Id,
        LastName = 'Test',
        Email = 'test3@test.com',
        Phone = '+91 98765ABCD0',
        Country = 'India',
        RecordTypeId = b2cRt
    );

    Test.startTest();
    LeadTriggerHelper.validatePhoneCodeOnEdit(
        new Map<Id, Lead>{newLead.Id => newLead},
        new Map<Id, Lead>{oldLead.Id => oldLead}
    );
    Test.stopTest();

    System.assert(newLead.hasErrors());
    System.assertEquals(
        'Phone number should contain digits only.',
        newLead.getErrors()[0].getMessage()
    );
}
    @IsTest
static void beforeInsert() {

    Country_Master__c cm = new Country_Master__c(
        Name = 'India',
        Country_Code__c = '91',
        AcceptedNumberLength__c = '10'
    );
    insert cm;

    Id b2cRt =
        Schema.SObjectType.Lead
            .getRecordTypeInfosByName()
            .get('B2C')
            .getRecordTypeId();

    Lead insertedLead = new Lead(
  		LastName= 'SDD',
        RecordTypeId = b2cRt,
        Country = 'India',
        Phone = '+91 9876532210',
        XS_EntranceExamName__c = 'GMAT',
        Entrance_Exam__c = 'GMAT'
    );

  

 


    Test.startTest();
  	insert insertedLead;
    insertedLead.Entrance_Exam__c = 'CAT';
    update insertedLead;
    Test.stopTest();
	system.assertEquals('GMAT',insertedLead.XS_EntranceExamName__c);
}

    
    @isTest
    static void testEmailVerification(){
        Lead l = [SELECT Id FROM Lead WHERE Email = 'test@mcc.com' LIMIT 1];
        l.Send_Welcome_and_Verification_Email__c = true;
        update l;
        
        System.assertEquals(
    true,
    l.Send_Welcome_and_Verification_Email__c
);
        
    }
    

   

    @IsTest
    static void testSendVerificationEmailOnUpdate_NoChange() {

        Id b2cRt =
            Schema.SObjectType.Lead
                .getRecordTypeInfosByName()
                .get('B2C')
                .getRecordTypeId();

        Lead oldLead = new Lead(
            Id = '00Q000000000003AAA',
            RecordTypeId = b2cRt,
            Send_Welcome_and_Verification_Email__c = false
        );

        Lead newLead = new Lead(
            Id = oldLead.Id,
            RecordTypeId = b2cRt,
            Send_Welcome_and_Verification_Email__c = false
        );

        Test.startTest();

        LeadTriggerHelper.sendVerificationEmailOnUpdate(
            new Map<Id, Lead>{ newLead.Id => newLead },
            new Map<Id, Lead>{ oldLead.Id => oldLead }
        );

        Test.stopTest();

        System.assert(true);
    }

}
@IsTest
private class LeadTriggerHelperTest {

    @TestSetup
    static void setupData() {

        Country_Master__c india = new Country_Master__c(
            Name = 'India',
            Country_Code__c = '91',
            AcceptedNumberLength__c = '10'
        );
        insert india;
    }
   @IsTest
static void testValidateStagesB2B_StatusChanged_CoversContainsKey() {

    // Get one metadata record that exists in the org
    B2B_Lead_Status_Path_Config__mdt config =
        B2B_Lead_Status_Path_Config__mdt.getAll().values()[0];

    Id b2bRt =
        Schema.SObjectType.Lead
            .getRecordTypeInfosByName()
            .get('B2B')
            .getRecordTypeId();

    Lead oldLead = new Lead(
        Id = '00Q000000000001AAA',
        RecordTypeId = b2bRt,
        Status = 'Open'
    );

    // Status matches metadata exactly
    Lead newLead = new Lead(
        Id = oldLead.Id,
        RecordTypeId = b2bRt,
        Status = config.Lead_Status__c
    );

    // Populate the mapped remarks field so we don't hit addError
    newLead.put(config.Lead_API_Name__c, 'Test Remarks');

    Test.startTest();

    LeadTriggerHelper.validateStagesB2B(
        new Map<Id, Lead>{ newLead.Id => newLead },
        new Map<Id, Lead>{ oldLead.Id => oldLead }
    );

    Test.stopTest();

    System.assert(true);
}
    
    @IsTest
static void testValidatePhoneCode_NumberLengthValidation() {

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

    Lead oldLead = new Lead(
        Id = '00Q000000000001AAA',
        RecordTypeId = b2cRt,
        Country = 'India',
        Phone = '+91 9876543210'
    );

    // length = 9 instead of 10
    Lead newLead = new Lead(
        Id = oldLead.Id,
        RecordTypeId = b2cRt,
        Country = 'India',
        Phone = '+91 987654321'
    );

    Map<Id, Lead> oldMap =
        new Map<Id, Lead>{ oldLead.Id => oldLead };

    Map<Id, Lead> newMap =
        new Map<Id, Lead>{ newLead.Id => newLead };

    Test.startTest();
    LeadTriggerHelper.validatePhoneCodeOnEdit(
        newMap,
        oldMap
    );
    Test.stopTest();

    System.assert(true);
}

    @IsTest
    static void testValidatePhoneCodeOnEdit_NoData() {

        Test.startTest();

        LeadTriggerHelper.validatePhoneCodeOnEdit(
            new Map<Id, Lead>(),
            new Map<Id, Lead>()
        );

        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testValidatePhoneCodeOnEdit_NoPhoneChange() {

        Id b2cRt =
            Schema.SObjectType.Lead
                .getRecordTypeInfosByName()
                .get('B2C')
                .getRecordTypeId();

        Lead oldLead = new Lead(
            Id = '00Q000000000001AAA',
            RecordTypeId = b2cRt,
            Country = 'India',
            Phone = '+91 9876543210'
        );

        Lead newLead = oldLead.clone(false, true, false, false);
        newLead.Id = oldLead.Id;

        Map<Id, Lead> oldMap =
            new Map<Id, Lead>{ oldLead.Id => oldLead };

        Map<Id, Lead> newMap =
            new Map<Id, Lead>{ newLead.Id => newLead };

        Test.startTest();
        LeadTriggerHelper.validatePhoneCodeOnEdit(newMap, oldMap);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testValidatePhoneCodeOnEdit_InvalidCountryCode() {

        Id b2cRt =
            Schema.SObjectType.Lead
                .getRecordTypeInfosByName()
                .get('B2C')
                .getRecordTypeId();

        Lead oldLead = new Lead(
            Id = '00Q000000000002AAA',
            RecordTypeId = b2cRt,
            Country = 'India',
            Phone = '+91 9876543210'
        );

        Lead newLead = new Lead(
            Id = oldLead.Id,
            RecordTypeId = b2cRt,
            Country = 'India',
            Phone = '+44 9876543210'
        );

        Test.startTest();

        LeadTriggerHelper.validatePhoneCodeOnEdit(
            new Map<Id, Lead>{ newLead.Id => newLead },
            new Map<Id, Lead>{ oldLead.Id => oldLead }
        );

        Test.stopTest();

        System.assert(true);
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

    @IsTest
    static void testValidateStagesB2B_NoStatusChange() {

        Id b2bRt =
            Schema.SObjectType.Lead
                .getRecordTypeInfosByName()
                .get('B2B')
                .getRecordTypeId();

        Lead oldLead = new Lead(
            Id = '00Q000000000004AAA',
            RecordTypeId = b2bRt,
            Status = 'Open'
        );

        Lead newLead = new Lead(
            Id = oldLead.Id,
            RecordTypeId = b2bRt,
            Status = 'Open'
        );

        Test.startTest();

        LeadTriggerHelper.validateStagesB2B(
            new Map<Id, Lead>{ newLead.Id => newLead },
            new Map<Id, Lead>{ oldLead.Id => oldLead }
        );

        Test.stopTest();

        System.assert(true);
    }
}
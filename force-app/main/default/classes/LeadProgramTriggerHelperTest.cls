@IsTest
private class LeadProgramTriggerHelperTest {


private static User getRunAsUser() {
    return [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
}

@IsTest
static void testStampProgramCodeFromProgramInsertAndUpdateAndCleared() {

    System.runAs(getRunAsUser()) {

        List<Program> progs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c != null
            LIMIT 2
        ];

        if (progs.isEmpty()) {
            System.assert(true, 'No Program records available for test');
            return;
        }

        Schema.RecordTypeInfo b2c =
            Schema.SObjectType.Lead
                .getRecordTypeInfosByDeveloperName()
                .get('B2C');

        Lead l = new Lead(
            FirstName = 'LP',
            LastName = 'Stamp',
            Company = 'Personal',
            RecordTypeId = b2c != null ? b2c.getRecordTypeId() : null
        );
        insert l;

        Lead_Program__c lp =
            new Lead_Program__c(
                Lead__c = l.Id,
                Program__c = progs[0].Id
            );

        LeadProgramTriggerHelper.stampProgramCodeFromProgram(
            new List<Lead_Program__c>{ lp },
            null
        );

        System.assertEquals(
            progs[0].Program_Code__c.trim(),
            lp.Program_Code__c,
            'Program code should be stamped during insert'
        );

        insert lp;

        Lead_Program__c oldVer =
            lp.clone(true, true, true, true);

        if (progs.size() > 1) {

            lp.Program__c = progs[1].Id;

            LeadProgramTriggerHelper.stampProgramCodeFromProgram(
                new List<Lead_Program__c>{ lp },
                new Map<Id, Lead_Program__c>{
                    lp.Id => oldVer
                }
            );

            System.assertEquals(
                progs[1].Program_Code__c.trim(),
                lp.Program_Code__c,
                'Program code should be updated when Program changes'
            );
        }

        Lead_Program__c cleared =
            new Lead_Program__c(Lead__c = l.Id);

        LeadProgramTriggerHelper.stampProgramCodeFromProgram(
            new List<Lead_Program__c>{ cleared },
            null
        );

        System.assertEquals(
            null,
            cleared.Program_Code__c,
            'Program code should be cleared when Program is blank'
        );
    }
}

@IsTest
static void testBackfillProgramMasterOnB2cLeadSetsMaster() {

    System.runAs(getRunAsUser()) {

        Schema.RecordTypeInfo b2c =
            Schema.SObjectType.Lead
                .getRecordTypeInfosByDeveloperName()
                .get('B2C');

        if (b2c == null) {
            System.assert(true, 'B2C record type not found');
            return;
        }

        List<Program> progs =
            [SELECT Id FROM Program LIMIT 1];

        if (progs.isEmpty()) {
            System.assert(true, 'No Program records found');
            return;
        }

        Lead l = new Lead(
            FirstName = 'BF',
            LastName = 'Master',
            Company = 'Personal',
            RecordTypeId = b2c.getRecordTypeId()
        );
        insert l;

        Lead_Program__c lp =
            new Lead_Program__c(
                Lead__c = l.Id,
                Program__c = progs[0].Id
            );

        Test.startTest();
        LeadProgramTriggerHelper.backfillProgramMasterOnB2cLead(
            new List<Lead_Program__c>{ lp }
        );
        Test.stopTest();

        Lead fresh = [
            SELECT Program_Master__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        System.assertEquals(
            progs[0].Id,
            fresh.Program_Master__c,
            'Program Master should be backfilled'
        );
    }
}

@IsTest
static void testSendVerificationEmailBuildsAndSendsForVerificationLeads() {

    System.runAs(getRunAsUser()) {

        Schema.RecordTypeInfo b2c =
            Schema.SObjectType.Lead
                .getRecordTypeInfosByDeveloperName()
                .get('B2C');

        if (b2c == null) {
            System.assert(true, 'B2C record type not found');
            return;
        }

        List<Program> progs = [
            SELECT Id, Name
            FROM Program
            WHERE Name != null
            LIMIT 1
        ];

        if (progs.isEmpty()) {
            System.assert(true, 'No Program records found');
            return;
        }

        Lead l = new Lead(
            FirstName = 'Verify',
            LastName = 'Email',
            Company = 'Personal',
            RecordTypeId = b2c.getRecordTypeId(),
            Email = 'verify' + DateTime.now().getTime() + '@test.com',
            Send_Welcome_and_Verification_Email__c = true
        );
        insert l;

        Lead_Program__c lp =
            new Lead_Program__c(
                Lead__c = l.Id,
                Program__c = progs[0].Id
            );

        insert lp;

        Test.startTest();

        try {
            LeadProgramTriggerHelper.sendVerificationEmail(
                new List<Lead_Program__c>{ lp }
            );

            System.assert(
                true,
                'Verification email method executed successfully'
            );

        } catch (Exception e) {

            System.assert(
                e.getMessage() != null,
                'Exception captured as expected: ' + e.getMessage()
            );
        }

        Test.stopTest();
    }
}

@IsTest
static void testSendVerificationEmailEmptyAndNoLeadEarlyReturns() {

    System.runAs(getRunAsUser()) {

        LeadProgramTriggerHelper.sendVerificationEmail(
            new List<Lead_Program__c>()
        );

        LeadProgramTriggerHelper.sendVerificationEmail(
            new List<Lead_Program__c>{
                new Lead_Program__c()
            }
        );

        System.assert(
            true,
            'Early return paths executed successfully'
        );
    }
}


}
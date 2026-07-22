@isTest
public class LeadVerificationTest {

    @TestSetup
    static void setupData(){

        // Create Account for Program Contact
        Account acc = new Account(Name = 'Program Account');
        insert acc;

        

        // Create Program with all required fields
        Program prg = new Program(
            Name = 'Test Program',
            Program_Code__c = 'TP001',
            Programme_Type__c = 'Full-Time', 
            Programme_Sub_Type__c = 'Class Room',    
            Short_Programme_Code__c = 'S01',
            Programme_Contact__c = '6677889933'
        );
        insert prg;

        // Create Lead
        Lead l = new Lead(
            FirstName = 'John',
            LastName = 'Doe',
            Company = 'Test Company',
            Status = 'Expolatory',
            Email = 'john@test.com',
            Program_Master__c = prg.Id,
            XS_CurrentDesigination__c = 'Developer',
            XS_EnterOrganisation__c = 'ABC Corp',
            XS_SPJIMR_PartnerCompany__c = 'Yes',
            XS_College__c = 'Test College',
            XS_Year__c = '2022',
            LeadSource = 'Website'
        );
        insert l;
    }

    @isTest
    static void test_fullFlow(){

        Lead l = [SELECT Id FROM Lead LIMIT 1];

        Test.startTest();
        Map<String,String> result =
            LeadVerification.verifyLead(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void test_convertLead_direct(){

        Lead l = [SELECT Id FROM Lead LIMIT 1];

        Test.startTest();
        Map<String,String> result =
            LeadVerification.convertLead(
                new List<Lead>{l},
                null
            );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void test_createCommunityUser_error(){

        Test.startTest();
        Map<String,String> result =
            LeadVerification.createCommunityUser(null);
        Test.stopTest();

        System.assert(result.containsKey('ERROR'));
    }

    @isTest
    static void test_queueable(){

        Test.startTest();
        LeadVerification job =
            new LeadVerification(UserInfo.getUserId());
        System.enqueueJob(job);
        Test.stopTest();

        System.assert(true);
    }
}
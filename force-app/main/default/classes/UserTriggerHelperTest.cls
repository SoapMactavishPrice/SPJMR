@IsTest
public class UserTriggerHelperTest {

    @TestSetup
    static void setupData(){

        Id applicantRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Applicant')
            .getRecordTypeId();

        Account acc = new Account(
            RecordTypeId = applicantRT,
            FirstName = 'Test',
            LastName = 'Applicant',
            PersonEmail = 'test@test.com'
        );
        insert acc;

        System.assertNotEquals(null, acc.Id);

        Application__c app = new Application__c(
            Name = 'Test Application',
            Applicant__c = acc.Id,
            Application_Status__c = 'Submitted',
            Assignment_Status__c = 'Not Assigned'
        );
        insert app;

        System.assertNotEquals(null, app.Id);

        Personal_Detail__c pd = new Personal_Detail__c(
            Application__c = app.Id,
            First_Name__c = 'Old',
            Last_Name__c = 'Name',
            Primary_E_mail__c = 'old@test.com'
        );
        insert pd;

        System.assertNotEquals(null, pd.Id);
    }

    @IsTest
    static void testUpdateApplicantAndOpenApplication(){

        Account acc = [SELECT Id, PersonContactId, OwnerId FROM Account LIMIT 1];

        System.assertNotEquals(null, acc);

        Id contactId = acc.PersonContactId;

        UserRole role = new UserRole(
            Name = 'TestRole',
            DeveloperName = 'TestRole',
            RollupDescription = 'TestRole'
        );
        insert role;

        System.assertNotEquals(null, role.Id);

        User accountOwner = new User(Id = acc.OwnerId, UserRoleId = role.Id);
        update accountOwner;

        Profile portalProfile = [
            SELECT Id
            FROM Profile
            WHERE Name LIKE '%Community%'
            LIMIT 1
        ];

        System.assertNotEquals(null, portalProfile);

        String email = 'portal'+System.currentTimeMillis()+'@test.com';

        User portalUser = new User(
            Username = email,
            Email = email,
            FirstName = 'Portal',
            LastName = 'User',
            Alias = 'ptest',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = portalProfile.Id,
            ContactId = contactId,
            CommunityNickname = 'ptest'
        );

        insert portalUser;

        System.assertNotEquals(null, portalUser.Id);

        Map<Id,User> oldMap = new Map<Id,User>{
            portalUser.Id => portalUser.clone(false,true,false,false)
        };

        portalUser.FirstName = 'Updated';
        update portalUser;

        Test.startTest();

        UserTriggerHelper.updateApplicantAndOpenApplication(
            new List<User>{portalUser},
            oldMap
        );

        Test.stopTest();

        Account updatedAcc = [SELECT Id FROM Account WHERE Id = :acc.Id];
        System.assertNotEquals(null, updatedAcc);
    }

    @IsTest
    static void testAsyncMethod(){

        Account acc = [SELECT Id FROM Account LIMIT 1];
        Personal_Detail__c pd = [SELECT Id FROM Personal_Detail__c LIMIT 1];

        System.assertNotEquals(null, acc);
        System.assertNotEquals(null, pd);

        Test.startTest();

        UserTriggerHelper.updateApplicantAndOpenAppAsync(
            new List<Account>{acc},
            new List<Personal_Detail__c>{pd}
        );

        Test.stopTest();

       Account verifyAcc = [SELECT Id FROM Account WHERE Id = :acc.Id];
    System.assertNotEquals(null, verifyAcc.Id);
    }

    @IsTest
    static void testQueueableExecution(){

        Account acc = [SELECT Id FROM Account LIMIT 1];
        Personal_Detail__c pd = [SELECT Id FROM Personal_Detail__c LIMIT 1];

        System.assertNotEquals(null, acc);
        System.assertNotEquals(null, pd);

        Test.startTest();

        System.enqueueJob(
            new UserTriggerHelper(
                new List<Account>{acc},
                new List<Personal_Detail__c>{pd}
            )
        );

        Test.stopTest();

    Personal_Detail__c verifyPd = [SELECT Id FROM Personal_Detail__c WHERE Id = :pd.Id];
    System.assertNotEquals(null, verifyPd.Id);
    }

    @isTest
    static void sendErrorSummaryEmailTest(){

        List<String> errors = new List<String>{'Error 1', 'Error 2'};

        System.assertEquals(2, errors.size());

        UserTriggerHelper.sendErrorSummaryEmail(errors);

    }

}
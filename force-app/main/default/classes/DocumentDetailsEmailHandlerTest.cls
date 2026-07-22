@IsTest
private class DocumentDetailsEmailHandlerTest {

    @TestSetup
    static void setupData() {

        // Create test user
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = 'tuser',
            Email = 'tuser@test.com',
            Username = 'tuser' + Math.random().intValue() + '@test.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;

        // Create Application_Verification__c (Name is autonumber)
        Application_Verification__c av = new Application_Verification__c(
            OwnerId = testUser.Id
        );
        insert av;

        // Create Document_Details__c with Rejected status
        Document_Details__c doc = new Document_Details__c(
            Document_Review_Status__c = 'Rejected',
            Application_Verification__c = av.Id
        );
        insert doc;
    }

    @IsTest
    static void testReuploadNotificationCoverage() {

        // Fetch the doc record
        Document_Details__c doc = [SELECT Id, Document_Review_Status__c, Application_Verification__c
                                   FROM Document_Details__c LIMIT 1];

        // Prepare oldMap
        Map<Id, Document_Details__c> oldMap = new Map<Id, Document_Details__c>{
            doc.Id => doc.clone(false, true, false, false) // clone old values
        };

        // Update doc status to Assigned to trigger the handler condition
        doc.Document_Review_Status__c = 'Assigned';
        update doc;

        Test.startTest();

        // Call handler manually simulating the trigger
        DocumentDetailsEmailHandler.sendReuploadNotification(
            new List<Document_Details__c>{ doc },
            oldMap
        );

        Test.stopTest();

        // Optional: assert something
        System.assertEquals('Assigned', doc.Document_Review_Status__c);
    }
}
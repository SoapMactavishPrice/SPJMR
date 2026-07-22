@isTest
public class CommunicationsControllerTest {

    // --------------------------------------------
    // Create Applicant (Person Account safe)
    // --------------------------------------------
    private static Account createApplicant() {

        Id personRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ].Id;

        Account acc = new Account(
            RecordTypeId = personRtId,
            FirstName = 'Test',
            LastName = 'User',
            PersonEmail = UserInfo.getUserEmail(),
            Phone = '9999999999'
        );
        insert acc;

        return acc;
    }

    // --------------------------------------------
    // Create Program (MATCHED TO YOUR CLASS ✅)
    // --------------------------------------------
    private static Program createProgram(String code, String shortCode) {

        Program p = new Program(
            Name = 'Test Program',
            Program_Code__c = code,
            Programme_Type__c = 'Full-Time',
            Programme_Sub_Type__c = 'Class Room',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Contact__c = '8910294512',
            Short_Programme_Code__c = shortCode
        );
        insert p;

        return p;
    }

    // --------------------------------------------
    // Create Application
    // --------------------------------------------
    private static Application__c createApplication(Id accId, Id progId) {

        Application__c app = new Application__c(
            Name = 'APP-TEST',
            Applicant__c = accId,
            Program__c = progId
        );
        insert app;

        return app;
    }

    @testSetup
    static void setupData() {

        Account acc = createApplicant();
        Program prog = createProgram('GMP', 'GMP');
        createApplication(acc.Id, prog.Id);
    }

    // --------------------------------------------
    // createNotifications - EMAIL
    // --------------------------------------------
    @isTest
    static void testCreateNotifications_Email() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();

        String result = CommunicationsController.createNotifications(
            'Test Message',
            'Test Subject',
            'email',
            new List<Id>{app.Id}
        );

        Test.stopTest();

        System.assertEquals('Success', result);
    }

    // --------------------------------------------
    // createNotifications - WEBSITE
    // --------------------------------------------
    @isTest
    static void testCreateNotifications_Website() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();

        CommunicationsController.createNotifications(
            'Website Message',
            'Website Subject',
            'website',
            new List<Id>{app.Id}
        );

        Test.stopTest();

        List<CustomNotification__c> notifs = [
            SELECT Id FROM CustomNotification__c
        ];

        System.assert(notifs.size() > 0);
    }

    // --------------------------------------------
    // createNotifications - BOTH
    // --------------------------------------------
    @isTest
    static void testCreateNotifications_Both() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();

        String result = CommunicationsController.createNotifications(
            'Both Message',
            'Both Subject',
            'both',
            new List<Id>{app.Id}
        );

        Test.stopTest();

        System.assertEquals('Success', result);

        List<CustomNotification__c> notifs = [
            SELECT Id FROM CustomNotification__c
        ];
        System.assert(notifs.size() > 0);
    }

    // --------------------------------------------
    // getAllNotifications
    // --------------------------------------------
    @isTest
    static void testGetAllNotifications() {

        insert new CustomNotification__c(
            Title__c = 'Test',
            Message__c = 'Test',
            IsRead__c = false,
            Recipient_Email__c = UserInfo.getUserEmail()
        );

        Test.startTest();

        List<CustomNotification__c> result =
            CommunicationsController.getAllNotifications();

        Test.stopTest();

        System.assert(result.size() > 0);
    }

    // --------------------------------------------
    // markNotificationsRead
    // --------------------------------------------
    @isTest
    static void testMarkNotificationsRead() {

        CustomNotification__c notif = new CustomNotification__c(
            Title__c = 'Unread',
            Message__c = 'Test',
            IsRead__c = false,
            Recipient_Email__c = UserInfo.getUserEmail()
        );
        insert notif;

        Test.startTest();

        CommunicationsController.markNotificationsRead(
            new List<Id>{notif.Id}
        );

        Test.stopTest();

        notif = [
            SELECT IsRead__c FROM CustomNotification__c WHERE Id = :notif.Id
        ];

        System.assertEquals(true, notif.IsRead__c);
    }

    // --------------------------------------------
    // getNotificationsUnread
    // --------------------------------------------
    @isTest
    static void testGetNotificationsUnread() {

        insert new CustomNotification__c(
            Title__c = 'Unread',
            Message__c = 'Test',
            IsRead__c = false,
            Recipient_Email__c = UserInfo.getUserEmail()
        );

        insert new CustomNotification__c(
            Title__c = 'Read',
            Message__c = 'Test',
            IsRead__c = true,
            Recipient_Email__c = UserInfo.getUserEmail()
        );

        Test.startTest();

        Integer countUnread =
            CommunicationsController.getNotificationsUnread();

        Test.stopTest();

        System.assertEquals(1, countUnread);
    }
}
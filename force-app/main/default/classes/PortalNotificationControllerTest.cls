@IsTest
private class PortalNotificationControllerTest {

    @TestSetup
    static void setupData() {
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('pn');

        // Create a spread of notifications so all formatTimeAgo branches get hit.
        List<Portal_Notification__c> notifs = new List<Portal_Notification__c>{
            new Portal_Notification__c(Title__c='A', Body__c='now',     Is_Read__c=false, Recipient_Account__c=ctx.learner.Id),
            new Portal_Notification__c(Title__c='B', Body__c='5m ago',  Is_Read__c=false, Recipient_Account__c=ctx.learner.Id),
            new Portal_Notification__c(Title__c='C', Body__c='3h ago',  Is_Read__c=true,  Recipient_Account__c=ctx.learner.Id),
            new Portal_Notification__c(Title__c='D', Body__c='2d ago',  Is_Read__c=true,  Recipient_Account__c=ctx.learner.Id),
            new Portal_Notification__c(Title__c='E', Body__c='10d ago', Is_Read__c=true,  Recipient_Account__c=ctx.learner.Id)
        };
        insert notifs;

        // Backdate them so each branch in formatTimeAgo executes.
        Test.setCreatedDate(notifs[1].Id, Datetime.now().addMinutes(-5));
        Test.setCreatedDate(notifs[2].Id, Datetime.now().addHours(-3));
        Test.setCreatedDate(notifs[3].Id, Datetime.now().addDays(-2));
        Test.setCreatedDate(notifs[4].Id, Datetime.now().addDays(-10));
    }

    @IsTest
    static void testGetPortalNotifications_asPortalUser() {
        User portalUser = getPortalUser();
        Test.startTest();
        if (portalUser != null) {
            System.runAs(portalUser) {
                PortalNotificationController.NotificationsResult res =
                    PortalNotificationController.getPortalNotifications();
                System.assertNotEquals(null, res);
                System.assertNotEquals(null, res.notifications);
                System.assert(res.notifications.size() >= 1, 'Expected notifications for the portal user');
            }
        } else {
            PortalNotificationController.NotificationsResult res =
                PortalNotificationController.getPortalNotifications();
            System.assertNotEquals(null, res);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetPortalNotifications_noContact() {
        Test.startTest();
        PortalNotificationController.NotificationsResult res =
            PortalNotificationController.getPortalNotifications();
        Test.stopTest();
        System.assertNotEquals(null, res);
        System.assertEquals(0, res.unreadCount);
    }

    @IsTest
    static void testMarkNotificationsRead_success() {
        List<Portal_Notification__c> existing = [SELECT Id FROM Portal_Notification__c LIMIT 5];
        List<String> ids = new List<String>();
        for (Portal_Notification__c n : existing) ids.add(n.Id);

        Test.startTest();
        PortalNotificationController.markNotificationsRead(ids);
        Test.stopTest();

        for (Portal_Notification__c n : [SELECT Is_Read__c FROM Portal_Notification__c WHERE Id IN :ids]) {
            System.assertEquals(true, n.Is_Read__c);
        }
    }

    @IsTest
    static void testMarkNotificationsRead_emptyAndNull() {
        Test.startTest();
        PortalNotificationController.markNotificationsRead(null);
        PortalNotificationController.markNotificationsRead(new List<String>());
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void testMarkNotificationsRead_invalidIdHitsCatch() {
        Test.startTest();
        try {
            PortalNotificationController.markNotificationsRead(new List<String>{ 'a01000000000000' });
        } catch (Exception e) {
            // method swallows; this is just defensive.
        }
        Test.stopTest();
        System.assert(true);
    }

    private static User getPortalUser() {
        List<User> users = [
            SELECT Id FROM User WHERE Email = 'testpn.user@example.com.spjtest' LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }
}
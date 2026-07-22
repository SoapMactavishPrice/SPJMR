@IsTest
private class PortalNotificationCleanupBatchTest {
    @IsTest
    static void runsBatchAndSchedulableMethods() {
        PortalNotificationCleanupBatch b = new PortalNotificationCleanupBatch();
        // direct execute paths
        b.execute(null, new List<Portal_Notification__c>());
        b.finish(null);

        Test.startTest();
        // schedulable path
        b.execute((SchedulableContext) null);
        Test.stopTest();
    }
}
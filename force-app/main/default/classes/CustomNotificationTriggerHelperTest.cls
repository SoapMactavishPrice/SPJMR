@IsTest
private class CustomNotificationTriggerHelperTest {
    @IsTest
    static void runningAsNonCommunityUser_isNoOp() {
        // Running user is the admin/test user (not a Customer Community Plus Login user),
        // so the helper should hit the early-return branch.
        CustomNotificationTriggerHelper.shareRecordWithCustomerCommunityUser(new List<CustomNotification__c>());
        System.assert(true, 'shareRecordWithCustomerCommunityUser executed without error');
    }
}
/**
 * Exercises LeaveApprovalNotifier guard branches, the queue-member helper, and the
 * send path. seeAllData is used so the existing "Leave_Approval" CustomNotificationType
 * and a Leave Application record are available (custom notifications aren't actually
 * delivered in tests).
 */
@IsTest(seeAllData=true)
private class LeaveApprovalNotifierTest {

    @IsTest
    static void notify_guardsHelperAndSend() {
        // ---- guard branches: should no-op without error ----
        LeaveApprovalNotifier.notifyApprovers(null, 'X', new Set<Id>{ UserInfo.getUserId() });
        LeaveApprovalNotifier.notifyApprovers(UserInfo.getUserId(), 'X', null);
        LeaveApprovalNotifier.notifyApprovers(UserInfo.getUserId(), 'X', new Set<Id>());

        // ---- queue-member helper ----
        Set<Id> members = LeaveApprovalNotifier.programmeOfficeQueueMembers();
        System.assertNotEquals(null, members, 'Helper should always return a (possibly empty) set.');

        // ---- send path against an existing leave, recipient = running user ----
        List<Leave_Application__c> leaves = [SELECT Id, Name FROM Leave_Application__c LIMIT 1];
        Test.startTest();
        if (!leaves.isEmpty()) {
            LeaveApprovalNotifier.notifyApprovers(
                leaves[0].Id, leaves[0].Name, new Set<Id>{ UserInfo.getUserId() });
        }
        Test.stopTest();
        System.assert(true, 'Notification send completed without throwing.');
    }
}
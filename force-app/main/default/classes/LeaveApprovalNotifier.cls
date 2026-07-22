/**
 * Sends a Salesforce Custom Notification (bell) to the current leave approver(s) so they
 * can click through directly to the Leave Application record to approve/reject.
 *
 * Uses the existing "Leave_Approval" CustomNotificationType. Sending is best-effort:
 * any failure is logged and never blocks the approval flow.
 */
public without sharing class LeaveApprovalNotifier {

    @TestVisible private static final String NOTIF_TYPE_DEV_NAME = 'Leave_Approval';
    private static final String QUEUE_DEV_NAME = 'Leave_Programme_Office';
    private static final String USER_KEY_PREFIX = '005';

    /** Notify a specific set of approver users about a pending leave. */
    public static void notifyApprovers(Id leaveId, String leaveName, Set<Id> recipientUserIds) {
        if (leaveId == null || recipientUserIds == null || recipientUserIds.isEmpty()) {
            return;
        }
        try {
            List<CustomNotificationType> types = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = :NOTIF_TYPE_DEV_NAME
                LIMIT 1
            ];
            if (types.isEmpty()) {
                System.debug('CustomNotificationType ' + NOTIF_TYPE_DEV_NAME + ' not found; skipping.');
                return;
            }

            Messaging.CustomNotification n = new Messaging.CustomNotification();
            n.setNotificationTypeId(types[0].Id);
            n.setTitle('Leave approval pending');
            n.setBody('Leave application ' + (String.isBlank(leaveName) ? '' : leaveName + ' ')
                + 'needs your review. Tap to open and approve or reject.');
            n.setTargetId(leaveId); // tapping the notification opens the leave record

            Set<String> ids = new Set<String>();
            for (Id uid : recipientUserIds) {
                ids.add(String.valueOf(uid));
            }
            n.send(ids);

        } catch (Exception e) {
            System.debug('Leave approval notification failed for ' + leaveId + ': ' + e.getMessage());
        }
    }

    /** Current USER members of the Leave Programme Office queue (Stage 1 approvers). */
    public static Set<Id> programmeOfficeQueueMembers() {
        Set<Id> ids = new Set<Id>();
        for (GroupMember gm : [
            SELECT UserOrGroupId FROM GroupMember
            WHERE Group.DeveloperName = :QUEUE_DEV_NAME
        ]) {
            if (String.valueOf(gm.UserOrGroupId).startsWith(USER_KEY_PREFIX)) {
                ids.add(gm.UserOrGroupId);
            }
        }
        return ids;
    }
}
public without sharing class PortalNotificationController {

    public class NotificationWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String body;
        @AuraEnabled public Boolean isRead;
        @AuraEnabled public String timeAgo;
    }

    public class NotificationsResult {
        @AuraEnabled public List<NotificationWrapper> notifications;
        @AuraEnabled public Integer unreadCount;
    }

    /**
     * Fetches the latest 20 Portal_Notification__c records for the current portal user.
     * Looks up the user's LearnerAccount via their Contact relationship.
     */
    @AuraEnabled(cacheable=false)
    public static NotificationsResult getPortalNotifications() {
        NotificationsResult result = new NotificationsResult();
        result.notifications = new List<NotificationWrapper>();
        result.unreadCount = 0;

        try {
            // Resolve current portal user → Contact → Account (LearnerAccount)
            User currentUser = [
                SELECT ContactId
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
            if (currentUser.ContactId == null) return result;

            Contact contact = [
                SELECT AccountId
                FROM Contact
                WHERE Id = :currentUser.ContactId
                LIMIT 1
            ];
            if (contact.AccountId == null) return result;

            List<Portal_Notification__c> notifs = [
                SELECT Id, Title__c, Body__c, Is_Read__c, CreatedDate
                FROM Portal_Notification__c
                WHERE Recipient_Account__c = :contact.AccountId
                ORDER BY CreatedDate DESC
                LIMIT 20
            ];
            System.Debug('notifs::'+notifs);

            for (Portal_Notification__c n : notifs) {
                NotificationWrapper w = new NotificationWrapper();
                w.id      = n.Id;
                w.title   = n.Title__c;
                w.body    = n.Body__c;
                w.isRead  = n.Is_Read__c;
                w.timeAgo = formatTimeAgo(n.CreatedDate);
                if (!n.Is_Read__c) result.unreadCount++;
                result.notifications.add(w);
            }
        } catch (Exception e) {
            System.debug('PortalNotificationController.getPortalNotifications error: ' + e.getMessage());
        }

        return result;
    }

    /**
     * Marks the given Portal_Notification__c IDs as read.
     */
    @AuraEnabled(cacheable=false)
    public static void markNotificationsRead(List<String> notificationIds) {
        if (notificationIds == null || notificationIds.isEmpty()) return;
        try {
            List<Portal_Notification__c> toUpdate = new List<Portal_Notification__c>();
            for (String nId : notificationIds) {
                toUpdate.add(new Portal_Notification__c(Id = nId, Is_Read__c = true));
            }
            update toUpdate;
        } catch (Exception e) {
            System.debug('PortalNotificationController.markNotificationsRead error: ' + e.getMessage());
        }
    }

    // Returns a human-friendly "time ago" string for display in the notification panel.
    private static String formatTimeAgo(Datetime dt) {
        if (dt == null) return '';
        Long diffMs   = Datetime.now().getTime() - dt.getTime();
        Long diffMin  = diffMs / 60000;
        if (diffMin  < 1)  return 'Just now';
        if (diffMin  < 60) return diffMin + 'm ago';
        Long diffHr   = diffMin / 60;
        if (diffHr   < 24) return diffHr + 'h ago';
        Long diffDays = diffHr / 24;
        if (diffDays < 7)  return diffDays + 'd ago';
        return dt.format('MMM d');
    }
}
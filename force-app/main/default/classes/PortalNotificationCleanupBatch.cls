global class PortalNotificationCleanupBatch implements Database.Batchable<SObject>, Schedulable {

    // Configurable retention (days)
    private Integer retentionDays = 30;

    global Database.QueryLocator start(Database.BatchableContext bc) {

        Datetime cutoffDate = System.now().addDays(-retentionDays);

        return Database.getQueryLocator([
            SELECT Id
            FROM Portal_Notification__c
            WHERE CreatedDate < :cutoffDate
            AND Is_Read__c = true
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Portal_Notification__c> scope) {
        if (!scope.isEmpty()) {
            delete scope;
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Portal Notification cleanup completed');
    }

    // Scheduler method
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new PortalNotificationCleanupBatch(), 200);
    }
}
global class B2CLeadImportDeleteScheduler implements Schedulable {
global void execute(SchedulableContext sc) {

        System.debug('===== Scheduled Job Triggered: B2CLeadImportDeleteBatch =====');

        B2CLeadImportDeleteBatch batch = new B2CLeadImportDeleteBatch();
        Database.executeBatch(batch, 200);
    }
}
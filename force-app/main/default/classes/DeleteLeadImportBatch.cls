global class DeleteLeadImportBatch
implements Database.Batchable<SObject> {

    global Database.QueryLocator start(
        Database.BatchableContext bc
    ) {

        return Database.getQueryLocator([
            SELECT Id
            FROM Lead_Import__c
        ]);
    }

    global void execute(
        Database.BatchableContext bc,
        List<Lead_Import__c> scope
    ) {

        Database.delete(scope, false);
    }

    global void finish(
        Database.BatchableContext bc
    ) {

        System.debug(
            'Lead Import cleanup completed.'
        );
    }
}
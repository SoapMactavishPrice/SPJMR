global class B2CLeadImportDeleteBatch 
implements Database.Batchable<sObject> {
    
    global Database.QueryLocator start(Database.BatchableContext BC) {
        String query = 'SELECT Id'+
            ' FROM Lead_Import__c WHERE Status__c = \'Complete\'';
        
        return Database.getQueryLocator(query);
    }
    
    global void execute(Database.BatchableContext BC, List<Lead_Import__c> scope) {
            try{
                delete scope;
            }
            catch(DMLException e){
                system.debug('Could not delete Lead Import Records :'+e.getMessage());
            }
    }
    
    global void finish(Database.BatchableContext bc) {
        System.debug('Deletion Complete!');
    }

}
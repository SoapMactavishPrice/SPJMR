public without sharing class LeadImportProcessBatchStarter {
	
    @AuraEnabled
    public static void startBatch(Id parentImportId){
        if(parentImportId==null ){
            return;
        }
        if(Test.isRunningTest()){
            return;
        }
        Database.Executebatch(new LeadImportProcessBatch(parentImportId),500);
    }
}
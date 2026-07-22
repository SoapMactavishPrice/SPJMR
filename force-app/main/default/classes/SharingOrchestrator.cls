public class SharingOrchestrator {

    public static void processRecordsToUpdate(List<Application__c> applicationList,
    Map<Id,Application__c>mapOldApplications) {
        if(applicationList == null || applicationList.isEmpty()){
            return;
        }

        Set<Id> appIds = new Set<Id>();
        for(Application__c app : applicationList){
            if(app.Program__c != mapOldApplications.get(app.Id).Program__c){
                appIds.add(app.Id);
            }
        }
        handleRecords('Application__c',appIds);
    }

    public static void handleRecords(String objectApiName, Set<Id> recordIds) {
      

        if (String.isBlank(objectApiName) || recordIds == null || recordIds.isEmpty()) {
            return;
        }

        GenericProgramSharingFuture.shareRecords(
    objectApiName,
    new List<Id>(recordIds)
);
    }
}
public with sharing class ImportApplications {
   @TestVisible private static Boolean forceGetBulkApiUrlExceptionInTest = false;

   @AuraEnabled
   public static string getBulkApiUrl(){
      try {
         if (Test.isRunningTest() && forceGetBulkApiUrlExceptionInTest) {
            Integer forceError = 1 / 0;
         }
         return URL.getOrgDomainUrl().toExternalForm() + '/services/data/v58.0/jobs/query';
      } catch (Exception e) {
         throw new AuraHandledException(e.getMessage());
      }
   }

   @AuraEnabled
   public static string importApplications(String csvString) {
        Batch_ApplicationStatusUpdate batch = new Batch_ApplicationStatusUpdate(csvString);
        Database.executeBatch(batch);
        return 'Success';
   }

}
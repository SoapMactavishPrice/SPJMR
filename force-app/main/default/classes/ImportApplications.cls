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
   public static Id uploadChunk(String fileName, String csvChunk, Integer chunkNumber) {
      ContentVersion cv = new ContentVersion();
      cv.Title = fileName.replace('.csv','') + '_Part_' + chunkNumber;
      cv.PathOnClient = fileName.replace('.csv','') + '_Part_' + chunkNumber + '.csv';
      cv.VersionData = Blob.valueOf(csvChunk);
      insert cv;
      return cv.Id;
   }
   

   @AuraEnabled
   public static String startImport( List<Id> contentVersionIds, Boolean notifyShortlistedApplicants, Boolean emailErrorReport) {

      if(contentVersionIds == null || contentVersionIds.isEmpty()) {
         throw new AuraHandledException(
               'No CSV chunks were uploaded.'
         );
      }

      Batch_ApplicationStatusUpdate batch = new Batch_ApplicationStatusUpdate(contentVersionIds, notifyShortlistedApplicants, emailErrorReport);
      Database.executeBatch(batch, 1);
      return 'Success';
   }

}
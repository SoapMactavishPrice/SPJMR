public with sharing class ExportApplicationsController {

    @AuraEnabled
    public static Map<String,String> getExportStatus(String jobId){
        try {
            Map<String,String> result = new Map<String,String>();
            if(jobId!=null){
                List<Export_Job__c> job = [SELECT Id,Status__c,DocumentId__c 
                FROM Export_Job__c WHERE JobId__c =:jobId LIMIT 1];
                if(!job.isEmpty()){
                     result.put('status', job[0].Status__c);

                    if (job[0].Status__c == 'Completed' && job[0].DocumentId__c != null) {
                        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
                        String link = baseUrl + '/sfc/servlet.shepherd/document/download/' + job[0].DocumentId__c;
                        result.put('downloadUrl', link);
                    }    
                                 
                }   
            }
            return result;  
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static string exportApplicationsBatch(String programCode) {
         Id jobId = Database.executeBatch(new ExportApplications(programCode), 2000);
        return jobId;
    }
}
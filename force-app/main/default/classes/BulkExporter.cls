public with sharing class BulkExporter {
    public static String JobId;

    @AuraEnabled
    public static string callBulkApi(string soql){
        try {
           BulkExporter.createBulkJob(soql);
            return 'Yes';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    

    @future(callout=true)
    public static void createBulkJob(String soqlQuery) {

        HttpRequest req = new HttpRequest();
        req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + '/services/data/v58.0/jobs/query');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');

        req.setBody(JSON.serialize(new Map<String, Object>{
            'operation' => 'query',
            'query' => 'SELECT Id FROM Account LIMIT 2'
        }));

        HttpResponse res = new Http().send(req);
        System.debug('BODY => ' + res.getBody());
        Object parsed = JSON.deserializeUntyped(res.getBody());

if (parsed instanceof List<Object>) {
    System.debug('TYPE => LIST');
} else if (parsed instanceof Map<String, Object>) {
    System.debug('TYPE => MAP');
} else {
    System.debug('TYPE => UNKNOWN');
}
        // Bulk API returns a LIST here
        List<Object> arr = (List<Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> jobObj = (Map<String, Object>) arr[0];

        JobId= (String) jobObj.get('id');
        system.debug(JobId);
    }


    @AuraEnabled
    public static Map<String, Object> checkBulkJobStatus(String jobId) {

        HttpRequest req = new HttpRequest();
        req.setEndpoint(+ '/services/data/v58.0/jobs/query/' + jobId);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());

        HttpResponse res = new Http().send(req);
        System.debug('BODY => ' + res.getBody());
        Object parsed = JSON.deserializeUntyped(res.getBody());

if (parsed instanceof List<Object>) {
    System.debug('TYPE => LIST');
} else if (parsed instanceof Map<String, Object>) {
    System.debug('TYPE => MAP');
} else {
    System.debug('TYPE => UNKNOWN');
}
        // Bulk API returns a MAP here (NOT a List!)
        Map<String, Object> status = 
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        return status;
    }


    @AuraEnabled
    public static String getResultDownloadUrl(String jobId) {
        return URL.getOrgDomainUrl().toExternalForm()
            + '/services/data/v58.0/jobs/query/' + jobId + '/results';
    }
}
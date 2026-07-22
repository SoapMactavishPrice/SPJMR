public with sharing class applicantMyCommunicationController {
    @AuraEnabled(cacheable =true)
    public static List<EmailMessage> returnEmails(String emailId){
         Map<String,EmailMessage> errorMap = new Map<String,EmailMessage>();
        try {
            List<EmailMessage> listEmails = [SELECT Id,Subject,HtmlBody,TextBody,MessageDate FROM EmailMessage WHERE ToAddress = :emailId ORDER BY CreatedDate DESC LIMIT 100];
            if(listEmails.size()>0){
                return listEmails;
            }
        } catch (Exception e) {
            
            system.debug('Error Fetching Emails: '+e.getMessage());
            return null;
            
        }
        return null;
    }
}
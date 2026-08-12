public with sharing class CommunicationsController {

    //communication service
    
    public enum CommunicationScenario {

        PROFILE_SHORTLISTED,

        INTERVIEW_SCHEDULED,

        PANEL_ASSIGNED,

        OFFER_AVAILABLE,

        OFFER_ACCEPTED,

        OFFER_WITHDRAWN,

        APPLICATION_REJECTED
    }

    public class CommunicationRequest {

        public CommunicationScenario scenario { get; set; }

        public Id programId { get; set; }

        public Id applicationId { get; set; }

        public List<Id> applicationIds { get; set; }

        public Id referenceRecordId { get; set; }

        public Map<Id, Id> applicationIdToReferenceRecordId { get; set; }

        public CommunicationOptions options { get; set; }

    }

    public class CommunicationOptions {

        public Boolean sendEmail { get; set; }

        public Boolean sendNotification { get; set; }

        public String documentIdentifier { get; set; }

    }

    public class DashboardAnnouncement {
        public CommunicationScenario scenario { get; set; }
        public String htmlContent { get; set; }
        public Integer priority { get; set; }
        public Id applicationId { get; set; }
        public Id programId { get; set; }
    }


    //reusebale methods
        public static String renderTemplate(
        String template,
        Map<String, Object> templateData
    ) {
        String rendered = template == null ? '' : template;

        if (templateData == null) {
            return rendered;
        }

        for (String key : templateData.keySet()) {
            String replacementValue = formatTemplateValue(
                templateData.get(key)
            );
            rendered = rendered.replace(
                '{{' + key + '}}',
                replacementValue
            );
            rendered = rendered.replace(
                '{' + key + '}',
                replacementValue
            );
        }

        return rendered;
    }

    private static String formatTemplateValue(Object value) {
        if (value == null) {
            return '';
        }

        if (value instanceof Date) {
            return ((Date) value).format();
        }

        if (value instanceof Datetime) {
            return ((Datetime) value).format();
        }

        if (value instanceof Time) {
            return String.valueOf(value);
        }

        return String.valueOf(value);
    }

    //interface for flow
    @InvocableMethod(label='Send Communication')
    public static void send(List<Request> requests) {

        Map<String, CommunicationRequest> groupedRequests = new Map<String, CommunicationRequest>();

        for (Request req : requests) {

            String key = req.programId + '|' + req.scenario;

            if (!groupedRequests.containsKey(key)) {
                CommunicationRequest cr = new CommunicationRequest();
                cr.scenario = CommunicationScenario.valueOf(req.scenario);
                cr.programId = req.programId;
                cr.applicationIdToReferenceRecordId = new Map<Id, Id>();

                groupedRequests.put(key, cr);
            }

            groupedRequests.get(key).applicationIdToReferenceRecordId.put(
                req.applicationId,
                req.referenceRecordId
            );
        }

        for (CommunicationRequest request : groupedRequests.values()) {
            CommunicationService.communicateInline(request);
        }
    }

    public class Request {

        @InvocableVariable(required=true)
        public String scenario;

        @InvocableVariable(required=true)
        public Id applicationId;

        @InvocableVariable
        public Id programId;

        @InvocableVariable
        public Id referenceRecordId;
    }


    //notifications

    @AuraEnabled
    public static string createNotifications(String message,String subject, String medium,List<Id> listApplicationIds){
        try {
            if(listApplicationIds.size()>0){
                List<Application__c> listApplication = [SELECT Id,Applicant__r.PersonEmail,Program__r.Program_Code__c
                FROM Application__c WHERE Id IN :listApplicationIds];
                Map<Id,String> mapAppIdToEmail = new Map<Id,String>();
                Boolean isEmail = false, isWebsite = false;
                List<CustomNotification__c> InsertlistNotifications = new List<CustomNotification__c>();
                Set<String> setEmailIds_GMP = new Set<String>();
                Map<String,String> mapEmailToProgramCode = new Map<String,String>();
                switch on medium{
                    when 'email'{
                        isEmail = true;
                    }
                    when 'website'{
                        isWebsite = true;
                    }
                    when 'both'{
                        isEmail = true;
                        isWebsite = true;
                    }
                }
                 
                    for(Application__c app : listApplication){
                        mapAppIdToEmail.put(app.Id,app.Applicant__r.PersonEmail);
                        CustomNotification__c notif = new CustomNotification__c(IsRead__c=false,
                        Message__c=!String.isBlank(message)?message:'',
                        Title__c = !String.isBlank(subject)?subject:'',
                        Recipient_Email__c = app.Applicant__r.PersonEmail);
                        
                        if(app.Applicant__r?.PersonEmail == null){
                            continue;
                        }
                        
                        mapEmailToProgramCode.put(app.Applicant__r?.PersonEmail, app.Program__r.Program_Code__c);
                        InsertlistNotifications.add(notif);
                    }

                    if(isEmail){
                        for(String emailValue: mapEmailToProgramCode.keySet()){
                            if(mapEmailToProgramCode.get(emailValue)== 'GMP'){
                                setEmailIds_GMP.add(emailValue);
                            }
                        }

                        if(!setEmailIds_GMP.isEmpty()){
                             Map<String, Object> inputs_GMP = new Map<String, Object>();
                            inputs_GMP.put('Subject', subject);
                            inputs_GMP.put('Message', Message);
                            inputs_GMP.put('SetEmailIds',setEmailIds_GMP);

                            Flow.Interview.Notification_Email_Applicant_GMP flow =
                            new Flow.Interview.Notification_Email_Applicant_GMP(inputs_GMP);
                            flow.start();
                            if(!isWebsite){
                                return 'Success';
                            }
                        }

                    }

                if(InsertlistNotifications.size()>0 && isWebsite){
                    try{
                        insert InsertlistNotifications;
                        return 'Success';
                    }
                    catch(DMLException e){
                        system.debug('Could not insert Notifications '+e.getMessage());
                    }
                }
                  
            }
            return '';
            } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    
    @AuraEnabled
    public static List<CustomNotification__c> getAllNotifications() {
        return [
            SELECT Id, Title__c, Message__c, IsRead__c, CreatedDate
            FROM CustomNotification__c
            WHERE Recipient_Email__c = :UserInfo.getUserEmail()
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled
    public static void markNotificationsRead(List<Id> notificationIds) {
        List<CustomNotification__c> updates = new List<CustomNotification__c>();

        for (Id notifId : notificationIds) {
            updates.add(new CustomNotification__c(
                Id = notifId,
                IsRead__c = true
            ));
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }
    @AuraEnabled
    public static Integer getNotificationsUnread(){
        try {
            Integer countUnreadNotifs = [SELECT COUNT()
            FROM CustomNotification__c 
            WHERE Recipient_Email__c = :UserInfo.getUserEmail() AND IsRead__c = false];
            return countUnreadNotifs;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
}
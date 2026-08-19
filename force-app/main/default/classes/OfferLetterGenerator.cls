public with sharing class OfferLetterGenerator implements Queueable, Database.AllowsCallouts {

    @AuraEnabled(cacheable=true)
    public static List<GMPApplicationWrapper> getGMPApplications() {

        List<GMPApplicationWrapper> result = new List<GMPApplicationWrapper>();

        for (Application__c app : [
            SELECT Id,
                   Name,
                   Applicant__r.Name,
                   Applicant_State_Management__c
            FROM Application__c
            WHERE Applicant_State_Management__c = 'Offer Accepted'
            AND Id NOT IN (
                SELECT Applicant__c
                FROM Account
                WHERE RecordType.DeveloperName = 'Student'
                AND Applicant__c != null
            )
            ORDER BY Applicant__r.Name
        ]) {
            GMPApplicationWrapper w = new GMPApplicationWrapper();
            w.Id = app.Id;
            w.applicationNumber = app.Name;
            w.applicantName = app.Applicant__r != null ? app.Applicant__r.Name : '';
            w.applicantStateManagement = app.Applicant_State_Management__c;
            w.applicationUrl = '/' + app.Id;
            result.add(w);
        }
        return result;
    }


    List<Admission_Decision__c> listAdmission = new List<Admission_Decision__c>();
    public OfferLetterGenerator(List<Admission_Decision__c> listAdm){
        this.listAdmission = listAdm;

    }
    public void execute(QueueableContext context) {

        // Call your existing bulk logic here
        OfferLetterGenerator.generateOfferLettersBulk(this.listAdmission);
    }

    @AuraEnabled 
public static void generateOfferLetters(List<Id> applicationIds,Date offerDate,String decision) {
    if (applicationIds == null || applicationIds.isEmpty()) {
        return;
    }
    List<Admission_Decision__c> admList = new List<Admission_Decision__c>();
    for(Id appId:applicationIds){
        Admission_Decision__c adm = new Admission_Decision__c(Application__c = appId,
        Result__c =decision ,Offer_Letter_Date__c = offerDate);
        admList.add(adm);
    }
    if(admList.size()>0){
        try{
            insert admList;
            system.debug('Offer Created Success');
            // AdmissionDecisionTriggerHandler enqueues OfferLetterGeneratorBulk.
        }catch(Exception e){
            System.debug('Exception while inserting Admission Decisions '+e.getMessage());
        
    }
}
   
}

 

    public class GMPApplicationWrapper{
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String applicantName;
        @AuraEnabled public String applicantStateManagement;
        @AuraEnabled public String Id;
        @AuraEnabled public String applicationUrl;
        @AuraEnabled public String evaluationScore;
    }

    @AuraEnabled(cacheable=true)
    public static List<GMPApplicationWrapper> getShortlistedApplicantsGMP(){
        try {
            List<Application__c> applicationList =  [SELECT Id,Name,
            Applicant__r.Name,Evaluation_Score__c,
            Applicant_State_Management__c,Application_Status__c,
            (SELECT Id,(SELECT Id FROM Round_Results__r) FROM ApplicationSlotBookings__r)
            FROM Application__c 
            WHERE Program__r.Program_Code__c = 'GMP'  
            AND
            (Applicant_State_Management__c = 'Interview Round 1' OR 
            Applicant_State_Management__c = 'Interview Round 2' 
            OR Applicant_State_Management__c = 'Profile Shortlisted') 
            AND Applicant_State_Management__c <> 'Disqualified'
            ORDER BY Evaluation_Score__c DESC];

        List<GMPApplicationWrapper> returnList = new List<GMPApplicationWrapper>();
        if(!applicationList.isEmpty()){
            for(Application__c app:applicationList){
                // if(app.ApplicationSlotBookings__r.isEmpty()){
                //     continue;
                // }
                // else{
                //     for(ApplicationSlotBooking__c appSlot:app.ApplicationSlotBookings__r){
                //         if(appSlot.Round_Results__r.isEmpty()){
                //             continue;
                //         }
                //     }
                // }

                GMPApplicationWrapper wrapper = new GMPApplicationWrapper();
                wrapper.applicationNumber = app.Name;
                wrapper.applicantName = app?.Applicant__r.Name;
                wrapper.applicantStateManagement = app.Applicant_State_Management__c;
                wrapper.Id = app.Id;
                wrapper.applicationUrl = URL.getOrgDomainURL().toExternalForm() +'/'+app.Id;
                wrapper.evaluationScore = String.valueOf(app.Evaluation_Score__c);
                returnList.add(wrapper);
            }
            if(!returnList.isEmpty()){
                return returnList;
            }
        }
        return null;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static void sendOfferNotification(String admId){
        if(!String.isBlank(admId)){
            List<Admission_Decision__c> admList = [SELECT Id,Application__c 
            FROM Admission_Decision__c WHERE Id=:admId LIMIT 1];
            if(admList.isEmpty() || admList[0].Application__c == null){
                return;
            }

            List<Application__c> listApplication = [SELECT Id,Applicant__r.PersonEmail  FROM Application__c WHERE Id=:admList[0].Application__c LIMIT 1];
            if(listApplication.isEmpty() || String.isBlank(listApplication[0].Applicant__r.PersonEmail)){
                return;
            }
                CustomNotification__c notification = new CustomNotification__c(Recipient_Email__c =listApplication[0].Applicant__r.PersonEmail,
                Message__c = 'Offer Letter has been Issued',Title__c='Offer Letter Issued',IsRead__c = false );
                try{
                    insert notification;
                    
                    List<User> applicantUser = [SELECT Id FROM User 
                    WHERE Email =:listApplication[0].Applicant__r.PersonEmail
                    AND IsActive=true LIMIT 1];

                    CustomNotification__share notifShare = new CustomNotification__share(
                        ParentId = notification.Id,
                        UserOrGroupId = applicantUser[0].Id,
                        RowCause = Schema.CustomNotification__share.RowCause.Manual,
                        AccessLevel = 'Read'
                    );

                    insert notifShare;
                }
                catch(DMLException e){
                    system.debug('Could not insert Notification for Offer Letter'+e.getMessage());
                }
    }
}

private static void sendOfferNotificationBulk(Set<Id> applId){
    if(applId == null || applId.isEmpty()) return;

    List<Application__c> listApplication = [
        SELECT Id, Applicant__r.PersonEmail
        FROM Application__c
        WHERE Id IN :applId
    ];

    List<CustomNotification__c> customNotifList = new List<CustomNotification__c>();

    for(Application__c app : listApplication){
        if(String.isBlank(app.Applicant__r.PersonEmail)) continue;

        customNotifList.add(new CustomNotification__c(
            Recipient_Email__c = app.Applicant__r.PersonEmail,
            Message__c = 'Offer Letter has been Issued',
            Title__c = 'Offer Letter Issued',
            IsRead__c = false
        ));
    }

    if(!customNotifList.isEmpty()){
        insert customNotifList;
    }
}
    


    
private static void updateApplicationStateBulk(Set<Id> applId){
    if(applId == null || applId.isEmpty()) return;

    List<Application__c> listApplication = [
        SELECT Id
        FROM Application__c
        WHERE Id IN :applId
    ];

    for(Application__c app : listApplication){
        app.Applicant_State_Management__c = 'Offer Issued';
    }

    update listApplication;
}


    private static void updateApplicationState(String admId){
        if(!String.isBlank(admId)){
            List<Admission_Decision__c> admList = [SELECT Id,Application__c FROM Admission_Decision__c WHERE Id=:admId LIMIT 1];
            String applicationId = admList[0].Application__c;
            List<Application__c>  listApplication = [
        SELECT Id, Applicant_State_Management__c
        FROM Application__c
        WHERE Id = :admList[0].Application__c
        LIMIT 1
    ];
                listApplication[0].Applicant_State_Management__c = 'Offer Issued';
                try{
                    update listApplication;
                }
                catch(DMLException e){
                    system.debug('Could not update Application State from Admission Decision - Offer Letter Issued '+e.getMessage());
                }
        }
    }


    @AuraEnabled
    public static void invokeSendEmailFlow(String admId){
        try {
            Map<String, Object> inputs = new Map<String, Object>();
            inputs.put('admissionId', admId);
            Flow.Interview myFlow = Flow.Interview.createInterview('Send_Offer_Letter_to_Applicant_Autolaunched', inputs);
            myFlow.start();
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled 
    public static void generateOfferLettersBulk(List<Admission_Decision__c> listAdm){
        
        try {
            system.debug(listAdm +' is the list of ADms');
            Set<Id> setAdmissionId = new Set<Id>();
            Set<Id> applicationIds_OfferLetter = new Set<Id>();
            Set<Id> applicationIds = new Set<Id>();
            List<ContentVersion> contentVersionList = new List<ContentVersion>();
            for(Admission_Decision__c adm:listAdm){ 
                setAdmissionId.add(adm.Id);
            }
            system.debug('Admisison Ids are '+setAdmissionId);
                List<Admission_Decision__c> listDecision = [SELECT Id,Application__r.Applicant__r.Name,
                Application__r.Program__r.Program_Code__c ,Application__c,Result__c
                FROM Admission_Decision__c 
                WHERE Id IN :setAdmissionId LIMIT 1];
                system.debug('List of Decisions are '+listDecision);
            for(Admission_Decision__c adm:listDecision){
                Blob pdfBlob;
                applicationIds.add(adm.Application__c);
                if(adm.Result__c == 'Eligible for Admission'){
                    
                    applicationIds_OfferLetter.add(adm.Application__c);
                }
                String pgmCode = adm.Application__r.Program__r.Program_Code__c;
                Switch on pgmCode {
                when 'GMP' {
                     PageReference page = Page.GenerateOfferLetter_GMP;
                     page.getParameters().put('admissionId',adm.Id);
                     pdfBlob = page.getContentAsPDF();
                    
                }
                when else{
                     PageReference page = Page.GenerateOfferLetter;
                     page.getParameters().put('admissionId',adm.Id);
                        pdfBlob = page.getContentAsPDF();
                    
                } 
        }
    
   
        ContentVersion contentVersion = new ContentVersion();
        contentVersion.ContentLocation = 'S'; 
        contentVersion.PathOnClient = listDecision.isEmpty()?'Offer Letter.pdf': 'Offer Letter -'+adm.Application__r.Applicant__r.Name +'.pdf';
        contentVersion.Title = listDecision.isEmpty()?'Offer Letter.pdf': 'Offer Letter -'+adm.Application__r.Applicant__r.Name +'.pdf';
        contentVersion.VersionData = pdfBlob;
        contentVersion.AdmissionId__c = adm.Id;
            contentVersionList.add(contentVersion);
        //insert contentVersion;
        
    }
    insert contentVersionList;
    Set<Id> contentVersionIds = new Set<Id>();
    Map<Id,Id> mapContentVersionToAdm = new Map<Id,Id>();
    List<ContentDistribution> ContentDistributionList = new List<ContentDistribution>();
    List<ContentDocumentLink> ContentDocumentLinkList = new List<ContentDocumentLink>();
    system.debug(contentVersionIds);
    for(ContentVersion contentVersion:contentVersionList){
        contentVersionIds.add(contentVersion.Id);
        
    }
    system.debug(contentVersionIds+' are con version Ids');
        List<ContentVersion> contentDocVersions = [SELECT Id,ContentDocumentId,ContentDocument.Title,VersionDataUrl,AdmissionId__c 
        FROM ContentVersion WHERE Id IN :contentVersionIds];
        for(ContentVersion cv:contentDocVersions){
            ContentDocumentLink contentDocumentLink = new ContentDocumentLink();
            contentDocumentLink.ContentDocumentId = cv.ContentDocumentId;
            contentDocumentLink.LinkedEntityId = cv.AdmissionId__c;
            contentDocumentLink.ShareType = 'I'; // Inferred permission
            contentDocumentLink.Visibility = 'AllUsers';
            String docTitle = cv.ContentDocument.Title;
            
            ContentDistribution cdist = new ContentDistribution(
                    Name = !String.isBlank(docTitle)?docTitle:'Offer Letter.pdf',
                    ContentVersionId = cv.Id
                );
                ContentDistributionList.add(cdist);
                ContentDocumentLinkList.add(contentDocumentLink);
        }
        

                try{
                    insert ContentDistributionList; 
                    Insert ContentDocumentLinkList;
                    if(applicationIds.size()>0){
                    updateApplicationStateBulk(applicationIds_OfferLetter);
                    sendOfferNotificationBulk(applicationIds);
                    }
                    
                    
                    //return '/lightning/page/filePreview?selectedRecordId='+contentDocVersions[0].ContentDocumentId;
                }
                catch(DMLException e){
                    system.debug('Could not insert doc Link '+e.getMessage());
                }
            
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
}

    @AuraEnabled
    public static string generateOffer(String admId){
        try {
            List<Admission_Decision__c> listDecision = [SELECT Application__r.Applicant__r.Name,
            Application__r.Program__r.Program_Code__c 
        FROM Admission_Decision__c 
        WHERE Id=:admId LIMIT 1];
           
            
        Blob pdfBlob;
        if(!listDecision.isEmpty()){
            String pgmCode = listDecision[0].Application__r.Program__r.Program_Code__c;
            Switch on pgmCode {
                when 'GMP' {
                     PageReference page = Page.GenerateOfferLetter_GMP;
                     page.getParameters().put('admissionId',admId);
                    pdfBlob = page.getContentAsPDF();
                    
                }
                when else{
                     PageReference page = Page.GenerateOfferLetter;
                     page.getParameters().put('admissionId',admId);
                        pdfBlob = page.getContentAsPDF();
                    
                } 
        }
    
   // page.getParameters().put('admissionId',admId);
        ContentVersion contentVersion = new ContentVersion();
    contentVersion.ContentLocation = 'S'; 
    contentVersion.PathOnClient = listDecision.isEmpty()?'Offer Letter.pdf': 'Offer Letter -'+listDecision[0].Application__r.Applicant__r.Name +'.pdf';
    contentVersion.Title = listDecision.isEmpty()?'Offer Letter.pdf': 'Offer Letter -'+listDecision[0].Application__r.Applicant__r.Name +'.pdf';
    contentVersion.VersionData = pdfBlob;
        
        insert contentVersion;
        List<ContentVersion> contentDocVersions = [SELECT ContentDocumentId,ContentDocument.Title,VersionDataUrl 
        FROM ContentVersion WHERE Id = :contentVersion.Id LIMIT 1];
        ContentDocumentLink contentDocumentLink = new ContentDocumentLink();
    contentDocumentLink.ContentDocumentId = contentDocVersions[0].ContentDocumentId;
    contentDocumentLink.LinkedEntityId = admId;
    contentDocumentLink.ShareType = 'I'; // Inferred permission
    contentDocumentLink.Visibility = 'AllUsers';
    String docTitle = contentDocVersions[0].ContentDocument.Title;
    
    ContentDistribution cdist = new ContentDistribution(
                    Name = !String.isBlank(docTitle)?docTitle:'Offer Letter.pdf',
                    ContentVersionId = contentVersion.Id
                );

    try{
         insert contentDocumentLink; 
         Insert cdist;
         updateApplicationState(admId);
         sendOfferNotification(admId);
        
         return '/lightning/page/filePreview?selectedRecordId='+contentDocVersions[0].ContentDocumentId;
    }
    catch(DMLException e){
        system.debug('Could not insert doc Link '+e.getMessage());
    }
       
       
}
    return '';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
}
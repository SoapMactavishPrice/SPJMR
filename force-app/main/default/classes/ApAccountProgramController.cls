public without sharing class ApAccountProgramController {

    @AuraEnabled 
    public static List<String> checkUserValidity(){
        try {
            List<String> returnList = new List<String>();
            String userEmail = UserInfo.getUserEmail();
            List<Account> listAccounts = [SELECT Id, 
            (SELECT Id FROM Applications__r) FROM Account
            WHERE PersonEmail=:userEmail LIMIT 1];
            if(listAccounts.size()>0){
                for(Application__c app:listAccounts[0]?.Applications__r){
                    returnList.add(app.Id);
                }
                return returnList;
            }
            return new List<String>();

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
public static String getApplicationStage(Id applicationId) {
    return [
        SELECT ToLabel(Application_Stage__c)
        FROM Application__c
        WHERE Id = :applicationId
        LIMIT 1
    ].Application_Stage__c;
}


    @AuraEnabled
    public static String deleteDocument(String contentDocumentId,String entity){
        if(String.isEmpty(contentDocumentId) || String.isEmpty(entity)){
            return '';
        }
        switch on entity{
            when 'Offer'{
                List<ContentDocument> contentDocList = [SELECT Id FROM ContentDocument
                WHERE Id=:contentDocumentId];
                if(!contentDocList.isEmpty()){
                    try{
                        delete contentDocList;
                        return 'Offer';
                    }
                    catch(DMLException e){
                        system.debug('Could not delete Offer Letter '+e.getMessage());
                    }
                }
            }
            when 'Acceptance'{
                List<ContentDocument> contentDocList = [SELECT Id FROM ContentDocument
                WHERE Id=:contentDocumentId];
                
                if(!contentDocList.isEmpty()){
                    try{
                        delete contentDocList;
                        return 'Acceptance';
                    }
                    catch(DMLException e){
                        system.debug('Could not delete Offer Letter '+e.getMessage());
                    }
                }
            }
        }
        return '';
    }
    
    @AuraEnabled
    public static Boolean getDistributionUrl(String contentVersionId,String entity){
        ContentDistribution cdist = new ContentDistribution(
            Name=entity,
        ContentVersionId = contentVersionId
            );
        try{
            insert cdist;
            return true;
        }
        catch(DmlException e){
            system.debug('Error while inserting content Distribution record for '+entity+
                ' '+e.getMessage() );
        }
        return false;
    }
    
    @AuraEnabled(cacheable=false)
    public static String getAcceptanceLetterFileUrl(Id applicationId) {
        try {
            return getDocumentDetailFileUrl(applicationId, 'AcceptanceLetter');
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static String getOfferLetterFileUrl(Id admissionId) {
        if (admissionId == null) return '';
        List<ContentDocumentLink> offerLetters = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :admissionId LIMIT 1];
        if (offerLetters.isEmpty()) return '';
        List<ContentDistribution> cdList = [SELECT DistributionPublicUrl FROM ContentDistribution WHERE ContentDocumentId = :offerLetters[0].ContentDocumentId ORDER BY CreatedDate DESC LIMIT 1];
        if (!cdList.isEmpty()) return cdList[0].DistributionPublicUrl;
        return '';
    }

    public class OfferUploadConfigWrapper {
        @AuraEnabled public Boolean showUploadOfferDocuments;
        @AuraEnabled public Boolean showUploadAcceptDocuments;
    }

    @AuraEnabled(cacheable=true)
    public static OfferUploadConfigWrapper getOfferUploadConfig(String programCode) {
        OfferUploadConfigWrapper cfg = new OfferUploadConfigWrapper();
        cfg.showUploadOfferDocuments = false;
        cfg.showUploadAcceptDocuments = false;

        if (String.isBlank(programCode)) {
            return cfg;
        }

        List<Program_Document__mdt> records = [
            SELECT ShowOfferDocumentUpload__c, ShowAcceptanceDocumentUpload__c
            FROM Program_Document__mdt
            WHERE Program_Code__c = :programCode
            LIMIT 1
        ];

        if (!records.isEmpty()) {
            cfg.showUploadOfferDocuments = records[0].ShowOfferDocumentUpload__c;
            cfg.showUploadAcceptDocuments = records[0].ShowAcceptanceDocumentUpload__c;
        }

        return cfg;
    }

    @AuraEnabled
    public static Map<String,String> checkUploadedDocuments(String applicationId){
        Map<String,String> resultMap = new Map<String,String>();
        resultMap.put('acceptanceLetter','false');
        resultMap.put('offerLetter','false');

        if (String.isBlank(applicationId)) {
            return resultMap;
        }

        List<Document_Details__c> docDetails = [
            SELECT Id, Document_Code__c
            FROM Document_Details__c
            WHERE Application_No__c = :applicationId
            AND Document_Code__c IN ('SignedOfferLetter', 'SignedAcceptanceLetter')
        ];

        Map<Id, String> docDetailToCode = new Map<Id, String>();
        for (Document_Details__c docDetail : docDetails) {
            docDetailToCode.put(docDetail.Id, docDetail.Document_Code__c);
        }

        if (docDetailToCode.isEmpty()) {
            return resultMap;
        }

        Map<Id, Id> contentDocumentToDetail = new Map<Id, Id>();
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :docDetailToCode.keySet()
        ]) {
            contentDocumentToDetail.put(link.ContentDocumentId, link.LinkedEntityId);
        }

        if (contentDocumentToDetail.isEmpty()) {
            return resultMap;
        }

        for (ContentDistribution cdl : [
            SELECT ContentVersion.Title, DistributionPublicUrl, ContentDocumentId
            FROM ContentDistribution
            WHERE ContentDocumentId IN :contentDocumentToDetail.keySet()
            ORDER BY CreatedDate DESC
        ]) {
            String docCode = docDetailToCode.get(contentDocumentToDetail.get(cdl.ContentDocumentId));

            if (docCode == 'SignedOfferLetter' && resultMap.get('offerLetter') != 'true') {
                resultMap.put('offerLetter', 'true');
                resultMap.put('offerLetterUrl', cdl.DistributionPublicUrl);
                resultMap.put('offerLetterId', cdl.ContentDocumentId);
            }
            if (docCode == 'SignedAcceptanceLetter' && resultMap.get('acceptanceLetter') != 'true') {
                resultMap.put('acceptanceLetter', 'true');
                resultMap.put('acceptanceLetterId', cdl.ContentDocumentId);
                resultMap.put('acceptanceLetterUrl', cdl.DistributionPublicUrl);
            }
        }

        return resultMap;
    }

    @AuraEnabled
    public static void linkDocumentDetails(Id applicationId, Id contentDocumentId, String docCode, Id contentVersionId) {
        try {
            if (applicationId == null || String.isBlank(docCode)) {
                throw new AuraHandledException('Missing required parameters');
            }

            if (contentDocumentId == null && contentVersionId != null) {
                List<ContentVersion> versions = [
                    SELECT ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :contentVersionId
                    LIMIT 1
                ];
                if (!versions.isEmpty()) {
                    contentDocumentId = versions[0].ContentDocumentId;
                }
            }

            if (contentDocumentId == null) {
                throw new AuraHandledException('Missing uploaded file document id');
            }

            Document_Details__c docDetail = ensureDocumentDetail(applicationId, docCode);

            List<ContentDocumentLink> existingLinks = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :docDetail.Id
                AND ContentDocumentId = :contentDocumentId
                LIMIT 1
            ];

            if (existingLinks.isEmpty()) {
                insert new ContentDocumentLink(
                    LinkedEntityId = docDetail.Id,
                    ContentDocumentId = contentDocumentId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                );
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    
    public class admissionDecision{
        @AuraEnabled public string ProgramName;
        @AuraEnabled public string offerLetterLink;
        @AuraEnabled public string admissionDecisionId;
        @AuraEnabled public string contentDocId;
        @AuraEnabled public string applicationId;
        @AuraEnabled public string offerAccepted;
        @AuraEnabled public string offerDeclined;
        @AuraEnabled public string isOfferWithdrawn;
        @AuraEnabled public Boolean hasPendingDocuments;
    }
    
    @AuraEnabled
    public static Object getEligibleAdmissionDecisions(){
        try {
            String networkId, urlPathPrefix;
            List<Network> networks = [
                                SELECT Id, UrlPathPrefix
                                FROM Network
                                WHERE Name = 'Application Portal'
                                LIMIT 1
                            ];
            if (!networks.isEmpty()) {
                networkId = networks[0].Id;
                urlPathPrefix = networks[0].UrlPathPrefix;
            }
            
            String homePageUrl = Network.getLoginUrl(networkId);
            if (homePageUrl.endsWith('/s/login')) {
                homePageUrl = homePageUrl.substring(0, homePageUrl.length() - 7);
            }
            
            List<admissionDecision> result = new List<admissionDecision>();
            List<Account> accts = [SELECT Id,
            (SELECT Id,Program__r.Name,Program_Code__c,Applicant_State_Management__c,
            (SELECT Id,Result__c,Offer_Accepted__c,Offer_Declined__c
             FROM Admission_Decisions__r WHERE Result__c = 'Eligible for Admission') 
            FROM Applications__r)
            FROM Account 
            WHERE PersonEmail = :UserInfo.getUserEmail() LIMIT 1
            ];
            Set<Id> admissionDecisionIds = new Set<Id>();
            Map<Id,Id> mapAdmissionToOffer = new Map<Id,Id>();
            Map<Id,Id> mapOfferToAdmission = new Map<Id,Id>();
            Map<Id,String> mapAdmissionToPublicUrl = new  Map<Id,String>();
            List<Application__c> listApplications = new List<Application__c>();
            if(accts.size()>0){
                Set<String> pgmCodes = new Set<String>();
                Set<Id> appIds = new Set<Id>();
                for(Account acc: accts){
                    if(acc?.Applications__r.size()>0){
                        listApplications = acc.Applications__r;
                        for(Application__c app:acc.Applications__r){
                            appIds.add(app.Id);
                            if(String.isNotBlank(app.Program_Code__c)){
                                pgmCodes.add(app.Program_Code__c);
                            }
                            if(app?.Admission_Decisions__r.size()>0){
                                for(Admission_Decision__c adm:app.Admission_Decisions__r){
                                    admissionDecisionIds.add(adm.Id);
                                }
                            }
                        }
                    }
                }
                
                // Bulk query config & uploaded document details
                Map<String, Program_Document__mdt> pgmDocConfigMap = new Map<String, Program_Document__mdt>();
                if(!pgmCodes.isEmpty()){
                    for(Program_Document__mdt pd : [SELECT Program_Code__c, ShowOfferDocumentUpload__c, ShowAcceptanceDocumentUpload__c FROM Program_Document__mdt WHERE Program_Code__c IN :pgmCodes]){
                        pgmDocConfigMap.put(pd.Program_Code__c, pd);
                    }
                }
                
                Map<Id, Set<String>> uploadedDocCodesByAppId = new Map<Id, Set<String>>();
                if(!appIds.isEmpty()){
                    List<Document_Details__c> uploadedDocs = [SELECT Application_No__c, Document_Code__c, Id FROM Document_Details__c WHERE Application_No__c IN :appIds AND Document_Code__c IN ('SignedOfferLetter', 'SignedAcceptanceLetter')];
                    if(!uploadedDocs.isEmpty()){
                        Set<Id> ddIds = new Set<Id>();
                        Map<Id, Id> ddToApp = new Map<Id, Id>();
                        Map<Id, String> ddToCode = new Map<Id, String>();
                        for(Document_Details__c dd : uploadedDocs){
                            ddIds.add(dd.Id);
                            ddToApp.put(dd.Id, dd.Application_No__c);
                            ddToCode.put(dd.Id, dd.Document_Code__c);
                        }
                        for(ContentDocumentLink cdl : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :ddIds]){
                            Id appId = ddToApp.get(cdl.LinkedEntityId);
                            String code = ddToCode.get(cdl.LinkedEntityId);
                            if(!uploadedDocCodesByAppId.containsKey(appId)){
                                uploadedDocCodesByAppId.put(appId, new Set<String>());
                            }
                            uploadedDocCodesByAppId.get(appId).add(code);
                        }
                    }
                }

                Set<Id> appsWithAcceptanceLetter = new Set<Id>();
                if(!appIds.isEmpty()){
                    List<Document_Details__c> accLetterDocs = [SELECT Application_No__c, Id FROM Document_Details__c WHERE Application_No__c IN :appIds AND Document_Code__c = 'AcceptanceLetter'];
                    if(!accLetterDocs.isEmpty()){
                        Set<Id> accDocIds = new Set<Id>();
                        Map<Id, Id> accDocToApp = new Map<Id, Id>();
                        for(Document_Details__c dd : accLetterDocs){
                            accDocIds.add(dd.Id);
                            accDocToApp.put(dd.Id, dd.Application_No__c);
                        }
                        for(ContentDocumentLink cdl : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :accDocIds]){
                            appsWithAcceptanceLetter.add(accDocToApp.get(cdl.LinkedEntityId));
                        }
                    }
                }

                if(admissionDecisionIds.size()>0){
                    List<ContentDocumentLink> offerLetters = [SELECT Id,LinkedEntityId,ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :admissionDecisionIds ];
                    
                    if(!offerLetters.isEmpty()){
                        
                        for(ContentDocumentLink link:offerLetters){
                            mapAdmissionToOffer.put(link.LinkedEntityId,link.ContentDocumentId);
                            mapOfferToAdmission.put(link.ContentDocumentId,link.LinkedEntityId);
                        }
                    }
                    
                    List<ContentDistribution> contentDistributionLinks = [SELECT Id,DistributionPublicUrl,ContentDocumentId FROM ContentDistribution WHERE ContentDocumentId IN:mapAdmissionToOffer.values()];
                    for(ContentDistribution link:contentDistributionLinks){
                        mapAdmissionToPublicUrl.put(mapOfferToAdmission.get(link.ContentDocumentId),link.DistributionPublicUrl);
                    }
                    for(Application__c app:listApplications){
                        if(app?.Admission_Decisions__r.size()>0){
                            for(Admission_Decision__c adm:app.Admission_Decisions__r){
                                admissionDecision res = new admissionDecision();
                                res.ProgramName = app.Program__r.Name;
                                res.applicationId = app.Id;
                                res.isOfferWithdrawn = String.valueOf(app.Applicant_State_Management__c=='Withdrawn');
                                res.offerLetterLink = mapAdmissionToPublicUrl.get(adm.Id);
                                res.admissionDecisionId = adm.Id;
                                res.offerAccepted = String.valueOf(adm.Offer_Accepted__c);
                                res.offerDeclined = String.valueOf(adm.Offer_Declined__c);
                                res.contentDocId = mapAdmissionToOffer.get(adm.Id);

                                Boolean isAcc = (adm.Offer_Accepted__c == true);
                                Boolean hasPending = false;
                                if (isAcc) {
                                    Program_Document__mdt cfg = pgmDocConfigMap.get(app.Program_Code__c);
                                    Set<String> uploadedCodes = uploadedDocCodesByAppId.containsKey(app.Id) ? uploadedDocCodesByAppId.get(app.Id) : new Set<String>();
                                    Boolean hasOfferLetterDoc = String.isNotBlank(mapAdmissionToPublicUrl.get(adm.Id));
                                    Boolean showOfferUpload = (cfg != null && cfg.ShowOfferDocumentUpload__c == true && hasOfferLetterDoc);
                                    Boolean showAcceptUpload = (cfg != null && cfg.ShowAcceptanceDocumentUpload__c == true && appsWithAcceptanceLetter.contains(app.Id));

                                    Boolean offerMissing = showOfferUpload && !uploadedCodes.contains('SignedOfferLetter');
                                    Boolean acceptMissing = showAcceptUpload && !uploadedCodes.contains('SignedAcceptanceLetter');
                                    hasPending = offerMissing || acceptMissing;
                                }
                                res.hasPendingDocuments = hasPending;

                                result.add(res);
                            }
                        }
                        
                    }
                    if(result.size()>0){
                        String jsonResult = JSON.serialize(result);
                        return JSON.deserializeUntyped(jsonResult);
                    }
                }
            }
            return '';
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static string isDecisionPresent(){
        try {
            List<Account> accts = [SELECT Id,
            (SELECT Id,
            (SELECT Id,Result__c FROM Admission_Decisions__r) FROM Applications__r)
            FROM Account 
            WHERE PersonEmail = :UserInfo.getUserEmail() LIMIT 1
            ];
            if(accts.size()>0){
                for(Account acc: accts){
                    if(acc?.Applications__r.size()>0){
                        for(Application__c app:acc.Applications__r){
                            if(app?.Admission_Decisions__r.size()>0){
                                for(Admission_Decision__c adm:app.Admission_Decisions__r){
                                    if(adm.Result__c == 'Eligible for Admission'){
                                        return 'Yes';
                                    }
                                }
                            }
                        }
                    }
                }
            }
            return 'No';
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ProgramDocumentWrapper getProgramSpecificDocuments(String admissionId) {
        try {
            List<Admission_Decision__c> admList = [
                SELECT Id, Application__r.Program__r.Program_Code__c
                FROM Admission_Decision__c
                WHERE Id = :admissionId
                LIMIT 1
            ];

            if (admList.isEmpty()) {
                return null;
            }

            String pgmCode = admList[0].Application__r.Program__r.Program_Code__c;

            List<Program_Document__mdt> pgmMetadataList = [
                SELECT Id, Program_Code__c, Acceptance_Letter__c,
                       (SELECT Id, Annexure_Name__c, Annexure_URL__c, Display_Order__c
                        FROM Program_Annexures__r
                        ORDER BY Display_Order__c ASC)
                FROM Program_Document__mdt
                WHERE Program_Code__c = :pgmCode
                LIMIT 1
            ];

            if (pgmMetadataList.isEmpty()) {
                return null;
            }

            Program_Document__mdt pgmMetadata = pgmMetadataList[0];

            ProgramDocumentWrapper result = new ProgramDocumentWrapper();
            result.programCode = pgmMetadata.Program_Code__c;
            result.acceptanceLetterUrl = pgmMetadata.Acceptance_Letter__c;
            result.annexures = new List<AnnexureWrapper>();

            for (Program_Annexure__mdt ann : pgmMetadata.Program_Annexures__r) {
                AnnexureWrapper aw = new AnnexureWrapper();
                aw.annexureName = ann.Annexure_Name__c;
                aw.annexureUrl = ann.Annexure_URL__c;
                aw.displayOrder = ann.Display_Order__c;
                result.annexures.add(aw);
            }

            return result;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<AccountProgramApplicationWrapper> getProgramsForLoggedInUser() {
        // 1) Get logged-in user email
        String userEmail = UserInfo.getUserEmail();
        if (String.isBlank(userEmail)) return new List<AccountProgramApplicationWrapper>();
        
        Id accountId;
        
        // 2) Check if logged-in user is a Person Account
        List<Account> personAccts = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonEmail = :userEmail
            LIMIT 1
        ];
        
        if (!personAccts.isEmpty()) {
            accountId = personAccts[0].Id;
        }
        
        // 3) Fallback: Contact under Business Account
        if (accountId == null) {
            List<Contact> contacts = [
                SELECT AccountId
                FROM Contact
                WHERE Email = :userEmail
                AND AccountId != null
                LIMIT 1
            ];
            if (!contacts.isEmpty()) {
                accountId = contacts[0].AccountId;
            }
        }
        
        return getApplicationApbsList(accountId);
    }

    @AuraEnabled(cacheable=true)
    public static Object getDashboardAnnouncementsForApplication(
        Id applicationId
    ) {
        try {
            List<CommunicationsController.DashboardAnnouncement> announcements =
                DashboardAnnouncementService.getAnnouncements(applicationId);

            return JSON.deserializeUntyped(
                JSON.serialize(announcements)
            );
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    public class AccountProgramApplicationWrapper {
        @AuraEnabled public Id applicationId;
        @AuraEnabled public Id programId;
        @AuraEnabled public String programName;
        @AuraEnabled public String programCode;
        @AuraEnabled public String applicationStatus;
        @AuraEnabled public String applicationStage;
        @AuraEnabled public String applicationName;
        @AuraEnabled public String applicationAcceptanceStatus = 'Open';
        @AuraEnabled public Boolean allowSchedule;//will be set to true when status is open, Application_c.AllowSelfSchedule__c is true, and no existing active bookings for the application
        @AuraEnabled public Map<String,Object> bookingInfo;
        @AuraEnabled public Boolean isScheduled;
        @AuraEnabled public Boolean isRound1;
        @AuraEnabled public Boolean isDecisionPresent;
        @AuraEnabled public String applicantName;
        @AuraEnabled public Integer countBookings;
        @AuraEnabled public Boolean isRejected;
        @AuraEnabled public String applyString;
        @AuraEnabled public String assignmentStatus;
        public AccountProgramApplicationWrapper(Id id, String name, String code) {
            programId = id;
            programName = name;
            programCode = code;
        }
        
        public AccountProgramApplicationWrapper(Id id, String name, String code, 
        String status, String stage, String appName, Boolean allowSchedule, 
        Map<String,Object> bookingInfo,Boolean isScheduled,
        Boolean isRound1,Boolean isDecision,String applicantName,Integer countBookings,
        String appId,Boolean isRejected,String applyString,String assignmentStatus) {
            programId = id;
            programName = name;
            programCode = code;
            applicationStatus = status;
            applicationStage = stage;
            applicationName = appName;
            this.allowSchedule = allowSchedule;
            this.bookingInfo = bookingInfo;
            this.isScheduled = isScheduled;
            this.isRound1 = isRound1;
            this.isDecisionPresent = isDecision;
            this.applicantName=applicantName;
            this.countBookings = countBookings;
            this.applicationId = appId;
            this.isRejected = isRejected;
            this.applyString = applyString;
            this.assignmentStatus = assignmentStatus;
        }
    }
    
    private static List<AccountProgramApplicationWrapper> getApplicationApbsList(Id accountId){
        if (accountId == null) return new List<AccountProgramApplicationWrapper>();
        
        List<String> bookingStates = new List<String>{'Confirmed', 'Cancelled'};
        
        // 1) Query Account with child Program Batch Selections and Applications
        List<Account> accts = [
            SELECT Name,
             
                    (SELECT Id, (SELECT Id,Result__c FROM Admission_Decisions__r  LIMIT 1),
                    (SELECT Id,Net_Score__c,Application__c FROM Round_Results__r),
                    (SELECT BookingState__c, SlotMaster__r.SlotDate__c, SlotMaster__r.LocationMaster__r.AddressInformation__c,
                    format(SlotMaster__r.SlotStartTime__c), format(SlotMaster__r.SlotEndTime__c) 
                    FROM ApplicationSlotBookings__r 
                     WHERE //BookingState__c NOT IN :bookingStates 
                     Slot_Date__c >= TODAY  ORDER BY Slot_Date__c ASC ), Application_Number__c,
                           Program__r.Id,
                           Program__r.Name,
                           Program__r.Program_Code__c,
                           toLabel(Application_Status__c),
                           toLabel(Application_Stage__c),Assignment_Status__c,Name,
                           AllowSelfSchedule__c,Applicant_State_Management__c
                    FROM Applications__r 
                    ORDER BY CreatedDate DESC
                    LIMIT 100
                    )
                    
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        
        Set<Id> programIdSet = new Set<Id>();
        Set<Id> paidProgramsId = new Set<Id>();
        List<AccountProgramApplicationWrapper> results = new List<AccountProgramApplicationWrapper>();
        
        if(accts.isEmpty()) {
            return results;
        }
        String applicantName = accts[0].Name;
        
        Map<Id,AccountProgramApplicationWrapper> apbsMap = new Map<Id,AccountProgramApplicationWrapper>();
        
        for (Application__c sel : accts[0].Applications__r) {
            System.debug('sel.Application__c: ' + sel);
            Id appId = sel.Id;
            
            if (sel.Program__r != null) {
                programIdSet.add(sel.Program__r.Id);
            }
            if (sel.Program__r != null) {
                Map<String,Object> bookingInfo = null;
                Boolean allowSchedule; //= sel.AllowSelfSchedule__c && sel.Applicant_State_Management__c == 'Profile Shortlisted';
                Boolean isScheduled = false;
                Boolean isRejected = false;
                String applicationStatus = String.isBlank(sel.Application_Status__c)?'': sel.Application_Status__c;
                applicationStatus = sel.Application_Status__c == 'Paid'?'Paid':applicationStatus;
                if(applicationStatus == 'Paid'){
                    paidProgramsId.add(sel.Program__c);
                    
                }
                Boolean isFirstRound = true;
                Boolean isDecisionPresent = false;
                if(!sel?.Round_Results__r.isEmpty()){
                    isFirstRound = false;
                }
                
                Integer countResults;
                Integer countBookings;
                

                String assignmentStatus = sel.Assignment_Status__c;
                switch on sel.Applicant_State_Management__c{
                    when 'Profile Shortlisted'{
                        allowSchedule = sel.AllowSelfSchedule__c;
                        
                    }
                    
                    when 'Reject Round 1','Reject Round 2','Disqualified'{
                        applicationStatus = 'Disqualified';
                        isRejected = true;
                        isScheduled = false;
                    }
                    when 'Interview Round 1','Interview Round 2'{
                        if(!sel?.ApplicationSlotBookings__r.isEmpty() && sel?.Admission_Decisions__r.isEmpty()) {
                            if(!sel?.Round_Results__r.isEmpty()){
                                countResults = sel.Round_Results__r.size();
                                countBookings = sel.ApplicationSlotBookings__r.size();
                                if(countBookings > countResults){
                                    sel.AllowSelfSchedule__c = false;
                                    allowSchedule = false;
                                }
                            }
                            bookingInfo = constructBookingInfo(new List<ApplicationSlotBooking__c>{sel?.ApplicationSlotBookings__r[0]});
                            
                            isScheduled = true;
                            
                            
                            
                        }
                        
                        isScheduled = true;
                        applicationStatus = 'Shortlisted for Interview';
                    }
                    when 'Offer Issued','Withdrawn','Offer Accepted'{
                        if(!sel?.Admission_Decisions__r.isEmpty() ){
                            allowSchedule = false;
                            isDecisionPresent = true;
                            Admission_Decision__c decision = sel.Admission_Decisions__r;
                            if(decision.Result__c == 'Not Eligible'){
                                applicationStatus = 'Rejected';
                            }
                            else if(decision.Result__c == 'Waitlisted'){
                                applicationStatus = 'Waitlisted';
                            }
                            else{
                                applicationStatus = 'Selected';
                            }
                            
                        }
                    }
                }
                
                List<ProgramCohort> batchList = [SELECT Id ,Application_Start_Date__c,Application_End_Date__c,ProgramId
        FROM ProgramCohort WHERE ProgramId IN :programIdSet 
        AND Application_Start_Date__c<=TODAY AND Application_End_Date__c >= TODAY LIMIT 1];
        String applyString = 'Published';
        if(batchList.isEmpty()){
            applyString = 'Not Published';
           // batchNotFound = true;

        }
                apbsMap.put(sel.Program__c, new AccountProgramApplicationWrapper(
                    sel.Program__r.Id,
                sel.Program__r.Name,
                sel.Program__r.Program_Code__c,
                applicationStatus,
                sel.Application_Stage__c,
                sel.Name,
                allowSchedule,
                bookingInfo,
                isScheduled,
                isFirstRound,
                isDecisionPresent,
                applicantName,
                countBookings,
                appId,
                isRejected,
                applyString,
                assignmentStatus
                    ));
            }
        }
        
       
        system.debug('Paid for Programs are '+paidProgramsId);
        Set<String> allowPastEndDate = new Set<String>{'Paid'};
        
        Boolean batchNotFound = false;
        List<Program> programList = [SELECT Id,StartDate,EndDate FROM Program WHERE Id IN:programIdSet];
        
        
        for(Program p :programList){
            if(apbsMap.containsKey(p.Id)){
                Date dateToday = Date.today();
                if(paidProgramsId.contains(p.Id)){
                    system.debug('Found a paid program');
                    apbsMap.get(p.Id).applicationAcceptanceStatus = 'Paid';
                    continue;
                }
                if(dateToday >= p.StartDate && dateToday <= p.EndDate){
                    apbsMap.get(p.Id).applicationAcceptanceStatus = 'Open';
                    continue;
                }
                else if(dateToday < p.StartDate){
                    apbsMap.get(p.Id).applicationAcceptanceStatus = 'Too Early';
                    continue;
                }
                else if(dateToday > p.EndDate){
                    apbsMap.get(p.Id).applicationAcceptanceStatus = 'Closed';
                }
                
            }
        }
        
        
        return apbsMap.values();
        
    }
    
    private static Map<String,Object> constructBookingInfo(List<ApplicationSlotBooking__c> bookings) {
        Map<String,Object> bookingInfo = new Map<String,Object>();
        bookingInfo.put('bookingId', bookings[0].Id);
        bookingInfo.put('bookingState', bookings[0].BookingState__c);
        bookingInfo.put('bookingStartTime', formatISTTime(bookings[0].SlotMaster__r.SlotStartTime__c));
        bookingInfo.put('bookingEndTime', formatISTTime(bookings[0].SlotMaster__r.SlotEndTime__c));
        bookingInfo.put('bookingDate', bookings[0].SlotMaster__r.SlotDate__c);
        bookingInfo.put('bookingAddress', bookings[0].SlotMaster__r.LocationMaster__r?.AddressInformation__c);
        return bookingInfo;
    }
    
    private static String formatISTTime(Time val) {        
        if (val == null) {
            return '';
        }

        DateTime dt = DateTime.newInstance(
            Date.newInstance(2000, 1, 1),
            val
        );

        return dt.format('hh:mm a');
    }
    
    
    private static String formatTime(Time timevalue) {
        return DateTime.newInstance(Date.today(), timevalue).format('h:mm a');
    }
    
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getCurrentUserPersonAccountInfo() {
        User u = [
            SELECT Id, Account.FirstName, Account.LastName, Account.PersonEmail, Account.Phone
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        
        if (u.AccountId == null) {
            return new Map<String, Object>(); // not a person account
        }
        
        return new Map<String, Object> {
            'FirstName' => u.Account.FirstName,
            'LastName' => u.Account.LastName,
            'PersonEmail' => u.Account.PersonEmail,
            'Phone' => u.Account.Phone
        };
    }

    
    @AuraEnabled(cacheable=true)
    public static String getObjectApiName(Id recordId) {
        if (recordId == null) {
            return null;
        }
        
        return recordId.getSObjectType().getDescribe().getName();
    }

    public class AnnexureWrapper {
        @AuraEnabled public String annexureName;
        @AuraEnabled public String annexureUrl;
        @AuraEnabled public Decimal displayOrder;
    }

    public class ProgramDocumentWrapper {
        @AuraEnabled public String programCode;
        @AuraEnabled public String acceptanceLetterUrl;
        @AuraEnabled public List<AnnexureWrapper> annexures;
    }

    private static Document_Details__c ensureDocumentDetail(Id applicationId, String docCode) {
        List<Document_Details__c> existing = [
            SELECT Id
            FROM Document_Details__c
            WHERE Application_No__c = :applicationId
            AND Document_Code__c = :docCode
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        Document_Details__c docDetail = new Document_Details__c(
            Application_No__c = applicationId,
            Document_Code__c = docCode,
            Name = docCode
        );
        insert docDetail;
        return docDetail;
    }

    private static String getDocumentDetailFileUrl(Id applicationId, String docCode) {
        if (applicationId == null || String.isBlank(docCode)) {
            return '';
        }

        List<Document_Details__c> docList = [
            SELECT Id
            FROM Document_Details__c
            WHERE Application_No__c = :applicationId
            AND Document_Code__c = :docCode
            LIMIT 1
        ];
        if (docList.isEmpty()) {
            System.debug('No Document_Details__c record found for applicationId: ' + applicationId + ', docCode: ' + docCode);
            return '';
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :docList[0].Id
            LIMIT 1
        ];
        if (links.isEmpty()) return '';

        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        if (versions.isEmpty()) return '';

        List<ContentDistribution> existingDist = [
            SELECT Id, DistributionPublicUrl, ContentDownloadUrl,
                   PreferencesAllowOriginalDownload,
                   PreferencesAllowPDFDownload
            FROM ContentDistribution
            WHERE ContentVersionId = :versions[0].Id
            LIMIT 1
        ];

        ContentDistribution cd;
        if (!existingDist.isEmpty()) {
            cd = existingDist[0];
            if (!cd.PreferencesAllowOriginalDownload || !cd.PreferencesAllowPDFDownload) {
                cd.PreferencesAllowOriginalDownload = true;
                cd.PreferencesAllowPDFDownload = true;
                update cd;

                cd = [
                    SELECT Id, DistributionPublicUrl, ContentDownloadUrl
                    FROM ContentDistribution
                    WHERE Id = :cd.Id
                    LIMIT 1
                ];
            }
        } else {
            cd = new ContentDistribution();
            cd.Name = docCode + '_' + versions[0].Id;
            cd.ContentVersionId = versions[0].Id;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesAllowOriginalDownload = true;
            cd.PreferencesAllowPDFDownload = true;
            cd.PreferencesNotifyOnVisit = false;
            cd.PreferencesPasswordRequired = false;
            insert cd;

            cd = [
                SELECT Id, DistributionPublicUrl, ContentDownloadUrl
                FROM ContentDistribution
                WHERE Id = :cd.Id
                LIMIT 1
            ];
        }

        if (String.isNotBlank(cd.ContentDownloadUrl)) {
            return cd.ContentDownloadUrl;
        }
        if (String.isNotBlank(cd.DistributionPublicUrl)) {
            return cd.DistributionPublicUrl;
        }
        return Site.getBaseCustomUrl() + '/sfc/servlet.shepherd/version/download/' + versions[0].Id;
    }
    
    
}
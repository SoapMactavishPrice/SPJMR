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
    
    @AuraEnabled
    public static Map<String,String> checkUploadedDocuments(String applicationId){
        List<ContentDocumentLink> listContentDocLinks = [SELECT Id,ContentDocument.Title,ContentDocumentId   FROM ContentDocumentLink 
        WHERE LinkedEntityId = :applicationId 
        AND ContentDocument.Title LIKE '%Signed%' 
        AND ContentDocument.Title LIKE '%Letter%'];
        Set<Id> setContentId = new Set<Id>();
        for(ContentDocumentLink cdl: listContentDocLinks){
            setContentId.add(cdl.ContentDocumentId);
        }
        
        List<ContentDistribution> listContentDistribution = [SELECT ContentVersion.Title,DistributionPublicUrl,ContentDocumentId FROM ContentDistribution
        WHERE ContentDocumentId  IN :setContentId];
        Map<String,String> resultMap = new Map<String,String>();
        
        resultMap.put('acceptanceLetter','false');
        resultMap.put('offerLetter','false');
        for(ContentDistribution cdl:listContentDistribution){
            if(cdl.ContentVersion?.Title.contains('Offer')){
                resultMap.put('offerLetter','true');
                resultMap.put('offerLetterUrl',cdl.DistributionPublicUrl);
                resultMap.put('offerLetterId',cdl.ContentDocumentId);
            }
            if(cdl.ContentVersion?.Title.contains('Acceptance')){
                resultMap.put('acceptanceLetter','true');
                resultMap.put('acceptanceLetterId',cdl.ContentDocumentId);
                resultMap.put('acceptanceLetterUrl',cdl.DistributionPublicUrl);
            }
        }

        return resultMap;
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
            (SELECT Id,Program__r.Name,Applicant_State_Management__c,
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
                for(Account acc: accts){
                    if(acc?.Applications__r.size()>0){
                        listApplications = acc.Applications__r;
                        for(Application__c app:acc.Applications__r){
                            if(app?.Admission_Decisions__r.size()>0){
                                
                                for(Admission_Decision__c adm:app.Admission_Decisions__r){
                                    admissionDecisionIds.add(adm.Id);
                                }
                            }
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
                        
                        admissionDecision res = new admissionDecision();
                        res.ProgramName = app.Program__r.Name;
                        res.applicationId = app.Id;
                        res.isOfferWithdrawn = String.valueOf(app.Applicant_State_Management__c=='Withdrawn');
                        if(app?.Admission_Decisions__r.size()>0){
                            for(Admission_Decision__c adm:app.Admission_Decisions__r){
                                res.offerLetterLink = mapAdmissionToPublicUrl.get(adm.Id);
                                res.admissionDecisionId = adm.Id;
                                res.offerAccepted = String.valueOf(app.Applicant_State_Management__c == 'Offer Accepted');
                                res.offerDeclined = String.valueOf(app.Applicant_State_Management__c == 'OFfer Not Accepted');
                                res.contentDocId = mapAdmissionToOffer.get(adm.Id);
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
    public static List<Program_Document__mdt> getProgramSpecificDocuments(String admissionId){
        try {
            List<Admission_Decision__c> admList = [SELECT Id, Application__r.Program__r.Program_Code__c 
            FROM Admission_Decision__c WHERE Id=:admissionId LIMIT 1];
            if(!admList.isEmpty()){
                String pgmCode = admList[0].Application__r.Program__r.Program_Code__c;
                List<Program_Document__mdt> pgmMetadata = [SELECT Id,Acceptance_Letter__c,Annexure_1__c 
                FROM Program_Document__mdt WHERE DeveloperName=:pgmCode LIMIT 1];
                
                if(!pgmMetadata.isEmpty()){
                    return pgmMetadata;
                }
                
            }
            return new List<Program_Document__mdt>();
            
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
    
    
}
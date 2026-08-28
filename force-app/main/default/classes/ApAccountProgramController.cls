public with sharing class ApAccountProgramController {

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
    public static String deleteDocument(String contentDocumentId, String entity){
        if(String.isEmpty(contentDocumentId) || String.isEmpty(entity)){
            return '';
        }
        List<ContentDocument> contentDocList = [SELECT Id FROM ContentDocument WHERE Id = :contentDocumentId];
        if(!contentDocList.isEmpty()){
            try{
                delete contentDocList;
                return entity;
            }
            catch(DMLException e){
                system.debug('Could not delete document [' + entity + ']: ' + e.getMessage());
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
            return getDocumentDetailFileUrl(applicationId, 'Annexure1LetterofAcceptance');
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

    @AuraEnabled()
    public static Boolean getOfferDocumentUploadConfig(String programCode) {
        if (String.isBlank(programCode)) return false;
        List<ApplicationProgramBasedConfig__mdt> records = [
            SELECT ConfigValue__c, Type__c
            FROM ApplicationProgramBasedConfig__mdt
            WHERE Intent__c      = 'ShowOfferDocumentUpload'
              AND ProgramCode__c = :programCode
              AND Active__c      = true
            LIMIT 1
        ];
        if (!records.isEmpty() && records[0].Type__c == 'Boolean') {
            return records[0].ConfigValue__c != null &&
                   records[0].ConfigValue__c.trim().equalsIgnoreCase('true');
        }
        return false;
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

            syncAcceptanceLetterUploadStatus(applicationId, docCode);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @TestVisible
    public static void syncAcceptanceLetterUploadStatus(Id applicationId, String docCode) {
        if (applicationId == null || String.isBlank(docCode)) {
            return;
        }

        String normalizedCode = normalizeDocCode(docCode);
        if (!isAcceptanceLetterDocumentCode(normalizedCode)) {
            return;
        }

        List<Application__c> apps = [
            SELECT Id, Program__r.Program_Code__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return;
        }

        String programCode = apps[0].Program__r != null ? apps[0].Program__r.Program_Code__c : null;
        if (String.isBlank(programCode)) {
            return;
        }

        List<Program_Document__mdt> programDocs = [
            SELECT Id,
                (SELECT AnnexureName__c, DisplayAsImportantDocument__c, IsUploadSectionRequired__c
                 FROM Program_Annexures__r)
            FROM Program_Document__mdt
            WHERE Program_Code__c = :programCode
            LIMIT 1
        ];

        Boolean isConfiguredAcceptanceLetter = false;
        for (Program_Document__mdt programDoc : programDocs) {
            for (ProgramAnnexure__mdt annexure : programDoc.Program_Annexures__r) {
                if (annexure.AnnexureName__c == 'Annexure 1 - Letter of Acceptance'
                    && annexure.DisplayAsImportantDocument__c == true
                    && annexure.IsUploadSectionRequired__c == true) {
                    isConfiguredAcceptanceLetter = true;
                    break;
                }
            }
            if (isConfiguredAcceptanceLetter) {
                break;
            }
        }

        if (!isConfiguredAcceptanceLetter) {
            return;
        }

        List<Admission_Decision__c> decisions = [
            SELECT Id, IsSignedAcceptanceLetterUploaded__c
            FROM Admission_Decision__c
            WHERE Application__c = :applicationId
              AND Result__c = 'Eligible for Admission'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (decisions.isEmpty() || decisions[0].IsSignedAcceptanceLetterUploaded__c == true) {
            return;
        }

        decisions[0].IsSignedAcceptanceLetterUploaded__c = true;
        update decisions[0];
    }

    @TestVisible
    private static Boolean isAcceptanceLetterDocumentCode(String docCode) {
        if (String.isBlank(docCode)) {
            return false;
        }

        String normalized = normalizeDocCode(docCode);
        String acceptedLetterCode = normalizeDocCode('Signed Annexure 1 - Letter of Acceptance');
        String acceptedLetterCodeWithUnderscore = normalizeDocCode('Signed_Annexure1LetterofAcceptance');

        return normalized == acceptedLetterCode
            || normalized == acceptedLetterCodeWithUnderscore
            || normalized == normalizeDocCode(buildDocCode('Annexure 1 - Letter of Acceptance'));
    }

    @TestVisible
    private static String normalizeDocCode(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.replaceAll('[^a-zA-Z0-9]', '');
    }
    
    @AuraEnabled
    public static Map<String, Object> getPersonalDetailTShirtSize(Id applicationId) {
        try {
            if (applicationId == null) return new Map<String, Object>();
            List<Personal_Detail__c> pdList = [
                SELECT Id, TShirtSize__c
                FROM Personal_Detail__c
                WHERE Application__c = :applicationId
                LIMIT 1
            ];
            Map<String, Object> result = new Map<String, Object>();
            if (!pdList.isEmpty()) {
                result.put('personalDetailId', pdList[0].Id);
                result.put('tShirtSize', pdList[0].TShirtSize__c);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void savePersonalDetailTShirtSize(Id applicationId, String tShirtSize) {
        if (applicationId == null) {
            throw new AuraHandledException('Missing applicationId');
        }
        List<Personal_Detail__c> pdList = [
            SELECT Id
            FROM Personal_Detail__c
            WHERE Application__c = :applicationId
            LIMIT 1
        ];
        if (pdList.isEmpty()) {
            throw new AuraHandledException('No Personal Detail record found for this application.');
        }
        Personal_Detail__c pd = pdList[0];
        pd.TShirtSize__c = tShirtSize;
        update pd;
    }

    @AuraEnabled
    public static Map<String, Object> checkUploadedDocumentsByCodes(String applicationId, List<String> docCodes) {
        Map<String, Object> resultMap = new Map<String, Object>();
        if (String.isBlank(applicationId) || docCodes == null || docCodes.isEmpty()) {
            return resultMap;
        }

        List<Document_Details__c> docDetails = [
            SELECT Id, Document_Code__c
            FROM Document_Details__c
            WHERE Application_No__c = :applicationId
            AND Document_Code__c IN :docCodes
        ];

        Map<Id, String> ddToCode = new Map<Id, String>();
        for (Document_Details__c dd : docDetails) {
            ddToCode.put(dd.Id, dd.Document_Code__c);
        }

        if (ddToCode.isEmpty()) return resultMap;

        Map<Id, Id> contentDocToDD = new Map<Id, Id>();
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :ddToCode.keySet()
        ]) {
            contentDocToDD.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
        }

        if (contentDocToDD.isEmpty()) return resultMap;

        Map<String, Map<String, Object>> codeToResult = new Map<String, Map<String, Object>>();
        for (ContentDistribution cdist : [
            SELECT DistributionPublicUrl, ContentDocumentId
            FROM ContentDistribution
            WHERE ContentDocumentId IN :contentDocToDD.keySet()
            ORDER BY CreatedDate DESC
        ]) {
            String code = ddToCode.get(contentDocToDD.get(cdist.ContentDocumentId));
            if (code != null && !codeToResult.containsKey(code)) {
                codeToResult.put(code, new Map<String, Object>{
                    'uploaded' => true,
                    'url' => cdist.DistributionPublicUrl,
                    'contentDocumentId' => cdist.ContentDocumentId
                });
            }
        }

        resultMap.putAll(codeToResult);
        return resultMap;
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
            Set<String> allowedApplicantStates = new Set<String>{
                'Offer Issued',
                'Offer Accepted',
                'Offer Not Accepted',
                'Withdrawn'
            };
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
                        for(Application__c app:acc.Applications__r){
                            if(!allowedApplicantStates.contains(app.Applicant_State_Management__c)){
                                continue;
                            }
                            listApplications.add(app);
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
                
                Map<Id, Set<String>> uploadedDocCodesByAppId = new Map<Id, Set<String>>();
                if(!appIds.isEmpty()){
                    List<Document_Details__c> uploadedDocs = [SELECT Application_No__c, Document_Code__c, Id FROM Document_Details__c WHERE Application_No__c IN :appIds AND Document_Code__c = 'Signed_OfferLetter'];
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
                                res.applicantStateManagement = app.Applicant_State_Management__c;

                                Boolean isAcc = (adm.Offer_Accepted__c == true);
                                Boolean hasPending = false;
                                if (isAcc) {
                                    Set<String> uploadedCodes = uploadedDocCodesByAppId.containsKey(app.Id)
                                        ? uploadedDocCodesByAppId.get(app.Id)
                                        : new Set<String>();
                                    Boolean hasOfferLetterDoc = String.isNotBlank(mapAdmissionToPublicUrl.get(adm.Id));
                                    hasPending = hasOfferLetterDoc && !uploadedCodes.contains('Signed_OfferLetter');
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
    public static ProgramDocumentWrapper getProgramSpecificDocuments(String admissionId, String applicationId) {
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
                SELECT Id, Program_Code__c,
                       (SELECT Id, AnnexureName__c, AnnexureURL__c, DisplayOrder__c,
                               DisplayAsImportantDocument__c, IsUploadSectionRequired__c, FilterCondition__c,
                               ShowDocumentsBeforeAccept__c
                        FROM Program_Annexures__r
                        ORDER BY DisplayOrder__c ASC)
                FROM Program_Document__mdt
                WHERE Program_Code__c = :pgmCode
                LIMIT 1
            ];

            Admission_Decision__c admRecord = null;
            if (String.isNotBlank(admissionId) && !pgmMetadataList.isEmpty()) {
                Set<String> fieldNames = new Set<String>{'Id'};
                for (ProgramAnnexure__mdt ann : pgmMetadataList[0].Program_Annexures__r) {
                    String fc = ann.FilterCondition__c;
                    if (String.isBlank(fc)) continue;
                    String fcTrimmed = fc.trim();
                    if (fcTrimmed.equalsIgnoreCase('true') || fcTrimmed.equalsIgnoreCase('false')) continue;
                    List<String> ops = new List<String>{'>=','<=','==','>','<','='};
                    for (String op : ops) {
                        Integer idx = fcTrimmed.indexOf(op);
                        if (idx > 0) {
                            String fname = fcTrimmed.substring(0, idx).trim();
                            if (Schema.SObjectType.Admission_Decision__c.fields.getMap().containsKey(fname)) {
                                fieldNames.add(fname);
                            }
                            break;
                        }
                    }
                }
                    String soql = 'SELECT ' + String.join(new List<String>(fieldNames), ', ')
                        + ' FROM Admission_Decision__c WHERE Id = \'' + String.escapeSingleQuotes(admissionId) + '\' LIMIT 1';
                try {
                    List<Admission_Decision__c> admList2 = Database.query(soql);
                    if (!admList2.isEmpty()) admRecord = admList2[0];
                } catch (Exception ex) {
                }
            }

            if (pgmMetadataList.isEmpty()) {
                return null;
            }

            Program_Document__mdt pgmMetadata = pgmMetadataList[0];

            ProgramDocumentWrapper result = new ProgramDocumentWrapper();
            result.programCode = pgmMetadata.Program_Code__c;
            result.annexures = new List<AnnexureWrapper>();

            for (ProgramAnnexure__mdt ann : pgmMetadata.Program_Annexures__r) {
                AnnexureWrapper aw = new AnnexureWrapper();
                aw.annexureName = ann.AnnexureName__c;
                aw.annexureUrl = ann.AnnexureURL__c;
                aw.displayOrder = ann.DisplayOrder__c;
                aw.displayAsImportantDocument = ann.DisplayAsImportantDocument__c == true;
                aw.isUploadSectionRequired = ann.IsUploadSectionRequired__c == true;
                aw.filterCondition = ann.FilterCondition__c;
                aw.docCode = buildDocCode(ann.AnnexureName__c);
                aw.showDocumentsBeforeAccept = ann.ShowDocumentsBeforeAccept__c == true;
                aw.filterCondition = evaluateFilterCondition(ann.FilterCondition__c, admRecord)
                    ? null
                    : 'FILTERED_OUT';
                result.annexures.add(aw);
            }

            return result;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @TestVisible
    private static String buildDocCode(String annexureName) {
        if (String.isBlank(annexureName)) return 'Signed_Unknown';
        // Remove all non-alphanumeric chars (spaces, hyphens, etc.) → CamelCase style
        String cleaned = annexureName.replaceAll('[^a-zA-Z0-9]', '');
        return 'Signed_' + cleaned;
    }

    @TestVisible
    private static Boolean evaluateFilterCondition(String condition, Admission_Decision__c admRecord) {
        if (String.isBlank(condition)) return true;

        String trimmed = condition.trim();

        if (trimmed.equalsIgnoreCase('true'))  return true;
        if (trimmed.equalsIgnoreCase('false')) return false;

        List<String> operators = new List<String>{'>=', '<=', '==', '>', '<', '='};
        String foundOp = null;
        String lhs = null;
        String rhs = null;

        for (String op : operators) {
            Integer idx = trimmed.indexOf(op);
            if (idx > 0) {
                foundOp = op;
                lhs = trimmed.substring(0, idx).trim();
                rhs = trimmed.substring(idx + op.length()).trim();
                break;
            }
        }

        if (foundOp == null || String.isBlank(lhs) || String.isBlank(rhs)) return false;

        Date rhsDate = resolveDateLiteral(rhs);
        if (rhsDate == null) return false;

        if (admRecord == null) return false;
        Date lhsDate = resolveAdmissionDateField(lhs, admRecord);
        if (lhsDate == null) return false;

        switch on foundOp {
            when '>='  { return lhsDate >= rhsDate; }
            when '<='  { return lhsDate <= rhsDate; }
            when '>'   { return lhsDate > rhsDate; }
            when '<'   { return lhsDate < rhsDate; }
            when '=', '==' { return lhsDate == rhsDate; }
        }
        return false;
    }

    private static Date resolveDateLiteral(String val) {
        if (String.isBlank(val)) return null;
        String v = val.trim();
        if (v.equalsIgnoreCase('TODAY'))     return Date.today();
        if (v.equalsIgnoreCase('YESTERDAY')) return Date.today().addDays(-1);
        if (v.equalsIgnoreCase('TOMORROW'))  return Date.today().addDays(1);
        v = v.replaceAll('^[\'"]|[\'"]$', '');
        if (v.length() == 10 && v.substring(2,3) == '/' && v.substring(5,6) == '/') {
            try {
                Integer day   = Integer.valueOf(v.substring(0, 2));
                Integer month = Integer.valueOf(v.substring(3, 5));
                Integer year  = Integer.valueOf(v.substring(6, 10));
                return Date.newInstance(year, month, day);
            } catch (Exception e) {
                return null;
            }
        }
        return null;
    }

    private static Date resolveAdmissionDateField(String fieldApiName, Admission_Decision__c admRecord) {
        try {
            Schema.SObjectField fld = Schema.SObjectType.Admission_Decision__c.fields.getMap().get(fieldApiName);
            if (fld == null) return null;
            Schema.DisplayType fldType = fld.getDescribe().getType();
            if (fldType != Schema.DisplayType.DATE && fldType != Schema.DisplayType.DATETIME) return null;
            Object val = admRecord.get(fieldApiName);
            if (val == null) return null;
            if (fldType == Schema.DisplayType.DATETIME) {
                return ((DateTime) val).date();
            }
            return (Date) val;
        } catch (Exception e) {
            return null;
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
        @AuraEnabled public Boolean allowSchedule;
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
    public static Boolean getTShirtSizeConfig(String programCode) {
        if (String.isBlank(programCode)) {
            return true;
        }
        List<ApplicationProgramBasedConfig__mdt> records = [
            SELECT ConfigValue__c, Type__c
            FROM ApplicationProgramBasedConfig__mdt
            WHERE Intent__c      = 'ShowTShirtSizeSelection'
              AND ProgramCode__c = :programCode
              AND Active__c      = true
            LIMIT 1
        ];
        if (!records.isEmpty() && records[0].Type__c == 'Boolean') {
            return records[0].ConfigValue__c != null &&
                   records[0].ConfigValue__c.trim().equalsIgnoreCase('true');
        }
        return true;
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
        @AuraEnabled public Boolean displayAsImportantDocument;
        @AuraEnabled public Boolean isUploadSectionRequired;
        @AuraEnabled public String filterCondition;
        @AuraEnabled public String docCode;
        @AuraEnabled public Boolean showDocumentsBeforeAccept;
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
        @AuraEnabled public string applicantStateManagement;
    }
    
    @AuraEnabled(cacheable=false)
    public static Map<String, String> getApplicationDetailsForQuestionnaire(Id applicationId) {
        try {
            if (applicationId == null) {
                throw new AuraHandledException('Missing applicationId');
            }
            List<Application__c> apps = [
                SELECT Id, Name, Applicant__r.Name, Applicant__r.PersonEmail
                FROM Application__c
                WHERE Id = :applicationId
                LIMIT 1
            ];
            if (apps.isEmpty()) {
                throw new AuraHandledException('Application not found');
            }
            Application__c app = apps[0];
            String fullName = app.Applicant__r?.Name != null ? app.Applicant__r.Name : '';
            return new Map<String, String>{
                'applicantName'  => fullName,
                'applicationId'  => app.Name,
                'applicantEmail' => app.Applicant__r?.PersonEmail
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveDeclineWithdrawalQuestionnaire(
            Id applicationId,
            String applicantName,
            String applicationIdText,
            String applicantEmailId,
            String whichInstituteAreYouJoining,
            String otherInstituteName,
            String reasonsForYourChoice,
            String reasonsForChoicePlacementRoles,
            String reasonsForChoiceOther,
            String anyOtherInformation,
            String type
    ) {
        try {
            DeclineWithdrawalQuestionnaire__c rec = new DeclineWithdrawalQuestionnaire__c();
            rec.Application__c                 = applicationId;
            rec.ApplicantName__c              = applicantName;
            rec.ApplicationId__c              = applicationIdText;
            rec.ApplicantEmailId__c           = applicantEmailId;
            rec.WhichInstituteAreYouJoining__c = whichInstituteAreYouJoining;
            rec.Other_Institute_Name__c       = otherInstituteName;
            rec.ReasonsForYourChoice__c       = reasonsForYourChoice;
            rec.Reasons_for_Choice_Placement_Roles__c = reasonsForChoicePlacementRoles;
            rec.Reasons_for_Choice_Other__c   = reasonsForChoiceOther;
            rec.AnyOtherInformation__c        = anyOtherInformation;
            rec.Type__c                       = type;
            insert rec;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
}
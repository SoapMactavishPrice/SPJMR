public without sharing class FinalPdfFileFetcher {
    
    public class PdfFileWrapper {
        @AuraEnabled public String fileName;
        @AuraEnabled public String base64Data;
        @AuraEnabled public String fileType; // pdf / image
    }
    public class PdfMetaWrapper {

    @AuraEnabled public Id versionId;
    @AuraEnabled public String fileName;
    @AuraEnabled public String fileType;
    @AuraEnabled public Integer contentSize;

    }
    public class PdfChunkWrapper {
        
        @AuraEnabled public String fileName;
        @AuraEnabled public String base64Data;
        @AuraEnabled public String fileType;
        
    }
    @AuraEnabled
    public static List<PdfFileWrapper> getAllPdfFiles(Id recordId) {

        List<PdfFileWrapper> result = new List<PdfFileWrapper>();

        // =====================================================
        // 🎯 REQUIRED DOCUMENT ORDER (AS PER BUSINESS)
        // =====================================================
        List<String> orderedNames = new List<String>{
            'DOC_RESUME',   
            'Class 10 Mark Sheet',
            'Class 12 Mark Sheet', 
            'DOC_CLASS_X',
            'DOC_CLASS_XII',
            'DOC_DIPLOMA',        
            'DOC_GRAD',
            'DOC_POST_GRAD',
            'DOC_COMPETITIVE_GRE',
            'DOC_COMPETITIVE_GMAT',
            'DOC_COMPETITIVE_CAT',
            'DOC_COMPETITIVE_XAT',
            'DOC_COMPETITIVE_NMAT',
            'DOC_COMPETITIVE_GMATFocus',
            'DOC_LANGUAGE_TOEFL',
            'DOC_LANGUAGE_IELTS',
            'DOC_EXPERIENCE_LETTER',
                
            'DOC_PASSPORT',   
            'DOC_AADHAAR',
            'DOC_CLASS_X_CERTIFICATE', 
            'DOC_CLASS_X_MARKSHEET',
            'DOC_CLASS_XII_CERTIFICATE',
            'DOC_CLASS_XII_MARKSHEET',        
            'DOC_DIPLOMA_CERTIFICATE',
            'DOC_DIPLOMA_MARKSHEET',
            'DOC_GRAD_CERTIFICATE',
            'DOC_GRAD_MARKSHEET',
            'DOC_PG_CERTIFICATE',
            'DOC_PG_MARKSHEET',
            'DOC_CONVERSION_FACTOR',
            'DOC_OFFER_LETTER',
            'DOC_SALARY_SLIP',
            'DOC_WORK_EXP_1',
            'DOC_WORK_EXP_2',
            'DOC_WORK_EXP_3',
            'DOC_WORK_EXP_4',
            'DOC_WORK_EXP_5',
            'DOC_CAT_SCORE_CARD',
            'DOC_GMAT_SCORE_CARD',
            'DOC_GMAT_ADMIT_CARD',
            'DOC_GMAT_FOCUS_SCORE_CARD',
            'DOC_ACHIEVEMENTS'   
        };

        // =====================================================
        // 1️⃣ FETCH Document_Details__c
        // =====================================================
        List<Document_Details__c> docList = [
            SELECT Id, Document_Code__c
            FROM Document_Details__c
            WHERE Application_No__c = :recordId
            AND Document_Code__c != 'PASSPORT_PHOTO'
        ];

        if (docList.isEmpty()) {
            return result;
        }

        // =====================================================
        // 2️⃣ MAP Document_Code__c → ContentDocumentId(s)
        // =====================================================
        Map<String, List<Id>> docNameToContentIds = new Map<String, List<Id>>();

        Set<Id> docDetailIds = new Set<Id>();
        for (Document_Details__c d : docList) {
            docDetailIds.add(d.Id);
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :docDetailIds
        ];

        for (ContentDocumentLink link : links) {
            for (Document_Details__c d : docList) {
                if (d.Id == link.LinkedEntityId && d.Document_Code__c != null) {

                    String key = d.Document_Code__c.trim();

                    if (!docNameToContentIds.containsKey(key)) {
                        docNameToContentIds.put(key, new List<Id>());
                    }
                    docNameToContentIds.get(key).add(link.ContentDocumentId);
                }
            }
        }

        // =====================================================
        // 3️⃣ FETCH FILES IN EXACT ORDER
        // =====================================================
        for (String docName : orderedNames) {

            if (!docNameToContentIds.containsKey(docName)) continue;

            List<ContentVersion> fileList = [
                SELECT Id, Title, VersionData, FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId IN :docNameToContentIds.get(docName)
                AND IsLatest = true
                ORDER BY ContentSize DESC
            ];

            for (ContentVersion file : fileList) {

                if (file.VersionData == null) continue;

                String ext = file.FileExtension != null ? file.FileExtension.toLowerCase() : '';

                Boolean isPdf = (ext == 'pdf');

                if (isPdf) {

                 PdfFileWrapper w = new PdfFileWrapper();
                 w.fileName = file.Title;
                 w.base64Data = EncodingUtil.base64Encode(file.VersionData);
                 w.fileType = 'pdf';

                 result.add(w);
               }

            }
        }

        return result;
    }
    @AuraEnabled
public static List<PdfMetaWrapper> getDocumentMetadata(Id recordId) {

    List<PdfMetaWrapper> result = new List<PdfMetaWrapper>();

    // Same document order
    List<String> orderedNames = new List<String>{
        'DOC_RESUME',
        'Class 10 Mark Sheet',
        'Class 12 Mark Sheet',
        'DOC_CLASS_X',
        'DOC_CLASS_XII',
        'DOC_DIPLOMA',
        'DOC_GRAD',
        'DOC_POST_GRAD',
        'DOC_COMPETITIVE_GRE',
        'DOC_COMPETITIVE_GMAT',
        'DOC_COMPETITIVE_CAT',
        'DOC_COMPETITIVE_XAT',
        'DOC_COMPETITIVE_NMAT',
        'DOC_COMPETITIVE_GMATFocus',
        'DOC_LANGUAGE_TOEFL',
        'DOC_LANGUAGE_IELTS',
        'DOC_EXPERIENCE_LETTER',
        'DOC_PASSPORT',
        'DOC_AADHAAR',
        'DOC_CLASS_X_CERTIFICATE',
        'DOC_CLASS_X_MARKSHEET',
        'DOC_CLASS_XII_CERTIFICATE',
        'DOC_CLASS_XII_MARKSHEET',
        'DOC_DIPLOMA_CERTIFICATE',
        'DOC_DIPLOMA_MARKSHEET',
        'DOC_GRAD_CERTIFICATE',
        'DOC_GRAD_MARKSHEET',
        'DOC_PG_CERTIFICATE',
        'DOC_PG_MARKSHEET',
        'DOC_CONVERSION_FACTOR',
        'DOC_OFFER_LETTER',
        'DOC_SALARY_SLIP',
        'DOC_WORK_EXP_1',
        'DOC_WORK_EXP_2',
        'DOC_WORK_EXP_3',
        'DOC_WORK_EXP_4',
        'DOC_WORK_EXP_5',
        'DOC_CAT_SCORE_CARD',
        'DOC_GMAT_SCORE_CARD',
        'DOC_GMAT_ADMIT_CARD',
        'DOC_GMAT_FOCUS_SCORE_CARD',
        'DOC_ACHIEVEMENTS'
    };

    List<Document_Details__c> docList = [
        SELECT Id, Document_Code__c
        FROM Document_Details__c
        WHERE Application_No__c = :recordId
        AND Document_Code__c != 'PASSPORT_PHOTO'
    ];

    if(docList.isEmpty()){
        return result;
    }

    Map<String,List<Id>> docNameToContentIds = new Map<String,List<Id>>();

    Set<Id> docIds = new Set<Id>();

    for(Document_Details__c d : docList){
        docIds.add(d.Id);
    }

    List<ContentDocumentLink> links = [
        SELECT ContentDocumentId, LinkedEntityId
        FROM ContentDocumentLink
        WHERE LinkedEntityId IN :docIds
    ];

    Map<Id,String> detailToCode = new Map<Id,String>();

    for(Document_Details__c d : docList){
        detailToCode.put(d.Id,d.Document_Code__c);
    }

    for(ContentDocumentLink cdl : links){

        String code = detailToCode.get(cdl.LinkedEntityId);

        if(String.isBlank(code)){
            continue;
        }

        if(!docNameToContentIds.containsKey(code)){
            docNameToContentIds.put(code,new List<Id>());
        }

        docNameToContentIds.get(code).add(cdl.ContentDocumentId);

    }

    for(String docName : orderedNames){

        if(!docNameToContentIds.containsKey(docName)){
            continue;
        }

        for(ContentVersion cv : [

            SELECT
                Id,
                Title,
                FileExtension,
                ContentSize

            FROM ContentVersion

            WHERE ContentDocumentId IN :docNameToContentIds.get(docName)

            AND IsLatest=true

            ORDER BY ContentSize DESC

        ]){

            if(cv.FileExtension==null){
                continue;
            }

            if(cv.FileExtension.toLowerCase()!='pdf'){
                continue;
            }

            PdfMetaWrapper w = new PdfMetaWrapper();

            w.versionId = cv.Id;
            w.fileName = cv.Title;
            w.fileType = 'pdf';
            w.contentSize = cv.ContentSize;

            result.add(w);

        }

    }

    return result;

}
    @AuraEnabled
public static List<PdfChunkWrapper> getPdfChunk(List<Id> versionIds){

    List<PdfChunkWrapper> result = new List<PdfChunkWrapper>();

    for(ContentVersion cv : [

        SELECT
            Id,
            Title,
            VersionData,
            FileExtension

        FROM ContentVersion

        WHERE Id IN :versionIds

    ]){

        PdfChunkWrapper w = new PdfChunkWrapper();

        w.fileName = cv.Title;
        w.fileType = 'pdf';
        w.base64Data = EncodingUtil.base64Encode(cv.VersionData);

        result.add(w);

    }

    return result;

}
}
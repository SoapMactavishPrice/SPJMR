public with sharing class DocumentUploaderController {

    private static Document_Details__c ensureDocumentRecord(Id applicationId, String docCode) {
        if (applicationId == null || String.isBlank(docCode)) {
            throw new AuraHandledException('Missing required parameters');
        }

        List<Document_Details__c> existing = [
            SELECT Id, Name
            FROM Document_Details__c
            WHERE Application_No__c = :applicationId
            AND Document_Code__c = :docCode
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        Document_Details__c doc = new Document_Details__c(
            Application_No__c = applicationId,
            Document_Code__c = docCode,
            Name = docCode
        );
        insert doc;
        return doc;
    }

    /* ============================================================
       MAIN INIT METHOD
       ============================================================ */
    @AuraEnabled(cacheable=false)
    public static DocumentInitResponse getOrCreateDocument(Id applicationId, String docCode) {

        /* ---------------------------------------------------------
           1. Find or create Document_Details__c record
        --------------------------------------------------------- */
        Document_Details__c doc = ensureDocumentRecord(applicationId, docCode);

        /* ---------------------------------------------------------
           2. Find linked ContentDocuments
        --------------------------------------------------------- */
        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :doc.Id
        ];

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink cdl : links) {
            docIds.add(cdl.ContentDocumentId);
        }

        /* ---------------------------------------------------------
           3. Gather latest ContentVersions and build public URLs
        --------------------------------------------------------- */
        List<FileInfo> results = new List<FileInfo>();

        if (!docIds.isEmpty()) {
            List<ContentVersion> versions = [
                SELECT Id, Title, ContentDocumentId, VersionNumber, PathOnClient
                FROM ContentVersion
                WHERE IsLatest = TRUE
                AND ContentDocumentId IN :docIds
                ORDER BY LastModifiedDate DESC
            ];

            for (ContentVersion v : versions) {

                /* -------------------------------------------------
                   3A. Try to find existing public distribution
                ------------------------------------------------- */
                ContentDistribution dist;
                String publicUrl;

                List<ContentDistribution> existingDist = [
                    SELECT Id, DistributionPublicUrl, ContentVersionId, CreatedDate
                    FROM ContentDistribution
                    WHERE ContentVersionId = :v.Id
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];

                if (!existingDist.isEmpty()) {
                    dist = existingDist[0];
                    publicUrl = dist.DistributionPublicUrl;
                }

                /* -------------------------------------------------
                   3B. If no distribution exists → create one
                ------------------------------------------------- */
                if (dist == null) {
                    dist = new ContentDistribution(
                        Name = v.Title,
                        ContentVersionId = v.Id,
                        PreferencesAllowOriginalDownload = true,
                        PreferencesAllowPDFDownload = true,
                        PreferencesAllowViewInBrowser = true
                    );
                    insert dist;

                    // re-query to ensure DistributionPublicUrl exists
                    dist = [
                        SELECT Id, DistributionPublicUrl
                        FROM ContentDistribution
                        WHERE Id = :dist.Id
                        LIMIT 1
                    ];
                    publicUrl = dist.DistributionPublicUrl;
                }

                /* -------------------------------------------------
                   3C. Fallback: if URL still blank
                ------------------------------------------------- */
                if (String.isBlank(publicUrl)) {
                    // fallback to shepherd public URL
                    publicUrl = Site.getBaseCustomUrl()
                        + '/sfc/servlet.shepherd/version/download/' + v.Id;
                }

                /* -------------------------------------------------
                   3D. Add to response
                ------------------------------------------------- */
                FileInfo info = new FileInfo();
                info.documentId = v.ContentDocumentId;
                info.versionId = v.Id;
                info.title = (v.PathOnClient != null) ? v.PathOnClient : v.Title;
                info.downloadUrl = publicUrl;

                results.add(info);
            }
        }

        /* ---------------------------------------------------------
           FINAL RESPONSE
        --------------------------------------------------------- */
        DocumentInitResponse resp = new DocumentInitResponse();
        resp.documentId = doc.Id;
        resp.files = results;
        return resp;
    }

    @AuraEnabled
    public static DocumentInitResponse uploadFiles(Id applicationId, String docCode, List<UploadRequest> files) {
        if (files == null || files.isEmpty()) {
            throw new AuraHandledException('No files were provided.');
        }

        Document_Details__c doc = ensureDocumentRecord(applicationId, docCode);
        List<ContentVersion> versionsToInsert = new List<ContentVersion>();

        for (UploadRequest fileReq : files) {

            if (fileReq == null || String.isBlank(fileReq.fileName) || String.isBlank(fileReq.base64Data)) {
                throw new AuraHandledException('Each file must include a name and content.');
            }

            ContentVersion version = new ContentVersion();
            version.Title = deriveTitle(fileReq.fileName);
            version.PathOnClient = fileReq.fileName;
            version.VersionData = EncodingUtil.base64Decode(fileReq.base64Data);
            version.FirstPublishLocationId = doc.Id;
            versionsToInsert.add(version);
        }

        try {
            insert versionsToInsert;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to upload file - ' + e.getMessage());
        }

        return getOrCreateDocument(applicationId, docCode);
    }

    @AuraEnabled
    public static void deleteFiles(List<Id> documentIds) {
        if (documentIds == null || documentIds.isEmpty()) return;

        try {

            // STEP 1 — Get all CDLs for this ContentDocument
            List<ContentDocumentLink> cdls = [
                SELECT Id, LinkedEntityId, LinkedEntity.Type, ShareType,ContentDocumentId
                FROM ContentDocumentLink
                WHERE ContentDocumentId IN :documentIds
            ];

            List<ContentDocumentLink> deletable = new List<ContentDocumentLink>();
            Set<Id> deletableIds = new Set<Id>();
            // STEP 2 — Delete only CDLs not linked to User
            for (ContentDocumentLink cdl : cdls) {

                // Relationship type (User, Work_Experience__c, Application__c,...)
                String entityType = cdl.LinkedEntity.Type;

                // Skip User-linked CDL — cannot update/delete
                if (entityType == 'User') {
                    continue;
                }
                
                // This is your record-linked CDL → safe to delete
                deletable.add(cdl);
                deletableIds.add(cdl.ContentDocumentId);
            }

            // STEP 3 — Delete record-linked CDL ONLY
            if (!deletable.isEmpty()) {
                delete deletable;
                delete [
                    SELECT Id
                    FROM ContentDocument
                    WHERE Id IN :deletableIds
                ];
            }

        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to delete file — ' + e.getMessage()
            );
        }
    }


    @AuraEnabled
    public static Map<Id, Integer> getFileSizes(List<Id> documentIds) {

        Map<Id, Integer> result = new Map<Id, Integer>();
        if (documentIds == null || documentIds.isEmpty()) return result;     

        for(ContentVersion cv : [
            SELECT ContentSize,ContentDocumentId 
            FROM ContentVersion 
            WHERE ContentDocumentId IN :documentIds
            AND IsLatest = TRUE
        ]) {
            result.put(cv.ContentDocumentId, cv.ContentSize);
        }

        return result; // size in bytes
    }

    private static String deriveTitle(String fileName) {
        if (String.isBlank(fileName)) {
            return 'Uploaded File';
        }

        Integer dotIndex = fileName.lastIndexOf('.');
        if (dotIndex > 0) {
            return fileName.substring(0, dotIndex);
        }

        return fileName;
    }











    /* ============================================================
       WRAPPERS
       ============================================================ */
    public class DocumentInitResponse {
        @AuraEnabled public Id documentId;
        @AuraEnabled public List<FileInfo> files;
    }

    public class UploadRequest {
        @AuraEnabled public String fileName {get; set;}
        @AuraEnabled public String base64Data {get; set;}
    }

    public class FileInfo {
        @AuraEnabled public Id documentId;
        @AuraEnabled public Id versionId;
        @AuraEnabled public String title;
        @AuraEnabled public String downloadUrl;
    }
}
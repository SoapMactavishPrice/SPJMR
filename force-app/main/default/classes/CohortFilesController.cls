/**
 * Controller for Cohort Files LWC: search Program Cohorts (batches) and fetch files
 * linked to Document_Details__c for cohort members (Accounts).
 */
public with sharing class CohortFilesController {

    private static final Integer SEARCH_LIMIT = 15;

    public class FileRow {
        @AuraEnabled public String fileId { get; set; }
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public String documentName { get; set; }
    }

    public class CohortOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    /** Latest file body as Base64 for ZIP build in LWC (avoids CORS on file.force.com). */
    public class FileContentPayload {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String base64Data { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<CohortOption> searchProgramCohorts(String searchTerm) {
        List<CohortOption> options = new List<CohortOption>();
        String raw = String.isBlank(searchTerm) ? '' : String.escapeSingleQuotes(searchTerm.trim());
        String term = String.isBlank(raw) ? '%' : '%' + raw + '%';
        for (ProgramCohort pc : [
            SELECT Id, Name, Batch_Code__c
            FROM ProgramCohort
            WHERE Name LIKE :term
               OR Batch_Code__c LIKE :term
            ORDER BY Name
            LIMIT :SEARCH_LIMIT
        ]) {
            CohortOption o = new CohortOption();
            o.label = pc.Name;
            o.value = pc.Id;
            options.add(o);
        }
        return options;
    }

    @AuraEnabled(cacheable=false)
    public static List<FileRow> getCohortFiles(Id programCohortId, String fileTypeFilter) {
        List<FileRow> rows = new List<FileRow>();
        if (programCohortId == null) return rows;

        // Step 1: Cohort members (Account Ids)
        List<ProgramCohortMember> members = [
            SELECT Id, ProgramEnrolleeId, ProgramEnrollee.Name
            FROM ProgramCohortMember
            WHERE ProgramCohortId = :programCohortId
            AND ProgramEnrolleeId != null
        ];
        Set<Id> accountIds = new Set<Id>();
        Map<Id, String> accountNameById = new Map<Id, String>();
        for (ProgramCohortMember m : members) {
            accountIds.add(m.ProgramEnrolleeId);
            accountNameById.put(m.ProgramEnrolleeId, m.ProgramEnrollee != null ? m.ProgramEnrollee.Name : '');
        }
        if (accountIds.isEmpty()) return rows;

        // Step 2: Document_Details__c
        List<Document_Details__c> docs = [
            SELECT Id, Name, Student_Name__c
            FROM Document_Details__c
            WHERE Student_Name__c IN :accountIds
        ];
        Set<Id> docDetailIds = new Set<Id>();
        Map<Id, String> docNameById = new Map<Id, String>();
        Map<Id, Id> docToAccountId = new Map<Id, Id>();
        for (Document_Details__c d : docs) {
            docDetailIds.add(d.Id);
            docNameById.put(d.Id, d.Name != null ? d.Name : '');
            docToAccountId.put(d.Id, d.Student_Name__c);
        }
        if (docDetailIds.isEmpty()) return rows;

        // Step 3: ContentDocumentLink
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :docDetailIds
        ];
        Set<Id> contentDocIds = new Set<Id>();
        Map<Id, Id> contentDocToDocDetail = new Map<Id, Id>();
        for (ContentDocumentLink cdl : links) {
            contentDocIds.add(cdl.ContentDocumentId);
            contentDocToDocDetail.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
        }
        if (contentDocIds.isEmpty()) return rows;

        // Step 4: ContentDocument. A student can re-upload the same document
        // (e.g. PASSPORT_PHOTO) many times; each upload is a separate file linked
        // to the one Document_Details__c record. Keep only the latest file per
        // (student + document name) so each document shows a single, current row.
        List<ContentDocument> cds = [
            SELECT Id, Title, FileExtension, CreatedDate, ContentModifiedDate
            FROM ContentDocument
            WHERE Id IN :contentDocIds
            AND IsDeleted = false
            ORDER BY CreatedDate DESC, ContentModifiedDate DESC
        ];
        rows.addAll(buildLatestFileRows(
            cds, fileTypeFilter, contentDocToDocDetail, docToAccountId, docNameById, accountNameById
        ));
        return rows;
    }

    /**
     * Collapses files to the latest one per (student + document name), in newest-first
     * order, applying the optional file-type filter.
     * @param cds ContentDocuments ordered newest-first
     * @param fileTypeFilter optional extension filter (png/jpg/jpeg/pdf); blank = all
     * @param contentDocToDocDetail ContentDocumentId -> Document_Details__c Id
     * @param docToAccountId Document_Details__c Id -> student Account Id
     * @param docNameById Document_Details__c Id -> document name
     * @param accountNameById Account Id -> account name
     * @return one FileRow per (student, document name), keeping the newest file
     */
    private static List<FileRow> buildLatestFileRows(
        List<ContentDocument> cds,
        String fileTypeFilter,
        Map<Id, Id> contentDocToDocDetail,
        Map<Id, Id> docToAccountId,
        Map<Id, String> docNameById,
        Map<Id, String> accountNameById
    ) {
        String extFilter = String.isBlank(fileTypeFilter) ? null : fileTypeFilter.trim().toLowerCase();
        Map<String, FileRow> latestByKey = new Map<String, FileRow>();
        for (ContentDocument cd : cds) {
            String ext = (cd.FileExtension != null) ? cd.FileExtension.toLowerCase() : '';
            if (!matchesFileType(ext, extFilter)) {
                continue;
            }
            // Map.get tolerates a null key, so no extra null guards are needed here.
            Id docDetailId = contentDocToDocDetail.get(cd.Id);
            Id accId = docToAccountId.get(docDetailId);
            String docName = docNameById.get(docDetailId);
            String key = String.valueOf(accId) + '|' + docName;
            // cds is ordered newest-first, so the first row seen for a key is the latest.
            if (latestByKey.containsKey(key)) {
                continue;
            }
            FileRow fr = new FileRow();
            fr.fileId = cd.Id;
            fr.fileName = (cd.Title != null ? cd.Title : '') + (String.isNotBlank(ext) ? '.' + ext : '');
            fr.accountName = accountNameById.get(accId);
            fr.documentName = docName;
            latestByKey.put(key, fr);
        }
        return latestByKey.values();
    }

    /**
     * Whether a file extension passes the selected file-type filter. A jpg/jpeg
     * selection matches both extensions; a blank filter matches everything.
     * @param ext lowercase file extension of the document
     * @param extFilter lowercase selected filter, or null for no filter
     * @return true when the extension should be included
     */
    private static Boolean matchesFileType(String ext, String extFilter) {
        if (extFilter == null) {
            return true;
        }
        if (extFilter == 'jpg' || extFilter == 'jpeg') {
            return ext == 'jpg' || ext == 'jpeg';
        }
        return ext == extFilter;
    }

    /**
     * Returns the latest ContentVersion body for a ContentDocument the user can read.
     * One document per call to stay within Apex heap for large files.
     */
    @AuraEnabled(cacheable = false)
    public static FileContentPayload getContentDocumentBodyForZip(Id contentDocumentId) {
        if (contentDocumentId == null) {
            return null;
        }
        List<ContentVersion> versions = [
            SELECT Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            return null;
        }
        ContentVersion cv = versions[0];
        String ext = cv.FileExtension != null ? cv.FileExtension : '';
        String title = cv.Title != null ? cv.Title : 'file';
        String composedName = title;
        if (String.isNotBlank(ext) && !title.toLowerCase().endsWith('.' + ext.toLowerCase())) {
            composedName = title + '.' + ext;
        }
        FileContentPayload payload = new FileContentPayload();
        payload.fileName = composedName;
        payload.base64Data = EncodingUtil.base64Encode(cv.VersionData);
        return payload;
    }
}
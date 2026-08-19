public with sharing class ImportSlotMaster {
    /** Uploads one CSV chunk as a ContentVersion. */
    @AuraEnabled
    public static Id uploadChunk(String fileName, String csvChunk, Integer chunkNumber) {
        if (String.isBlank(fileName)) {
            throw new AuraHandledException('File Name cannot be blank.');
        }
        if (String.isBlank(csvChunk)) {
            throw new AuraHandledException('CSV Chunk cannot be blank.');
        }

        ContentVersion version = new ContentVersion(
            Title = fileName + '_Chunk_' + chunkNumber,
            PathOnClient = fileName + '_Chunk_' + chunkNumber + '.csv',
            VersionData = Blob.valueOf(csvChunk)
        );
        insert version;
        return version.Id;
    }

    /** Starts the Slot Master import batch. */
    @AuraEnabled
    public static String startImport(List<Id> contentVersionIds, Boolean emailErrorReport) {
        if (contentVersionIds == null || contentVersionIds.isEmpty()) {
            throw new AuraHandledException('No CSV chunks found.');
        }

        Id jobId = Database.executeBatch(
            new Batch_SlotMasterImport(contentVersionIds, emailErrorReport),
            1
        );
        return String.valueOf(jobId);
    }

    /** Returns the current batch status. */
    @AuraEnabled(cacheable=true)
    public static AsyncApexJob getJobStatus(String jobId) {
        return [
            SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, CreatedDate, CompletedDate
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];
    }
}
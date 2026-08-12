public with sharing class AdmissionDecisionImportController {

    @AuraEnabled
    public static Id uploadChunk(
        String fileName,
        String csvChunk,
        Integer chunkNumber
    ) {

        if (String.isBlank(fileName) || String.isBlank(csvChunk)) {
            throw new AuraHandledException(
                'A file name and CSV content are required.'
            );
        }

        ContentVersion version = new ContentVersion(
            Title = fileName.replace('.csv', '') + '_Part_' + chunkNumber,
            PathOnClient = fileName.replace('.csv', '') + '_Part_' + chunkNumber + '.csv',
            VersionData = Blob.valueOf(csvChunk)
        );

        insert version;

        return version.Id;
    }

    @AuraEnabled
    public static String startImport(
        List<Id> contentVersionIds,
        Boolean emailReports
    ) {

        if (contentVersionIds == null || contentVersionIds.isEmpty()) {
            throw new AuraHandledException(
                'No CSV chunks were uploaded.'
            );
        }

        Id jobId = Database.executeBatch(
            new AdmissionDecisionImportBatch(
                contentVersionIds,
                emailReports
            ),
            1
        );

        return String.valueOf(jobId);
    }

    @AuraEnabled(cacheable=true)
    public static AsyncApexJob getJobStatus(
        String jobId
    ) {

        return [

            SELECT
                Id,
                Status,
                JobItemsProcessed,
                TotalJobItems,
                NumberOfErrors,
                CreatedDate,
                CompletedDate

            FROM AsyncApexJob

            WHERE Id = :jobId

            LIMIT 1

        ];

    }

}
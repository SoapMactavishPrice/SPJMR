public with sharing class InterviewBookingImportController {
    @AuraEnabled
    public static Id uploadChunk(String fileName, String csvChunk, Integer chunkNumber) {
        if (String.isBlank(fileName) || String.isBlank(csvChunk)) {
            throw new AuraHandledException('A file name and CSV content are required.');
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
        String importType,
        Id programId,
        Boolean notifyApplicants,
        Boolean notifyInterviewers,
        Boolean emailErrorCsv
    ) {
        if (contentVersionIds == null || contentVersionIds.isEmpty()) {
            throw new AuraHandledException('No CSV chunks were uploaded.');
        }
        if (!new Set<String>{ 'WITHOUT_PANEL', 'WITH_PANEL', 'ASSIGN_PANEL' }.contains(importType)) {
            throw new AuraHandledException('Select a valid import type.');
        }
        if (importType == 'WITH_PANEL' && programId == null) {
            throw new AuraHandledException('Select a program for Book Interview With Panel.');
        }

        return String.valueOf(Database.executeBatch(
            new InterviewBookingImportBatch(
                contentVersionIds,
                importType,
                programId,
                notifyApplicants,
                notifyInterviewers,
                emailErrorCsv
            ),
            1
        ));
    }
}
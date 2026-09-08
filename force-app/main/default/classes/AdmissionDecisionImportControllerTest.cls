@IsTest
private class AdmissionDecisionImportControllerTest {
    private static final String CSV_HEADER = String.join(new List<String>{
        'Application Number',
        'Admission Decision',
        'Waitlist Number',
        'Offer Date Date',
        'Last Date of Acceptance',
        'Last Date of Uploading the Signed Letter of Acceptance',
        'Last Date for Completing the Payment of the Acceptance Fee',
        'Last Date for Completing the Payment of the First Installment',
        'Balance Fee Payment ETA'
    }, ',');

    @IsTest
    static void uploadChunkCreatesContentVersion() {
        Test.startTest();
        Id versionId = AdmissionDecisionImportController.uploadChunk(
            'admission-decisions.csv',
            CSV_HEADER,
            2
        );
        Test.stopTest();

        ContentVersion version = [
            SELECT Title, PathOnClient, ContentSize
            FROM ContentVersion
            WHERE Id = :versionId
        ];
        System.assertEquals('admission-decisions_Part_2', version.Title);
        System.assertEquals('admission-decisions_Part_2.csv', version.PathOnClient);
        System.assert(version.ContentSize > 0, 'The CSV body should be stored.');
    }

    @IsTest
    static void uploadChunkRejectsMissingInputs() {
        Boolean blankNameRejected = false;
        Boolean blankContentRejected = false;

        try {
            AdmissionDecisionImportController.uploadChunk('', CSV_HEADER, 1);
        } catch (AuraHandledException expected) {
            blankNameRejected = true;
        }

        try {
            AdmissionDecisionImportController.uploadChunk('test.csv', '   ', 1);
        } catch (AuraHandledException expected) {
            blankContentRejected = true;
        }

        System.assert(blankNameRejected, 'A blank file name must be rejected.');
        System.assert(blankContentRejected, 'Blank CSV content must be rejected.');
    }

    @IsTest
    static void startImportRejectsMissingChunks() {
        Boolean nullListRejected = false;
        Boolean emptyListRejected = false;

        try {
            AdmissionDecisionImportController.startImport(null, false);
        } catch (AuraHandledException expected) {
            nullListRejected = true;
        }

        try {
            AdmissionDecisionImportController.startImport(new List<Id>(), true);
        } catch (AuraHandledException expected) {
            emptyListRejected = true;
        }

        System.assert(nullListRejected, 'A null chunk list must be rejected.');
        System.assert(emptyListRejected, 'An empty chunk list must be rejected.');
    }

    @IsTest
    static void startsBatchAndReturnsItsStatus() {
        Id versionId = AdmissionDecisionImportController.uploadChunk(
            'controller-import.csv',
            CSV_HEADER,
            1
        );

        Test.startTest();
        String jobId = AdmissionDecisionImportController.startImport(
            new List<Id>{ versionId },
            false
        );
        AsyncApexJob queuedJob =
            AdmissionDecisionImportController.getJobStatus(jobId);
        System.assertEquals((Id) jobId, queuedJob.Id);
        System.assertEquals(0, queuedJob.JobItemsProcessed);
        Test.stopTest();

        AsyncApexJob completedJob =
            AdmissionDecisionImportController.getJobStatus(jobId);
        System.assertEquals('Completed', completedJob.Status);
        System.assertEquals(1, completedJob.TotalJobItems);
        System.assertEquals(1, completedJob.JobItemsProcessed);
        System.assertEquals(0, completedJob.NumberOfErrors);
        System.assertNotEquals(null, completedJob.CompletedDate);
    }
}
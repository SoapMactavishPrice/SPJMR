@IsTest
private class ExportApplicationsControllerTest {

    @TestSetup
    static void setupData() {
        ContentVersion cv = new ContentVersion(
            Title = 'Export_Controller_Test_File',
            PathOnClient = 'Export_Controller_Test_File.csv',
            VersionData = Blob.valueOf('col1,col2\nA,B')
        );
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        insert new List<Export_Job__c>{
            new Export_Job__c(
                Name = 'Completed Job',
                JobId__c = 'JOB-COMP-001',
                Status__c = 'Completed',
                DocumentId__c = cv.ContentDocumentId
            ),
            new Export_Job__c(
                Name = 'In Progress Job',
                JobId__c = 'JOB-PROG-001',
                Status__c = 'Processing'
            )
        };
    }

    @IsTest
    static void testGetExportStatus_NullJobId() {
        Map<String, String> result = ExportApplicationsController.getExportStatus(null);
        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void testGetExportStatus_NoMatchingJob() {
        Map<String, String> result = ExportApplicationsController.getExportStatus('JOB-NOT-FOUND');
        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void testGetExportStatus_InProgressJob() {
        Map<String, String> result = ExportApplicationsController.getExportStatus('JOB-PROG-001');
        System.assertEquals('Processing', result.get('status'));
        System.assertEquals(false, result.containsKey('downloadUrl'));
    }

    @IsTest
    static void testGetExportStatus_CompletedJob() {
        Export_Job__c completedJob = [
            SELECT Id, DocumentId__c
            FROM Export_Job__c
            WHERE JobId__c = 'JOB-COMP-001'
            LIMIT 1
        ];

        Map<String, String> result = ExportApplicationsController.getExportStatus('JOB-COMP-001');

        System.assertEquals('Completed', result.get('status'));
        System.assert(result.containsKey('downloadUrl'));
        System.assert(result.get('downloadUrl').contains('/sfc/servlet.shepherd/document/download/' + completedJob.DocumentId__c));
    }

    @IsTest
    static void testExportApplicationsBatch_ReturnsJobId() {
        Test.startTest();
        String jobId = ExportApplicationsController.exportApplicationsBatch('NO_MATCHING_PROGRAM_CODE');
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }
}
@IsTest
private class ImportApplicationsTest {

    @IsTest
    static void testGetBulkApiUrl() {
        String bulkApiUrl = ImportApplications.getBulkApiUrl();

        System.assertNotEquals(null, bulkApiUrl, 'URL should not be null.');
        System.assert(
            bulkApiUrl.startsWith(URL.getOrgDomainUrl().toExternalForm()),
            'URL should start with org domain.'
        );
        System.assert(
            bulkApiUrl.endsWith('/services/data/v58.0/jobs/query'),
            'URL should end with Bulk API jobs/query path.'
        );
    }

    @IsTest
    static void testImportApplicationsReturnsSuccess() {
        // Header-only CSV prevents row-level DML while still executing the batch lifecycle.
        String csv = 'Application Number,Applicant State Management';

        Test.startTest();
        String result = ImportApplications.importApplications(csv);
        Test.stopTest();

        System.assertEquals('Success', result, 'Import method should return Success.');
    }

    @IsTest
    static void testGetBulkApiUrl_ExceptionPath() {
        ImportApplications.forceGetBulkApiUrlExceptionInTest = true;
        try {
            ImportApplications.getBulkApiUrl();
            System.assert(false, 'Expected AuraHandledException.');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should carry a message.');
        } finally {
            ImportApplications.forceGetBulkApiUrlExceptionInTest = false;
        }
    }
}
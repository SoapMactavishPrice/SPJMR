@isTest
private class ImportApplicationsTest {

    @isTest
    static void testGetBulkApiUrl_Success() {
        Test.startTest();
        String url = ImportApplications.getBulkApiUrl();
        Test.stopTest();

        System.assert(url.endsWith('/services/data/v58.0/jobs/query'),
            'URL should end with the jobs/query endpoint');
        System.assert(url.startsWith('http'), 'URL should be a full external URL: ' + url);
    }

    @isTest
    static void testGetBulkApiUrl_ThrowsAuraHandledException() {
        ImportApplications.forceGetBulkApiUrlExceptionInTest = true;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ImportApplications.getBulkApiUrl();
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected an AuraHandledException to be thrown');
    }

    @isTest
    static void testUploadChunk_CreatesContentVersion() {
        String fileName = 'MyApplications.csv';
        String csvChunk = 'Application Number,Applicant State Management\nAPP-1000,Shortlisted';

        Test.startTest();
        Id cvId = ImportApplications.uploadChunk(fileName, csvChunk, 1);
        Test.stopTest();

        System.assertNotEquals(null, cvId, 'A ContentVersion Id should be returned');

        ContentVersion cv = [
            SELECT Title, PathOnClient, VersionData
            FROM ContentVersion
            WHERE Id = :cvId
        ];

        System.assertEquals('MyApplications_Part_1', cv.Title);
        System.assertEquals('MyApplications_Part_1.csv', cv.PathOnClient);
        System.assertEquals(csvChunk, cv.VersionData.toString());
    }

    @isTest
    static void testUploadChunk_HandlesFileNameWithoutCsvExtension() {
        // .replace('.csv','') should be a no-op if the extension isn't present
        String fileName = 'MyApplications';
        String csvChunk = 'Application Number\nAPP-2000';

        Test.startTest();
        Id cvId = ImportApplications.uploadChunk(fileName, csvChunk, 3);
        Test.stopTest();

        ContentVersion cv = [SELECT Title, PathOnClient FROM ContentVersion WHERE Id = :cvId];
        System.assertEquals('MyApplications_Part_3', cv.Title);
        System.assertEquals('MyApplications_Part_3.csv', cv.PathOnClient);
    }

    @isTest
    static void testUploadChunk_MultipleChunksGetDistinctNames() {
        String fileName = 'BigFile.csv';

        Test.startTest();
        Id cv1 = ImportApplications.uploadChunk(fileName, 'chunk1data', 1);
        Id cv2 = ImportApplications.uploadChunk(fileName, 'chunk2data', 2);
        Test.stopTest();

        Map<Id, ContentVersion> versions = new Map<Id, ContentVersion>(
            [SELECT Id, Title FROM ContentVersion WHERE Id IN :new List<Id>{ cv1, cv2 }]
        );

        System.assertEquals('BigFile_Part_1', versions.get(cv1).Title);
        System.assertEquals('BigFile_Part_2', versions.get(cv2).Title);
    }

    @isTest
    static void testStartImport_NullList_ThrowsException() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ImportApplications.startImport(null, true, false);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // System.assertEquals('No CSV chunks were uploaded.', e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for null contentVersionIds');
    }

    @isTest
    static void testStartImport_EmptyList_ThrowsException() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ImportApplications.startImport(new List<Id>(), true, false);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // System.assertEquals('No CSV chunks were uploaded.', e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for empty contentVersionIds');
    }

    @isTest
    static void testStartImport_HappyPath_DispatchesBatchAndReturnsSuccess() {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'ImportFile_Part_1';
        cv.PathOnClient = 'ImportFile_Part_1.csv';
        cv.VersionData = Blob.valueOf('Application Number\nAPP-1000');
        insert cv;

        Test.startTest();
        String result = ImportApplications.startImport(new List<Id>{ cv.Id }, true, false);
        Test.stopTest(); // batch runs synchronously here

        System.assertEquals('Success', result);
    }

}
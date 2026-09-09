@isTest
private class ImportSlotMasterTest {

    // =================================================================
    // uploadChunk
    // =================================================================

    @isTest
    static void testUploadChunk_BlankFileName_ThrowsException() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ImportSlotMaster.uploadChunk(null, 'some,csv,data', 1);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // System.assertEquals('File Name cannot be blank.', e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for blank fileName');
    }

    @isTest
    static void testUploadChunk_EmptyStringFileName_ThrowsException() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ImportSlotMaster.uploadChunk('   ', 'some,csv,data', 1);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // System.assertEquals('File Name cannot be blank.', e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for whitespace-only fileName');
    }

    @isTest
    static void testUploadChunk_BlankCsvChunk_ThrowsException() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ImportSlotMaster.uploadChunk('SlotMaster.csv', null, 1);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // System.assertEquals('CSV Chunk cannot be blank.', e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for blank csvChunk');
    }

    @isTest
    static void testUploadChunk_EmptyStringCsvChunk_ThrowsException() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ImportSlotMaster.uploadChunk('SlotMaster.csv', '   ', 1);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // System.assertEquals('CSV Chunk cannot be blank.', e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for whitespace-only csvChunk');
    }

    @isTest
    static void testUploadChunk_CreatesContentVersion() {
        String fileName = 'SlotMaster.csv';
        String csvChunk = 'Slot Number,Slot Status\nSLOT-001,Open';

        Test.startTest();
        Id cvId = ImportSlotMaster.uploadChunk(fileName, csvChunk, 1);
        Test.stopTest();

        System.assertNotEquals(null, cvId, 'A ContentVersion Id should be returned');

        ContentVersion cv = [
            SELECT Title, PathOnClient, VersionData
            FROM ContentVersion
            WHERE Id = :cvId
        ];

        System.assertEquals('SlotMaster.csv_Chunk_1', cv.Title);
        System.assertEquals('SlotMaster.csv_Chunk_1.csv', cv.PathOnClient);
        System.assertEquals(csvChunk, cv.VersionData.toString());
    }

    @isTest
    static void testUploadChunk_MultipleChunksGetDistinctNames() {
        String fileName = 'BigSlotFile';

        Test.startTest();
        Id cv1 = ImportSlotMaster.uploadChunk(fileName, 'chunk-one-data', 1);
        Id cv2 = ImportSlotMaster.uploadChunk(fileName, 'chunk-two-data', 2);
        Test.stopTest();

        Map<Id, ContentVersion> versions = new Map<Id, ContentVersion>(
            [SELECT Id, Title, PathOnClient FROM ContentVersion WHERE Id IN :new List<Id>{ cv1, cv2 }]
        );

        System.assertEquals('BigSlotFile_Chunk_1', versions.get(cv1).Title);
        System.assertEquals('BigSlotFile_Chunk_1.csv', versions.get(cv1).PathOnClient);
        System.assertEquals('BigSlotFile_Chunk_2', versions.get(cv2).Title);
        System.assertEquals('BigSlotFile_Chunk_2.csv', versions.get(cv2).PathOnClient);
    }

    // =================================================================
    // startImport
    // =================================================================

    @isTest
    static void testStartImport_NullList_ThrowsException() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ImportSlotMaster.startImport(null, false);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // System.assertEquals('No CSV chunks found.', e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for null contentVersionIds');
    }

    @isTest
    static void testStartImport_EmptyList_ThrowsException() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ImportSlotMaster.startImport(new List<Id>(), false);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // System.assertEquals('No CSV chunks found.', e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception for empty contentVersionIds');
    }

    @isTest
    static void testStartImport_HappyPath_ReturnsValidJobId() {
        ContentVersion cv = new ContentVersion(
            Title = 'SlotImport_Chunk_1',
            PathOnClient = 'SlotImport_Chunk_1.csv',
            VersionData = Blob.valueOf('Slot Number,Slot Status\nSLOT-001,Open')
        );
        insert cv;

        Test.startTest();
        String jobIdString = ImportSlotMaster.startImport(new List<Id>{ cv.Id }, false);
        Test.stopTest(); // batch runs synchronously here

        System.assertNotEquals(null, jobIdString, 'Expected a job id string to be returned');

        // Confirm it's a real, resolvable Id
        Id jobId = (Id) jobIdString;
        AsyncApexJob job = [SELECT Id, Status FROM AsyncApexJob WHERE Id = :jobId LIMIT 1];
        System.assertEquals(jobId, job.Id);
    }

    // =================================================================
    // getJobStatus
    // =================================================================

    @isTest
    static void testGetJobStatus_ReturnsMatchingJob() {
        ContentVersion cv = new ContentVersion(
            Title = 'StatusCheck_Chunk_1',
            PathOnClient = 'StatusCheck_Chunk_1.csv',
            VersionData = Blob.valueOf('Slot Number,Slot Status\nSLOT-001,Open')
        );
        insert cv;

        Test.startTest();
        String jobIdString = ImportSlotMaster.startImport(new List<Id>{ cv.Id }, false);
        Test.stopTest(); // batch completes synchronously before we query status

        AsyncApexJob status = ImportSlotMaster.getJobStatus(jobIdString);

        System.assertNotEquals(null, status, 'Expected a job status to be returned');
        System.assertEquals(jobIdString, String.valueOf(status.Id));
        System.assertEquals('Completed', status.Status);
    }

    @isTest
    static void testGetJobStatus_UnknownJobId_ThrowsQueryException() {
        // A syntactically valid but non-existent AsyncApexJob Id should yield no rows,
        // which throws a QueryException on the implicit single-row assignment.
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ImportSlotMaster.getJobStatus('707000000000000AAA');
        } catch (System.QueryException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected a QueryException for a non-existent job id');
    }
}
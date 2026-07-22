@IsTest
public class DocumentUploaderControllerTest {

    private static Application__c createApplication() {
        Application__c app = new Application__c(Name = 'Test Application');
        insert app;
        return app;
    }

    private static ContentVersion createStandaloneFile(String title, String fileName, String body) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = fileName,
            VersionData = Blob.valueOf(body),
            IsMajorVersion = true
        );
        insert cv;

        return [
            SELECT Id, ContentDocumentId, ContentSize, PathOnClient, Title
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
    }
    
    @IsTest
    static void testMissingParams() {
        
        try {
            DocumentUploaderController.getOrCreateDocument(null, null);
            System.assert(false, 'Expected missing parameter exception.');
        } catch (Exception e) {
            System.assert(e instanceof AuraHandledException);
        }
    }
    
    @IsTest
    static void testCreateAndFetchDocument() {
        
        Application__c app = createApplication();
        
        Test.startTest();
        DocumentUploaderController.DocumentInitResponse resp =
            DocumentUploaderController.getOrCreateDocument(app.Id, 'DOC_A');
        Test.stopTest();
        
        System.assertNotEquals(null, resp.documentId);
        System.assertEquals(0, resp.files.size());
    }
    
    @IsTest
    static void testExistingDocumentWithFileAndExistingDistribution() {
        
        Application__c app = createApplication();
        
        Document_Details__c doc = new Document_Details__c(
            Name = 'DOC_B',
            Application_No__c = app.Id,
            Document_Code__c = 'DOC_B'
        );
        insert doc;
        
        ContentVersion cv = createStandaloneFile('File1', 'File1.pdf', 'Data1');
        
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = doc.Id,
            ShareType = 'I'
        );
        
        insert new ContentDistribution(
            Name = 'File1',
            ContentVersionId = cv.Id,
            PreferencesAllowOriginalDownload = true
        );
        
        Test.startTest();
        DocumentUploaderController.getOrCreateDocument(app.Id, 'DOC_B');
        Test.stopTest();
        
        DocumentUploaderController.DocumentInitResponse resp =
            DocumentUploaderController.getOrCreateDocument(app.Id, 'DOC_B');
        
        List<ContentDistribution> dists = [
            SELECT Id, DistributionPublicUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :cv.Id
        ];

        System.assertNotEquals(null, resp);
        System.assertEquals(1, resp.files.size());
        System.assertEquals(1, dists.size(), 'Existing distribution should be reused.');
    }
    
    @IsTest
    static void testDistributionCreationBranch() {
        
        Application__c app = createApplication();
        
        Document_Details__c doc = new Document_Details__c(
            Name = 'DOC_C',
            Application_No__c = app.Id,
            Document_Code__c = 'DOC_C'
        );
        insert doc;
        
        ContentVersion cv = createStandaloneFile('File2', 'File2.pdf', 'Data2');
        
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = doc.Id,
            ShareType = 'I'
        );
        
        Test.startTest();
        DocumentUploaderController.getOrCreateDocument(app.Id, 'DOC_C');
        Test.stopTest();
        
        DocumentUploaderController.DocumentInitResponse resp =
            DocumentUploaderController.getOrCreateDocument(app.Id, 'DOC_C');

        List<ContentDistribution> dists = [
            SELECT Id, DistributionPublicUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :cv.Id
        ];
        
        System.assertNotEquals(null, resp);
        System.assertEquals(1, resp.files.size());
        System.assertEquals(1, dists.size(), 'A new distribution should have been created.');
    }
    
    @IsTest
    static void testDeleteFilesBranches() {
        
        Application__c app = createApplication();
        
        Document_Details__c doc = new Document_Details__c(
            Name = 'DOC_D',
            Application_No__c = app.Id,
            Document_Code__c = 'DOC_D'
        );
        insert doc;
        
        ContentVersion cv = createStandaloneFile('File3', 'File3.pdf', 'Data3');
        
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = doc.Id,
            ShareType = 'I'
        );
        
        
        
        Test.startTest();
        DocumentUploaderController.deleteFiles(
            new List<Id>{cv.ContentDocumentId}
        );
        Test.stopTest();
        
        List<ContentDocumentLink> links =
            [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :doc.Id];
        
        System.assertEquals(0, links.size());
    }
    
    @IsTest
    static void testDeleteFilesNullBranch() {
        
        Test.startTest();
        DocumentUploaderController.deleteFiles(null);
        DocumentUploaderController.deleteFiles(new List<Id>());
        Test.stopTest();
        
    }

    @IsTest
    static void testGetFileSizesBranches() {
        
        ContentVersion cv = createStandaloneFile('SizeFile', 'SizeFile.pdf', 'SizeData');
        
        Test.startTest();
        Map<Id, Integer> result =
            DocumentUploaderController.getFileSizes(
                new List<Id>{cv.ContentDocumentId}
            );
        Test.stopTest();
        
        System.assertEquals(1, result.size());
        
        Map<Id, Integer> emptyResult =
            DocumentUploaderController.getFileSizes(null);
        
        System.assertEquals(0, emptyResult.size());
    }

    @IsTest
    static void testUploadFilesSuccess() {
        Application__c app = createApplication();

        DocumentUploaderController.UploadRequest req =
            new DocumentUploaderController.UploadRequest();
        req.fileName = 'Transcript.pdf';
        req.base64Data = EncodingUtil.base64Encode(Blob.valueOf('Transcript body'));

        Test.startTest();
        DocumentUploaderController.DocumentInitResponse resp =
            DocumentUploaderController.uploadFiles(
                app.Id,
                'DOC_UPLOAD',
                new List<DocumentUploaderController.UploadRequest>{req}
            );
        Test.stopTest();

        List<Document_Details__c> docs = [
            SELECT Id, Name, Document_Code__c, Application_No__c
            FROM Document_Details__c
            WHERE Application_No__c = :app.Id
            AND Document_Code__c = 'DOC_UPLOAD'
        ];

        System.assertEquals(1, docs.size());
        System.assertEquals(1, resp.files.size());
    }

    @IsTest
    static void testUploadFilesRejectsMissingFileList() {
        Application__c app = createApplication();

        try {
            DocumentUploaderController.uploadFiles(app.Id, 'DOC_UPLOAD_EMPTY', null);
            System.assert(false, 'Expected empty file list exception.');
        } catch (Exception e) {
            System.assert(e instanceof AuraHandledException);
        }

        try {
            DocumentUploaderController.uploadFiles(
                app.Id,
                'DOC_UPLOAD_EMPTY',
                new List<DocumentUploaderController.UploadRequest>()
            );
            System.assert(false, 'Expected empty file list exception.');
        } catch (Exception e) {
            System.assert(e instanceof AuraHandledException);
        }
    }

    @IsTest
    static void testUploadFilesRejectsInvalidFilePayload() {
        Application__c app = createApplication();

        DocumentUploaderController.UploadRequest req =
            new DocumentUploaderController.UploadRequest();
        req.fileName = 'Invalid.pdf';

        try {
            DocumentUploaderController.uploadFiles(
                app.Id,
                'DOC_UPLOAD_INVALID',
                new List<DocumentUploaderController.UploadRequest>{req}
            );
            System.assert(false, 'Expected invalid payload exception.');
        } catch (Exception e) {
            System.assert(e instanceof AuraHandledException);
        }
    }
}
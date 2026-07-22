@IsTest
private class FinalPdfFileFetcherTest {

    @testSetup
    static void setupData() {

        Application__c app = new Application__c(
            Name='Test App'
        );
        insert app;

        // PDF Document
        Document_Details__c pdfDoc = new Document_Details__c(
            Application_No__c = app.Id,
            Document_Code__c = 'DOC_RESUME'
        );
        insert pdfDoc;

        ContentVersion pdfVersion = new ContentVersion(
            Title='Resume',
            PathOnClient='Resume.pdf',
            VersionData=Blob.valueOf('PDF DATA'),
            IsMajorVersion=true
        );
        insert pdfVersion;

        pdfVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id=:pdfVersion.Id
        ];

        insert new ContentDocumentLink(
            ContentDocumentId=pdfVersion.ContentDocumentId,
            LinkedEntityId=pdfDoc.Id,
            ShareType='V',
            Visibility='AllUsers'
        );

        // Non PDF document (covers continue statement)

        Document_Details__c imageDoc = new Document_Details__c(
            Application_No__c=app.Id,
            Document_Code__c='DOC_GRAD'
        );
        insert imageDoc;

        ContentVersion imageVersion = new ContentVersion(
            Title='Image',
            PathOnClient='image.png',
            VersionData=Blob.valueOf('IMAGE'),
            IsMajorVersion=true
        );
        insert imageVersion;

        imageVersion=[
            SELECT Id,ContentDocumentId
            FROM ContentVersion
            WHERE Id=:imageVersion.Id
        ];

        insert new ContentDocumentLink(
            ContentDocumentId=imageVersion.ContentDocumentId,
            LinkedEntityId=imageDoc.Id,
            ShareType='V',
            Visibility='AllUsers'
        );
    }

    @IsTest
    static void testGetAllPdfFiles() {

        Application__c app=[
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];

        Test.startTest();

        List<FinalPdfFileFetcher.PdfFileWrapper> files =
            FinalPdfFileFetcher.getAllPdfFiles(app.Id);

        Test.stopTest();

        System.assertEquals(1, files.size());
        System.assertEquals('pdf', files[0].fileType);
        System.assertNotEquals(null, files[0].base64Data);
    }

    @IsTest
    static void testGetMetadata() {

        Application__c app=[
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];

        Test.startTest();

        List<FinalPdfFileFetcher.PdfMetaWrapper> meta =
            FinalPdfFileFetcher.getDocumentMetadata(app.Id);

        Test.stopTest();

        System.assertEquals(1, meta.size());
        System.assertEquals('pdf', meta[0].fileType);
        System.assertNotEquals(null, meta[0].versionId);
        System.assert(meta[0].contentSize > 0);
    }

    @IsTest
    static void testGetPdfChunk() {

        ContentVersion cv=[
            SELECT Id
            FROM ContentVersion
            WHERE FileExtension='pdf'
            LIMIT 1
        ];

        Test.startTest();

        List<FinalPdfFileFetcher.PdfChunkWrapper> chunk =
            FinalPdfFileFetcher.getPdfChunk(
                new List<Id>{cv.Id}
            );

        Test.stopTest();

        System.assertEquals(1, chunk.size());
        System.assertEquals('pdf', chunk[0].fileType);
        System.assertNotEquals(null, chunk[0].base64Data);
    }

    @IsTest
    static void testNoDocuments() {

        Application__c app = new Application__c(
            Name='Empty App'
        );
        insert app;

        Test.startTest();

        System.assertEquals(
            0,
            FinalPdfFileFetcher.getAllPdfFiles(app.Id).size()
        );

        System.assertEquals(
            0,
            FinalPdfFileFetcher.getDocumentMetadata(app.Id).size()
        );

        Test.stopTest();
    }
}
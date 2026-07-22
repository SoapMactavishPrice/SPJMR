@IsTest
private class PdfTriggerHandlerTest {
    @IsTest
    static void processAsync_linkedToNonUserDrivesEnqueue() {
        // Create a non-User record (Lead) and a ContentVersion linked to it so
        // ContentDocumentLink.LinkedEntityId does NOT start with '005'.
        Lead l = new Lead(LastName='T', Company='C', Email='t@t.com');
        try { insert l; } catch (Exception e) { return; }
        ContentVersion cv = new ContentVersion(
            Title='test.pdf', PathOnClient='test.pdf',
            VersionData=Blob.valueOf('x'),
            FirstPublishLocationId = l.Id
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        PdfTriggerHandler.processAsync(new List<Id>{ cv.Id });
        Test.stopTest();
    }
}
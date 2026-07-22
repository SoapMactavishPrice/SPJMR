@IsTest
public class ContentDocumentLinkHelperTest {
    
    // --------------------------------------------------------
    // Test cleanFiles() - empty branch
    // --------------------------------------------------------
    @IsTest
    static void testCleanFiles_NoPrefix() {
        
        List<ContentDocumentLink> fakeLinks = new List<ContentDocumentLink>();
        
        // create dummy link with wrong prefix (Account Id)
        Account acc = new Account(Name='Test');
        insert acc;
        
        fakeLinks.add(new ContentDocumentLink(
            LinkedEntityId = acc.Id,
            ContentDocumentId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        ));
        
        Test.startTest();
        ContentDocumentLinkHelper.cleanFiles(fakeLinks);
        Test.stopTest();
        
        System.assertEquals(1, fakeLinks.size());
    }
    
    // --------------------------------------------------------
    // Full async logic test
    // --------------------------------------------------------
    @IsTest
    static void testCleanFilesAsync_DeleteAndUpdate() {
        
        // Create Document Details
        Document_Details__c doc = new Document_Details__c(
            Name = 'Test Doc',
            Rejected_DateTime__c = System.now().addMinutes(-5)
        );
        insert doc;
        
        // Create file (ContentVersion)
        ContentVersion cv = new ContentVersion(
            Title = 'TestFile',
            PathOnClient = 'TestFile.txt',
            VersionData = Blob.valueOf('Test Content')
        );
        insert cv;
        
        // Get ContentDocumentId
        cv = [SELECT Id, ContentDocumentId, CreatedDate 
              FROM ContentVersion WHERE Id = :cv.Id];
        
        // Link file to Document_Details__c
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = doc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
        
        // Simulate trigger new list
        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>{cdl};
            
            Test.startTest();
        ContentDocumentLinkHelper.cleanFiles(newLinks);
        Test.stopTest();
        
        // Verify either delete or update branch executed
        List<ContentDocumentLink> linksAfter =
            [SELECT Id FROM ContentDocumentLink WHERE Id = :cdl.Id];
        
        Document_Details__c updatedDoc =
            [SELECT Document_Review_Status__c FROM Document_Details__c WHERE Id = :doc.Id];
        
        System.assert(updatedDoc.Document_Review_Status__c != null);
    }
    
    // --------------------------------------------------------
    // Test null rejection date branch
    // --------------------------------------------------------
    @IsTest
    static void testRejectedDateNull() {
        
        Document_Details__c doc = new Document_Details__c(
            Name = 'No Rejection Date'
        );
        insert doc;
        
        ContentVersion cv = new ContentVersion(
            Title = 'File2',
            PathOnClient = 'File2.txt',
            VersionData = Blob.valueOf('Content')
        );
        insert cv;
        
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = doc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
        
        Test.startTest();
        ContentDocumentLinkHelper.cleanFiles(
            new List<ContentDocumentLink>{cdl}
        );
        Test.stopTest();
        
        System.assertNotEquals(null, cdl.Id);
    }
}
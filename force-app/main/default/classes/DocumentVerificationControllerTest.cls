@IsTest
public class DocumentVerificationControllerTest {

    @TestSetup
    static void setupData() {

        // --------------------------------------------------
        // Create Program Team (Required Parent)
        // --------------------------------------------------
        Program_Team__c team = new Program_Team__c(
            Name = 'Test Team'
        );
        insert team;

        // --------------------------------------------------
        // Create Program Team Member (Pass Required Field)
        // --------------------------------------------------
        Program_Team_Members__c ptm = new Program_Team_Members__c(
            Program_Team__c = team.Id
        );
        insert ptm;

        // --------------------------------------------------
        // Create Application Verification
        // (DO NOT set Name if auto-number)
        // --------------------------------------------------
        Application_Verification__c verification =
            new Application_Verification__c(
                Verifier__c = UserInfo.getUserId(),
                Program_Team_Members__c = ptm.Id
            );
        insert verification;

        // --------------------------------------------------
        // Create Document Details
        // --------------------------------------------------
        insert new Document_Details__c(
            Application_Verification__c = verification.Id,
            Document_Review_Status__c = 'Pending'
        );
    }

    // ------------------------------------------------------------
    // getDocumentDetails - Empty Branch
    // ------------------------------------------------------------
    @IsTest
    static void testGetDocumentDetailsEmpty() {

        Test.startTest();
        List<DocumentVerificationController.DocumentWrapper> result =
            DocumentVerificationController.getDocumentDetails(
                UserInfo.getUserId()
            );
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    // ------------------------------------------------------------
    // getDocumentDetails - With Files
    // ------------------------------------------------------------
    @IsTest
    static void testGetDocumentDetailsWithFiles() {

        Application_Verification__c verification =
            [SELECT Id FROM Application_Verification__c LIMIT 1];

        Document_Details__c doc =
            [SELECT Id FROM Document_Details__c LIMIT 1];

        // Create File
        ContentVersion cv = new ContentVersion(
            Title = 'TestFile',
            PathOnClient = 'TestFile.pdf',
            VersionData = Blob.valueOf('Test Data'),
            IsMajorVersion = true
        );
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = doc.Id,
            ShareType = 'V'
        );

        Test.startTest();
        List<DocumentVerificationController.DocumentWrapper> result =
            DocumentVerificationController.getDocumentDetails(verification.Id);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals(1, result[0].files.size());
        System.assertNotEquals(null, result[0].files[0].previewUrl);
        System.assertNotEquals(null, result[0].files[0].downloadUrl);
    }

    // ------------------------------------------------------------
    // updateReviewStatus
    // ------------------------------------------------------------
    @IsTest
    static void testUpdateReviewStatus() {

        Document_Details__c doc =
            [SELECT Id FROM Document_Details__c LIMIT 1];

        Test.startTest();
        DocumentVerificationController.updateReviewStatus(
            doc.Id,
            'Approved',
            'Verified successfully'
        );
        Test.stopTest();

        Document_Details__c updated =
            [SELECT Document_Review_Status__c,
                    Remarks__c,
                    Verified_By__c,
                    Program_Team_Member__c
             FROM Document_Details__c
             WHERE Id = :doc.Id];

        System.assertEquals('Approved', updated.Document_Review_Status__c);
        System.assertEquals('Verified successfully', updated.Remarks__c);
        System.assertNotEquals(null, updated.Verified_By__c);
        System.assertNotEquals(null, updated.Program_Team_Member__c);
    }
}
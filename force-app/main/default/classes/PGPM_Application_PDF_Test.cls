@IsTest
private class PGPM_Application_PDF_Test {

    @TestSetup
    static void setupData() {

        Application__c app = new Application__c(Name='Test Application');
        insert app;

        // Personal Details
        insert new Personal_Detail__c(
            Application__c = app.Id,
            First_Name__c = 'Test',
            Last_Name__c = 'User'
        );

        // Academic Detail
        insert new Academic_Detail__c(
            Application__c = app.Id,
            Name='10th'
        );

        // Work Experience
        insert new Work_Experience__c(
            Application__c = app.Id,
            Name_of_Organisation__c='Test Company'
        );

        // Competitive Exam
        insert new Competitive_Exam_Details__c(
            Application__c = app.Id,
            Exam_Name__c='CAT'
        );

        // Basic Academic Detail
        insert new BasicAcademicDetail__c(
            Application__c = app.Id
        );

        // Resume Document
        Document_Details__c resumeDoc = new Document_Details__c(
            Application_No__c = app.Id,
            Document_Code__c = 'DOC_RESUME'
        );
        insert resumeDoc;

        // Passport Photo Document
        Document_Details__c photoDoc = new Document_Details__c(
            Application_No__c = app.Id,
            Document_Code__c = 'PASSPORT_PHOTO'
        );
        insert photoDoc;

        // -------- PDF FILE --------
        ContentVersion pdf = new ContentVersion(
            Title='Resume',
            PathOnClient='resume.pdf',
            VersionData=Blob.valueOf('PDF DATA'),
            IsMajorVersion=true
        );
        insert pdf;

        pdf = [SELECT ContentDocumentId FROM ContentVersion WHERE Id=:pdf.Id];

        insert new ContentDocumentLink(
            ContentDocumentId = pdf.ContentDocumentId,
            LinkedEntityId = resumeDoc.Id,
            ShareType='V',
            Visibility='AllUsers'
        );

        // -------- IMAGE FILE --------
        ContentVersion img = new ContentVersion(
            Title='Photo',
            PathOnClient='photo.jpg',
            VersionData=Blob.valueOf('IMG DATA'),
            IsMajorVersion=true
        );
        insert img;

        img = [SELECT ContentDocumentId FROM ContentVersion WHERE Id=:img.Id];

        insert new ContentDocumentLink(
            ContentDocumentId = img.ContentDocumentId,
            LinkedEntityId = photoDoc.Id,
            ShareType='V',
            Visibility='AllUsers'
        );
    }

    /*------------------------------------------------------
      Test Constructor with Data
    ------------------------------------------------------*/
    @IsTest
    static void testConstructorWithData() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        PageReference pageRef = Page.PGPM_Application_PDF;
        pageRef.getParameters().put('id',app.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        PGPM_Application_PDF controller = new PGPM_Application_PDF();
        Test.stopTest();

        System.assertNotEquals(null,controller);
        System.assertNotEquals(null,controller.imageUrls);
        System.assertNotEquals(null,controller.pdfUrls);
    }

    /*------------------------------------------------------
      Test Constructor Without Related Records
      (covers catch blocks)
    ------------------------------------------------------*/
    @IsTest
    static void testConstructorWithoutRecords() {

        Application__c app = new Application__c(Name='Empty Application');
        insert app;

        PageReference pageRef = Page.PGPM_Application_PDF;
        pageRef.getParameters().put('id',app.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        PGPM_Application_PDF controller = new PGPM_Application_PDF();
        Test.stopTest();

        System.assertNotEquals(null,controller);
    }

    /*------------------------------------------------------
      Test Cancel Method
    ------------------------------------------------------*/
    @IsTest
    static void testCancelMethod() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        PageReference pageRef = Page.PGPM_Application_PDF;
        pageRef.getParameters().put('id',app.Id);
        Test.setCurrentPage(pageRef);

        PGPM_Application_PDF controller = new PGPM_Application_PDF();

        Test.startTest();
        PageReference result = controller.Cancel();
        Test.stopTest();

        System.assertNotEquals(null,result);
    }

}
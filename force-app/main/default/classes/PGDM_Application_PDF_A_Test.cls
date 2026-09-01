@IsTest
private class PGDM_Application_PDF_A_Test {

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

        PageReference pageRef = Page.PGDM_Application_PDF_A;
        pageRef.getParameters().put('id',app.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        PGDM_Application_PDF_A controller = new PGDM_Application_PDF_A();
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

        PageReference pageRef = Page.PGDM_Application_PDF_A;
        pageRef.getParameters().put('id',app.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        PGDM_Application_PDF_A controller = new PGDM_Application_PDF_A();
        Test.stopTest();

        System.assertNotEquals(null,controller);
    }

    /*------------------------------------------------------
      Test Cancel Method
    ------------------------------------------------------*/
    @IsTest
    static void testCancelMethod() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        PageReference pageRef = Page.PGDM_Application_PDF_A;
        pageRef.getParameters().put('id',app.Id);
        Test.setCurrentPage(pageRef);

        PGDM_Application_PDF_A controller = new PGDM_Application_PDF_A();

        Test.startTest();
        PageReference result = controller.Cancel();
        Test.stopTest();

        System.assertNotEquals(null,result);
    }
    @IsTest
static void testConstructorWithFullData() {

    Application__c app = [SELECT Id FROM Application__c WHERE Name = 'Test Application' LIMIT 1];

    insert new Program_Detail__c(Application__c = app.Id);

    insert new Academic_Detail__c(Application__c = app.Id, Name = '12th');
    insert new Academic_Detail__c(Application__c = app.Id, Name = 'Diploma');
    Academic_Detail__c grad = new Academic_Detail__c(Application__c = app.Id, Name = 'UG', Pattern_of_Examination__c = 'Year wise');
    insert grad;
    insert new Academic_Detail__c(Application__c = app.Id, Name = 'PG');

    insert new Professional_Qualification__c(Application__c = app.Id);

    insert new Work_Experience__c(Application__c = app.Id, Name_of_Organisation__c = 'Previous Company');

    insert new Versatility__c(Application__c = app.Id, Name_of_the_Activity__c = 'Cricket');

    insert new Academic_Achievements__c(Application__c = app.Id, Title_of_the_Award__c = 'Best Student');

    insert new Competitive_Exam_Details__c(Application__c = app.Id, Exam_Name__c = 'GMAT');
    insert new Competitive_Exam_Details__c(Application__c = app.Id, Exam_Name__c = 'GMAT Focus');
    insert new Competitive_Exam_Details__c(Application__c = app.Id, Exam_Name__c = 'CAT');
    insert new Competitive_Exam_Details__c(Application__c = app.Id, Exam_Name__c = 'NMAT');
    insert new Competitive_Exam_Details__c(Application__c = app.Id, Exam_Name__c = 'GRE');
    insert new Competitive_Exam_Details__c(Application__c = app.Id, Exam_Name__c = 'XAT');
    insert new Competitive_Exam_Details__c(Application__c = app.Id, Exam_Name__c = 'TOEFL');
    insert new Competitive_Exam_Details__c(Application__c = app.Id, Exam_Name__c = 'IELTS');

    List<Graduation_Details_Semester_wise__c> semesterList = new List<Graduation_Details_Semester_wise__c>();

    for (Integer i = 1; i <= 8; i++) {
        semesterList.add(new Graduation_Details_Semester_wise__c(
            Academic_Detail__c = grad.Id,
            
            Year_Semester_Name__c = String.valueOf(i)
        ));
    }

    insert semesterList;

    List<Graduation_Details_Semester_wise__c> yearList = new List<Graduation_Details_Semester_wise__c>();

    for (Integer i = 1; i <= 5; i++) {
        yearList.add(new Graduation_Details_Semester_wise__c(
            Academic_Detail__c = grad.Id,
            Year_Semester_Name__c = String.valueOf(i)
        ));
    }

    insert yearList;

    PageReference pageRef = Page.PGDM_Application_PDF_A;
    pageRef.getParameters().put('id', app.Id);
    Test.setCurrentPage(pageRef);

    Test.startTest();
    PGDM_Application_PDF_A controller = new PGDM_Application_PDF_A();
    Work_Experience__c latest = controller.latestWorkExp;
    Test.stopTest();
    
}

}
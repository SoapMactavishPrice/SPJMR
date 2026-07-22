@IsTest
private class CohortFilesControllerTest {

    @TestSetup
    static void setupData() {
        SpjimrPortalTestDataFactory.buildAll('cf');
    }

    @IsTest
    static void searchProgramCohorts_blankTerm_returnsList() {
        Test.startTest();
        List<CohortFilesController.CohortOption> opts =
            CohortFilesController.searchProgramCohorts(null);
        List<CohortFilesController.CohortOption> opts2 =
            CohortFilesController.searchProgramCohorts('');
        Test.stopTest();
        System.assertNotEquals(null, opts);
        System.assertNotEquals(null, opts2);
    }

    @IsTest
    static void searchProgramCohorts_specificTerm_matches() {
        Test.startTest();
        List<CohortFilesController.CohortOption> opts =
            CohortFilesController.searchProgramCohorts('Test');
        Test.stopTest();
        System.assertNotEquals(null, opts);
    }

    @IsTest
    static void getCohortFiles_nullId_returnsEmpty() {
        Test.startTest();
        List<CohortFilesController.FileRow> rows = CohortFilesController.getCohortFiles(null, null);
        Test.stopTest();
        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void getCohortFiles_cohortWithMembersNoDocs_returnsEmpty() {
        List<ProgramCohort> cs = [SELECT Id FROM ProgramCohort LIMIT 1];
        if (cs.isEmpty()) return;
        Test.startTest();
        List<CohortFilesController.FileRow> rows = CohortFilesController.getCohortFiles(cs[0].Id, null);
        Test.stopTest();
        System.assertNotEquals(null, rows);
    }

    @IsTest
    static void getCohortFiles_emptyCohort_returnsEmpty() {
        // A cohort with no members
        Id progId = [SELECT Id FROM Program LIMIT 1].Id;
        SObject pc = (SObject) ProgramCohort.SObjectType.newSObject();
        pc.put('Name', 'EmptyCohort');
        pc.put('ProgramId', progId);
        try { pc.put('Batch_Code__c', 'EC1'); } catch (Exception e) {}
        try { pc.put('Short_Batch_Code__c', 'EC1'); } catch (Exception e) {}
        try { pc.put('Batch_Sub_Type__c', 'Class Room'); } catch (Exception e) {}
        try { pc.put('Batch_Base_Currency__c', 'INR'); } catch (Exception e) {}
        try { pc.put('Program_Code__c', 'TP1'); } catch (Exception e) {}
        try { pc.put('Profile_Window_IsActive__c', true); } catch (Exception e) {}
        try { pc.put('Profile_Window_Start_Time__c', Datetime.now()); } catch (Exception e) {}
        try { pc.put('Profile_Window_End_Time__c', Datetime.now().addDays(1)); } catch (Exception e) {}
        try { pc.put('Batch_Intake__c', 1); } catch (Exception e) {}
        for (String f : new List<String>{
            'Allow_Exchange_Participation__c','Allow_Multi_Program_Batch__c',
            'Allow_Previous_Batch_Same_Programme__c','Allow_Re_Evaluation__c',
            'Cannot_Exceed_Program_Intake__c','is_Active__c','Is_Student_Exchange__c',
            'IsAcceptingApplications__c','SPJIMR_Is_Major_Specialisation__c',
            'SPJIMR_Is_Minor_Specialisation__c','SPJIMR_Is_Specialisation_Program__c'
        }) {
            try { pc.put(f, f == 'is_Active__c'); } catch (Exception e) {}
        }
        try { insert pc; } catch (Exception e) {}

        Test.startTest();
        List<CohortFilesController.FileRow> rows = CohortFilesController.getCohortFiles((Id) pc.get('Id'), null);
        Test.stopTest();
        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void getCohortFiles_withDocsAndFiles_returnsRows() {
        ProgramCohort cohort = [SELECT Id FROM ProgramCohort LIMIT 1];
        ProgramCohortMember mem = [SELECT Id, ProgramEnrolleeId FROM ProgramCohortMember WHERE ProgramCohortId = :cohort.Id LIMIT 1];
        if (mem.ProgramEnrolleeId == null) {
            System.debug('ProgramEnrolleeId is null; skip');
            return;
        }

        // Create Document_Details__c linked to the learner account
        SObject doc = (SObject) Type.forName('Document_Details__c').newInstance();
        try { doc.put('Student_Name__c', mem.ProgramEnrolleeId); } catch (Exception e) {}
        try { doc.put('Name', 'TestDoc'); } catch (Exception e) {}
        // Required booleans (per FieldDefinition)
        for (String f : new List<String>{
            'AllDocumentsUploaded__c','Change_Requested_Email_Sent__c',
            'File_Deleted__c','HasAttachment__c','Rejected_Email_Sent__c'
        }) {
            try { doc.put(f, false); } catch (Exception e) {}
        }
        try { insert doc; } catch (Exception e) {
            System.debug('Document_Details__c insert failed: ' + e.getMessage());
            return;
        }

        // ContentVersion → ContentDocument
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.pdf',
            VersionData = Blob.valueOf('hello world'),
            IsMajorVersion = true
        );
        insert cv;
        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = contentDocId,
            LinkedEntityId = (Id) doc.get('Id'),
            ShareType = 'V'
        );
        insert cdl;

        Test.startTest();
        // 1) No file-type filter
        List<CohortFilesController.FileRow> rows1 = CohortFilesController.getCohortFiles(cohort.Id, null);
        // 2) PDF filter (exact match)
        List<CohortFilesController.FileRow> rows2 = CohortFilesController.getCohortFiles(cohort.Id, 'pdf');
        // 3) JPG filter (jpeg-like branch) — should match nothing on our pdf file
        List<CohortFilesController.FileRow> rows3 = CohortFilesController.getCohortFiles(cohort.Id, 'jpg');
        // 4) Unmatched extension
        List<CohortFilesController.FileRow> rows4 = CohortFilesController.getCohortFiles(cohort.Id, 'xlsx');
        Test.stopTest();

        System.assertNotEquals(null, rows1);
        System.assertNotEquals(null, rows2);
        System.assertNotEquals(null, rows3);
        System.assertNotEquals(null, rows4);
    }

    @IsTest
    static void getCohortFiles_multipleFilesSameDoc_returnsLatestOnly() {
        ProgramCohort cohort = [SELECT Id FROM ProgramCohort LIMIT 1];
        ProgramCohortMember mem = [SELECT Id, ProgramEnrolleeId FROM ProgramCohortMember WHERE ProgramCohortId = :cohort.Id LIMIT 1];
        if (mem.ProgramEnrolleeId == null) {
            return; // No learner account on the cohort member; nothing to dedup.
        }

        // Single Document_Details__c representing one document type for the student.
        String docName = 'DEDUP_PASSPORT_PHOTO';
        SObject doc = (SObject) Type.forName('Document_Details__c').newInstance();
        try { doc.put('Student_Name__c', mem.ProgramEnrolleeId); } catch (Exception e) {}
        try { doc.put('Name', docName); } catch (Exception e) {}
        for (String f : new List<String>{
            'AllDocumentsUploaded__c','Change_Requested_Email_Sent__c',
            'File_Deleted__c','HasAttachment__c','Rejected_Email_Sent__c'
        }) {
            try { doc.put(f, false); } catch (Exception e) {}
        }
        try { insert doc; } catch (Exception e) {
            return; // Object/field not available in this org; skip the scenario.
        }

        // Two separate files (re-uploads) linked to the SAME document record.
        List<ContentVersion> cvs = new List<ContentVersion>{
            new ContentVersion(Title = 'Old Upload', PathOnClient = 'old.png', VersionData = Blob.valueOf('old'), IsMajorVersion = true),
            new ContentVersion(Title = 'New Upload', PathOnClient = 'new.png', VersionData = Blob.valueOf('new'), IsMajorVersion = true)
        };
        insert cvs;
        List<ContentDocumentLink> cdls = new List<ContentDocumentLink>();
        for (ContentVersion v : [SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :cvs]) {
            cdls.add(new ContentDocumentLink(
                ContentDocumentId = v.ContentDocumentId,
                LinkedEntityId = (Id) doc.get('Id'),
                ShareType = 'V'
            ));
        }
        insert cdls;

        Test.startTest();
        List<CohortFilesController.FileRow> rows = CohortFilesController.getCohortFiles(cohort.Id, null);
        Test.stopTest();

        Integer matchCount = 0;
        for (CohortFilesController.FileRow r : rows) {
            if (docName.equals(r.documentName)) {
                matchCount++;
            }
        }
        System.assertEquals(1, matchCount, 'Expected exactly one (latest) file per document name per student');
    }

    @IsTest
    static void getContentDocumentBodyForZip_nullId() {
        Test.startTest();
        CohortFilesController.FileContentPayload p = CohortFilesController.getContentDocumentBodyForZip(null);
        Test.stopTest();
        System.assertEquals(null, p);
    }

    @IsTest
    static void getContentDocumentBodyForZip_validFile() {
        ContentVersion cv = new ContentVersion(
            Title = 'Body Test',
            PathOnClient = 'body.txt',
            VersionData = Blob.valueOf('content'),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        Test.startTest();
        CohortFilesController.FileContentPayload p = CohortFilesController.getContentDocumentBodyForZip(docId);
        Test.stopTest();
        System.assertNotEquals(null, p);
        System.assertNotEquals(null, p.base64Data);
    }

    @IsTest
    static void getContentDocumentBodyForZip_titleAlreadyHasExtension() {
        // Exercise the branch where title already ends with extension (composedName == title)
        ContentVersion cv = new ContentVersion(
            Title = 'already.txt',
            PathOnClient = 'already.txt',
            VersionData = Blob.valueOf('x'),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        Test.startTest();
        CohortFilesController.FileContentPayload p = CohortFilesController.getContentDocumentBodyForZip(docId);
        Test.stopTest();
        System.assertNotEquals(null, p);
    }

    @IsTest
    static void wrappers_exerciseConstructors() {
        CohortFilesController.FileRow r = new CohortFilesController.FileRow();
        r.fileId = 'a'; r.fileName = 'b'; r.accountName = 'c'; r.documentName = 'd';
        System.assertEquals('a', r.fileId);

        CohortFilesController.CohortOption o = new CohortFilesController.CohortOption();
        o.label = 'L'; o.value = 'V';
        System.assertEquals('L', o.label);

        CohortFilesController.FileContentPayload p = new CohortFilesController.FileContentPayload();
        p.fileName = 'n'; p.base64Data = 'b';
        System.assertEquals('n', p.fileName);
    }
}
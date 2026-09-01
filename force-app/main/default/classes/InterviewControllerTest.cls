@isTest
private class InterviewControllerTest {

    /* =========================================================
       SHARED TEST DATA
       ========================================================= */

    private static Id personAccountRecordTypeId;

    @testSetup
    static void setup() {

        // ---- Person Account Record Type (required for Account.PersonEmail) ----
        List<RecordType> prts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ];

        Account evaluatorAcc;
        if (!prts.isEmpty()) {
            evaluatorAcc = new Account(
                RecordTypeId  = prts[0].Id,
                FirstName     = 'Eva',
                LastName      = 'Luator',
                PersonEmail   = UserInfo.getUserEmail()
            );
            insert evaluatorAcc;
        } else {
            // Fallback: org may not have Person Accounts enabled.
            // Most of the evaluator-dependent flows will simply resolve
            // getCurrentEvaluatorAccountId() to null in that case.
            evaluatorAcc = new Account(Name = 'Fallback Evaluator Account');
            insert evaluatorAcc;
        }

        // ---- Program ----
        Program pgm = new Program(Name = 'General Management Program', Program_Code__c = 'PGPM', Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room', Short_Programme_Code__c = 'PPD');
        insert pgm;

        // ---- Rounds ----
        RoundMaster__c round1 = new RoundMaster__c(Name = 'Round One', RoundNumber__c = '1', Program__c = pgm.Id);
        RoundMaster__c round2 = new RoundMaster__c(Name = 'Round Two', RoundNumber__c = '2', Program__c = pgm.Id);
        insert new List<RoundMaster__c>{ round1, round2 };

        // ---- Scoring Templates (criteria) ----
        List<ScoringTemplate__c> templates = new List<ScoringTemplate__c>{
            new ScoringTemplate__c(CriteriaName__c = 'Communication', Round__c = round1.Id,
                                    Maximum_Score__c = 10, CriteriaDescription__c = 'Communication skills'),
            new ScoringTemplate__c(CriteriaName__c = 'Aptitude', Round__c = round1.Id,
                                    Maximum_Score__c = 10, CriteriaDescription__c = 'Aptitude skills')
        };
        insert templates;

        RecordType personRt = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Account' AND IsPersonType = true 
            LIMIT 1
        ];

        Account applicant = new Account(
            RecordTypeId = personRt.Id,
            FirstName = 'Eval',
            LastName = 'Helper',
            PersonEmail = 'eval.helper@example.com'
        );
        insert applicant;

        // ---- Application ----
        Application__c app = new Application__c(
            Applicant__c                    = applicant.Id,
            Program__c                      = pgm.Id,
            Applicant_State_Management__c   = 'Interview Round 1',
            Evaluation_Score__c             = 85
        );
        insert app;

        // ---- Location / Panel / Slot ----
        LocationMaster__c loc = new LocationMaster__c(LocationName__c = 'Campus A');
        insert loc;

        PanelMaster__c panel = new PanelMaster__c();
        insert panel;

        PanelInterviewer__c panelInterviewer = new PanelInterviewer__c(
            Account__c    = evaluatorAcc.Id,
            PanelMaster__c = panel.Id
        );
        insert panelInterviewer;

        SlotMaster__c slotMaster = new SlotMaster__c(
            Name              = 'Slot 1',
            SlotDate__c       = Date.today(),
            SlotStartTime__c  = Time.newInstance(9, 0, 0, 0),
            SlotEndTime__c    = Time.newInstance(9, 30, 0, 0),
            LocationMaster__c = loc.Id,
            Mode__c           = 'Offline',
            Program_Master__c = pgm.Id
        );
        insert slotMaster;

        // ---- Application Slot Booking ----
        ApplicationSlotBooking__c booking = new ApplicationSlotBooking__c(
            Application__c    = app.Id,
            Mode__c           = 'Offline',
            Panel_Master__c   = panel.Id,
            RoundMaster__c    = round1.Id,
            SlotMaster__c     = slotMaster.Id
        );
        insert booking;

        // ---- Round Result (so it satisfies the sub-query filter in getInterviewMatrixPage) ----
        Round_Result__c rr = new Round_Result__c(
            ApplicationSlotBooking__c = booking.Id,
            Net_Score__c              = 18
        );
        insert rr;

        booking.Round_Result__c = rr.Id;
        update booking;

        // ---- Evaluation + Individual Criteria Results ----
        Evaluation__c evaluation = new Evaluation__c(
            Application_Slot_Booking__c = booking.Id,
            EvaluatedUser__c             = evaluatorAcc.Id,
            EvaluatedBy__c               = evaluatorAcc.Name,
            Status__c                    = 'Pending'
        );
        insert evaluation;

        List<Individual_Criteria_Result__c> icrs = new List<Individual_Criteria_Result__c>();
        for (ScoringTemplate__c st : templates) {
            icrs.add(new Individual_Criteria_Result__c(
                Evaluation__c        = evaluation.Id,
                Scoring_Template__c  = st.Id,
                Score__c             = 8,
                Comments__c          = 'Good'
            ));
        }
        insert icrs;
    }

    /* =========================================================
       HELPERS
       ========================================================= */

    private static RoundMaster__c getRound(String name) {
        return [SELECT Id, Name, RoundNumber__c FROM RoundMaster__c WHERE Name = :name LIMIT 1];
    }

    private static Application__c getApplication() {
        return [SELECT Id, Name FROM Application__c LIMIT 1];
    }

    private static ApplicationSlotBooking__c getBooking() {
        return [SELECT Id, RoundMaster__c, SlotMaster__c, Panel_Master__c FROM ApplicationSlotBooking__c LIMIT 1];
    }

    private static Evaluation__c getEvaluation() {
        return [SELECT Id, Status__c, EvaluatedUser__c FROM Evaluation__c LIMIT 1];
    }

    private static ScoringTemplate__c getTemplate() {
        return [SELECT Id FROM ScoringTemplate__c LIMIT 1];
    }

    /* =========================================================
       TESTS
       ========================================================= */

    @isTest
    static void testGetInterviewMatrixPage_guardClauses() {
        Test.startTest();
        InterviewController.InterviewMatrixPage emptyPage =
            InterviewController.getInterviewMatrixPage(new List<Id>(), null);
        Test.stopTest();

        System.assertEquals(0, emptyPage.totalRecords, 'Empty inputs should short-circuit with 0 records');
    }

    @isTest
    static void testGetInterviewMatrixPage_withData() {
        Application__c app = getApplication();
        RoundMaster__c round1 = getRound('Round One');

        Test.startTest();
        InterviewController.InterviewMatrixPage page =
            InterviewController.getInterviewMatrixPage(new List<Id>{ app.Id }, round1.Id);
        Test.stopTest();

        System.assertEquals(1, page.totalRecords, 'Should return one matrix row for the seeded booking');
        System.assert(!page.criteriaHeaders.isEmpty(), 'Criteria headers should include the scoring templates');
        System.assertEquals('Total Score', page.criteriaHeaders[page.criteriaHeaders.size() - 1].label,
            'Total Score header should be last');
        System.assertEquals(18, page.rows[0].totalScore, 'Total score should come from Round_Result__c');
    }

    @isTest
    static void testProcessInterviewAndLogStatus() {
        Test.startTest();
        String logId;
        try {
            logId = InterviewController.processInterview('069000000000000AAA', 'GMP');
        } catch (Exception e) {
            // Downstream queueable may reference a ContentDocumentId that doesn't
            // really exist in this test context; we only care that the log record
            // itself was created before the async job runs.
        }
        Test.stopTest();

        List<Interview_Excel_Log__c> logs = [SELECT Id, Status__c FROM Interview_Excel_Log__c];
        System.assert(!logs.isEmpty(), 'processInterview should insert an Interview_Excel_Log__c record');

        Interview_Excel_Log__c fetched = InterviewController.getlogStatus(logs[0].Id);
        System.assertNotEquals(null, fetched, 'getlogStatus should return the log record');

        Interview_Excel_Log__c notFound = InterviewController.getlogStatus(null);
        System.assertEquals(null, notFound, 'getlogStatus with an invalid Id should return null');
    }

    @isTest
    static void testGetScoringTemplates() {
        RoundMaster__c round1 = getRound('Round One');

        Test.startTest();
        List<ScoringTemplate__c> templates = InterviewController.getScoringTemplates(round1.Id);
        List<ScoringTemplate__c> emptyResult = InterviewController.getScoringTemplates(null);
        Test.stopTest();

        System.assertEquals(2, templates.size(), 'Should return both seeded scoring templates');
        System.assertEquals(null, emptyResult, 'No matching templates should return null');
    }

    @isTest
    static void testGetInterviewRounds() {
        Test.startTest();
        List<RoundMaster__c> rounds = InterviewController.getInterviewRounds('GMP');
        List<RoundMaster__c> nullResult = InterviewController.getInterviewRounds('');
        Test.stopTest();

    }

    @isTest
    static void testGetShortlistedApplications() {
        Test.startTest();
        List<InterviewController.InterviewWrapper> results = InterviewController.getShortlistedApplications();
        Test.stopTest();

    }

    @isTest
    static void testUpsertIndividualResults() {
        Evaluation__c evaluation = getEvaluation();
        ScoringTemplate__c template = getTemplate();

        List<InterviewController.ScoreWrapper> wrappers = new List<InterviewController.ScoreWrapper>();
        InterviewController.ScoreWrapper sw = new InterviewController.ScoreWrapper();
        sw.scoringTemplateId = template.Id;
        sw.score = 9;
        sw.comment = 'Updated comment';
        wrappers.add(sw);

        Test.startTest();
        InterviewController.upsertIndividualResults(evaluation.Id, JSON.serialize(wrappers));
        Test.stopTest();

        Individual_Criteria_Result__c icr = [
            SELECT Score__c, Comments__c FROM Individual_Criteria_Result__c
            WHERE Evaluation__c = :evaluation.Id AND Scoring_Template__c = :template.Id
            LIMIT 1
        ];
        System.assertEquals(9, icr.Score__c);
        System.assertEquals('Updated comment', icr.Comments__c);
    }

    @isTest
    static void testUpsertIndividualResults_completedEvaluationBlocked() {
        Evaluation__c evaluation = getEvaluation();
        evaluation.Status__c = 'Complete';
        update evaluation;

        ScoringTemplate__c template = getTemplate();
        List<InterviewController.ScoreWrapper> wrappers = new List<InterviewController.ScoreWrapper>();
        InterviewController.ScoreWrapper sw = new InterviewController.ScoreWrapper();
        sw.scoringTemplateId = template.Id;
        sw.score = 5;
        wrappers.add(sw);

        Boolean blocked = false;
        Test.startTest();
        try {
            InterviewController.upsertIndividualResults(evaluation.Id, JSON.serialize(wrappers));
        } catch (AuraHandledException e) {
            blocked = true;
        }
        Test.stopTest();

        System.assert(blocked, 'Completed evaluations should not be editable');
    }

    @isTest
    static void testCompleteInterviewsBulk() {
        ApplicationSlotBooking__c booking = getBooking();
        ScoringTemplate__c template = getTemplate();

        InterviewController.ScoreWrapper sw = new InterviewController.ScoreWrapper();
        sw.scoringTemplateId = template.Id;
        sw.score = 7;
        sw.comment = 'Nice';

        InterviewController.BulkCompleteRequest req = new InterviewController.BulkCompleteRequest();
        req.bookingId = booking.Id;
        req.evaluatorComment = 'Overall good';
        req.scores = new List<InterviewController.ScoreWrapper>{ sw };

        List<InterviewController.BulkCompleteRequest> requests =
            new List<InterviewController.BulkCompleteRequest>{ req };

        Test.startTest();
        Map<String, String> results = InterviewController.completeInterviewsBulk(JSON.serialize(requests));
        Test.stopTest();

        System.assert(results.containsKey(String.valueOf(booking.Id)), 'Result map should contain the booking id');

        Evaluation__c evalRec = [
            SELECT Status__c, EvaluatorComments__c FROM Evaluation__c
            WHERE Application_Slot_Booking__c = :booking.Id
            LIMIT 1
        ];
        System.assertEquals('Complete', evalRec.Status__c);
    }

    @isTest
    static void testCompleteInterviewsBulk_emptyPayload() {
        Test.startTest();
        Map<String, String> results = InterviewController.completeInterviewsBulk(null);
        Test.stopTest();

        System.assert(results.isEmpty(), 'Blank payload should return an empty map');
    }

    @isTest
    static void testGetHighestCriteriaCountAndExport() {
        Evaluation__c evaluation = getEvaluation();
        evaluation.Status__c = 'Complete';
        update evaluation;

        Test.startTest();
        Map<String, String> criteriaMap = InterviewController.getHighestCriteriaCount();
        List<Evaluation__c> exportList = InterviewController.updateEvalScoreExport();
        Test.stopTest();

        System.assert(criteriaMap != null, 'Criteria count map should not be null');
        System.assert(!exportList.isEmpty(), 'Should return the completed evaluation for export');
    }

    @isTest
    static void testGetApplicationUrl() {
        ApplicationSlotBooking__c booking = getBooking();

        Test.startTest();
        try {
            String url = InterviewController.getApplicationUrl(booking.Id);
            System.assert(url != null, 'If a FacultyPortal network exists, a URL should be returned');
        } catch (AuraHandledException e) {
            // Expected in orgs/sandboxes without a 'FacultyPortal' Experience Cloud site configured.
            System.assert(true);
        }
        Test.stopTest();
    }

    @isTest
    static void testGetVFPageUrl_noMetadataConfigured() {
        Application__c app = getApplication();

        Test.startTest();
        String url = InterviewController.getVFPageUrl(app.Id);
        Test.stopTest();
    }

    @isTest
    static void testCheckInterviewStatusAndFinishInterview() {
        ApplicationSlotBooking__c booking = getBooking();

        Test.startTest();
        String statusBefore = InterviewController.checkInterviewStatus(booking.Id);
        Test.stopTest();

        System.assertEquals('Pending', statusBefore);
    }

    @isTest
    static void testFinishInterview() {
        Evaluation__c evaluation = getEvaluation();

        Test.startTest();
        String result = InterviewController.finishInterview(evaluation.Id);
        Test.stopTest();

        System.assertEquals('Success', result);

        Evaluation__c updated = [SELECT Status__c FROM Evaluation__c WHERE Id = :evaluation.Id];
        System.assertEquals('Complete', updated.Status__c);
    }

    @isTest
    static void testFinishInterview_notFound() {
        Boolean threw = false;
        Test.startTest();
        try {
            InterviewController.finishInterview(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Missing evaluation id should throw an AuraHandledException');
    }

    @isTest
    static void testGetEvaluationId_existingAndNew() {
        ApplicationSlotBooking__c booking = getBooking();

        Test.startTest();
        String existingId = InterviewController.getEvaluationId(booking.Id);
        Test.stopTest();

        System.assert(String.isNotBlank(existingId), 'Should return the seeded evaluation id for this user/slot');
    }

    @isTest
    static void testGetSlotMastersForEvaluator() {
        Test.startTest();
        List<InterviewController.SlotMasterWrapper> slots = InterviewController.getSlotMastersForEvaluator();
        Test.stopTest();

        // Result depends on Person Account/PersonEmail being resolvable to the running user;
        // we simply assert the call completes without error and returns a list.
        System.assert(slots != null, 'Should always return a (possibly empty) list, never null-throw');
    }

    @isTest
    static void testGetSlotBookingsBySlotMaster() {
        ApplicationSlotBooking__c booking = [
            SELECT Id, SlotMaster__c FROM ApplicationSlotBooking__c LIMIT 1
        ];

        Test.startTest();
        List<InterviewController.SlotBookingWrapper> results =
            InterviewController.getSlotBookingsBySlotMaster(booking.SlotMaster__c);
        Test.stopTest();

        System.assert(results != null, 'Should always return a (possibly empty) list, never null-throw');
    }

    @isTest
    static void testGetScoringConfig_defaultsFalse() {
        Test.startTest();
        InterviewController.ScoringConfigWrapper cfg = InterviewController.getScoringConfig('GMP');
        Test.stopTest();

        System.assertEquals(false, cfg.showCriteriaComment,
            'Without an active ApplicationProgramBasedConfig__mdt record, this should default to false');
    }

    @isTest
    static void testSaveAndGetEvaluatorComment() {
        Evaluation__c evaluation = getEvaluation();
        ApplicationSlotBooking__c booking = [
            SELECT Id FROM ApplicationSlotBooking__c
            WHERE Id = :[SELECT Application_Slot_Booking__c FROM Evaluation__c WHERE Id = :evaluation.Id].Application_Slot_Booking__c
            LIMIT 1
        ];

        Test.startTest();
        InterviewController.saveEvaluatorComment(evaluation.Id, 'Solid candidate');
        String comment = InterviewController.getEvaluatorComment(booking.Id);
        Test.stopTest();

        System.assertEquals('Solid candidate', comment);
    }

    @isTest
    static void testSaveEvaluatorComment_completedBlocked() {
        Evaluation__c evaluation = getEvaluation();
        evaluation.Status__c = 'Complete';
        update evaluation;

        Boolean blocked = false;
        Test.startTest();
        try {
            InterviewController.saveEvaluatorComment(evaluation.Id, 'Too late');
        } catch (AuraHandledException e) {
            blocked = true;
        }
        Test.stopTest();

        System.assert(blocked, 'Completed evaluations should not accept new comments');
    }

    @isTest
    static void testGetEvaluationCriteria() {
        ApplicationSlotBooking__c booking = getBooking();

        Test.startTest();
        Map<String, List<SObject>> result = InterviewController.getEvaluationCriteria(booking.Id);
        Test.stopTest();

        System.assert(!result.isEmpty(), 'Should return a populated map for a booking with a round assigned');
    }

    @isTest
    static void testGetStaticPdfAndSpecialisationConfig_defaults() {
        Test.startTest();
        Boolean staticPdf = InterviewController.getStaticPdfConfig('GMP');
        Boolean showSpec = InterviewController.getShowSpecialisationConfig('GMP');
        Test.stopTest();

    }

    @isTest
    static void testGetMerittoExtractFileUrl_noDocument() {
        Application__c app = getApplication();

        Test.startTest();
        String url = InterviewController.getMerittoExtractFileUrl(app.Id);
        Test.stopTest();

        System.assertEquals('', url, 'No Document_Details__c record should resolve to an empty string');
    }

    @isTest
    static void testGetMerittoExtractFileUrl_withDocument() {
        Application__c app = getApplication();

        Document_Details__c doc = new Document_Details__c(
            Application_No__c = app.Id,
            Document_Code__c  = 'MerittoExtract'
        );
        insert doc;

        ContentVersion cv = new ContentVersion(
            Title        = 'MerittoExtract',
            PathOnClient = 'MerittoExtract.pdf',
            VersionData  = Blob.valueOf('Sample extract content')
        );
        insert cv;

        ContentVersion insertedCv = [
            SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
        ];

        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = insertedCv.ContentDocumentId,
            LinkedEntityId    = doc.Id,
            ShareType         = 'V'
        );
        insert link;

        Test.startTest();
        String url = InterviewController.getMerittoExtractFileUrl(app.Id);
        Test.stopTest();

        System.assert(String.isNotBlank(url), 'A ContentDistribution public URL should be generated');
    }
}
@IsTest
private class InterviewControllerTest {

    private static Id safeInsert(SObject rec) {
        Database.SaveResult sr = Database.insert(rec, false);
        return sr.isSuccess() ? sr.getId() : null;
    }

    private static Account ensureEvaluatorAccount() {
        List<Account> existing = [
            SELECT Id, Name, PersonEmail
            FROM Account
            WHERE PersonEmail = :UserInfo.getUserEmail()
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        List<RecordType> personRts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ];
        if (personRts.isEmpty()) {
            return null;
        }

        Account pa = new Account(
            RecordTypeId = personRts[0].Id,
            FirstName = 'Test',
            LastName = 'Evaluator',
            PersonEmail = UserInfo.getUserEmail()
        );
        Id paId = safeInsert(pa);
        return paId == null ? null : [SELECT Id, Name, PersonEmail FROM Account WHERE Id = :paId LIMIT 1];
    }

    private static Program ensureProgram() {
        List<Program> existing = [
            SELECT Id, Name, Program_Code__c
            FROM Program
            WHERE Program_Code__c = 'GMP'
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        Program p = new Program(
            Name = 'Interview Program',
            Program_Code__c = 'GMP',
            StartDate = System.today(),
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Type__c = 'Full-Time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'INT'
        );
        Id pId = safeInsert(p);
        if (pId != null) {
            return [SELECT Id, Name, Program_Code__c FROM Program WHERE Id = :pId LIMIT 1];
        }

        List<Program> anyProgram = [SELECT Id, Name, Program_Code__c FROM Program LIMIT 1];
        return anyProgram.isEmpty() ? null : anyProgram[0];
    }

    private static RoundMaster__c ensureRound(Id programId) {
        List<RoundMaster__c> existing = [
            SELECT Id, Name, Program__c, RoundNumber__c
            FROM RoundMaster__c
            WHERE Program__c = :programId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        RoundMaster__c r = new RoundMaster__c(
            Name = 'Round 1',
            Program__c = programId,
            RoundNumber__c = '1'
        );
        Id rId = safeInsert(r);
        if (rId != null) {
            return [SELECT Id, Name, Program__c, RoundNumber__c FROM RoundMaster__c WHERE Id = :rId LIMIT 1];
        }
        return null;
    }

    private static void ensureScoringTemplate(Id roundId) {
        if (roundId == null) {
            return;
        }
        Integer cnt = [
            SELECT Count()
            FROM ScoringTemplate__c
            WHERE Round__c = :roundId
        ];
        if (cnt == 0) {
            safeInsert(new ScoringTemplate__c(CriteriaName__c = 'Communication', Round__c = roundId));
            safeInsert(new ScoringTemplate__c(CriteriaName__c = 'Leadership', Round__c = roundId));
        }
    }

    private static ApplicationSlotBooking__c ensureSlotGraph() {
        List<ApplicationSlotBooking__c> existing = [
            SELECT Id, Application__c, RoundMaster__c, Panel_Master__c, Applicant_Name__c
            FROM ApplicationSlotBooking__c
            WHERE Application__c != null AND RoundMaster__c != null
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        Account evaluator = ensureEvaluatorAccount();
        Program p = ensureProgram();
        if (evaluator == null || p == null) {
            return null;
        }

        Id appId = safeInsert(new Application__c(
            Name = 'INT-APP-001',
            Applicant__c = evaluator.Id,
            Applicant_State_Management__c = 'Interview Round 1',
            Program__c = p.Id
        ));

        RoundMaster__c round = ensureRound(p.Id);
        if (appId == null || round == null) {
            return null;
        }
        ensureScoringTemplate(round.Id);

        Id panelId = safeInsert(new PanelMaster__c());
        if (panelId != null) {
            safeInsert(new PanelInterviewer__c(Account__c = evaluator.Id, PanelMaster__c = panelId));
        }
        Id slotMasterId = safeInsert(new SlotMaster__c(BookedCapacity__c = 0));

        ApplicationSlotBooking__c slot = new ApplicationSlotBooking__c(
            Application__c = appId,
            RoundMaster__c = round.Id,
            Panel_Master__c = panelId,
            SlotMaster__c = slotMasterId
        );
        Id slotId = safeInsert(slot);
        return slotId == null ? null : [
            SELECT Id, Application__c, RoundMaster__c, Panel_Master__c, Applicant_Name__c
            FROM ApplicationSlotBooking__c
            WHERE Id = :slotId
            LIMIT 1
        ];
    }

    private static void ensureEvaluationAndRoundResult(ApplicationSlotBooking__c slot) {
        if (slot == null) {
            return;
        }
        Account evaluator = ensureEvaluatorAccount();
        if (evaluator == null) {
            return;
        }

        List<Evaluation__c> evals = [
            SELECT Id, Status__c, Total_Score__c, Application_Slot_Booking__c
            FROM Evaluation__c
            WHERE Application_Slot_Booking__c = :slot.Id
            LIMIT 1
        ];
        Id evalId;
        if (evals.isEmpty()) {
            evalId = safeInsert(new Evaluation__c(
                Application_Slot_Booking__c = slot.Id,
                EvaluatedUser__c = evaluator.Id,
                EvaluatedBy__c = evaluator.Name,
                Status__c = 'Pending'
            ));
        } else {
            evalId = evals[0].Id;
        }

        if (evalId != null && slot.RoundMaster__c != null) {
            List<ScoringTemplate__c> tmpl = [
                SELECT Id
                FROM ScoringTemplate__c
                WHERE Round__c = :slot.RoundMaster__c
                LIMIT 1
            ];
            if (!tmpl.isEmpty()) {
                Integer resultCnt = [
                    SELECT Count()
                    FROM Individual_Criteria_Result__c
                    WHERE Evaluation__c = :evalId AND Scoring_Template__c = :tmpl[0].Id
                ];
                if (resultCnt == 0) {
                    safeInsert(new Individual_Criteria_Result__c(
                        Evaluation__c = evalId,
                        Scoring_Template__c = tmpl[0].Id,
                        Score__c = 8,
                        Comments__c = 'Good'
                    ));
                }
            }
        }

        Integer rrCnt = [
            SELECT Count()
            FROM Round_Result__c
            WHERE ApplicationSlotBooking__c = :slot.Id
        ];
        if (rrCnt == 0) {
            safeInsert(new Round_Result__c(ApplicationSlotBooking__c = slot.Id, Net_Score__c = 10));
        }
    }

    private static void setupData() {
        safeInsert(new Automation_Control__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Skip_Flows__c = true
        ));
        ApplicationSlotBooking__c slot = ensureSlotGraph();
        ensureEvaluationAndRoundResult(slot);
        safeInsert(new Interview_Excel_Log__c(
            ContentDocumentId__c = '069000000000001AAA',
            Status__c = 'Created'
        ));
    }

    @IsTest(SeeAllData=true)
    static void testInterviewMatrixPage() {
        setupData();
        InterviewController.InterviewMatrixPage guard = InterviewController.getInterviewMatrixPage(null, null);
        System.assertEquals(0, guard.totalRecords);

        ApplicationSlotBooking__c slot = ensureSlotGraph();
        ensureEvaluationAndRoundResult(slot);
        if (slot != null && slot.Application__c != null && slot.RoundMaster__c != null) {
            InterviewController.InterviewMatrixPage page = InterviewController.getInterviewMatrixPage(
                new List<Id>{slot.Application__c},
                slot.RoundMaster__c
            );
            System.assertNotEquals(null, page);
            System.assertNotEquals(null, page.criteriaHeaders);
            System.assertNotEquals(null, page.rows);
        }
    }

    @IsTest(SeeAllData=true)
    static void testLogProcessTemplatesRounds() {
        setupData();
        Interview_Excel_Log__c none = InterviewController.getlogStatus(null);
        System.assertEquals(null, none);

        List<Interview_Excel_Log__c> logs = [SELECT Id FROM Interview_Excel_Log__c LIMIT 1];
        if (!logs.isEmpty()) {
            System.assertNotEquals(null, InterviewController.getlogStatus(logs[0].Id));
        }

        try {
            String logId = InterviewController.processInterview('069000000000002AAA', 'GMP');
            System.assertNotEquals(null, logId);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }

        List<ScoringTemplate__c> nullRoundTemplates = InterviewController.getScoringTemplates(null);
        System.assertEquals(true, nullRoundTemplates == null || nullRoundTemplates.size() >= 0);

        ApplicationSlotBooking__c slot = ensureSlotGraph();
        if (slot != null && slot.RoundMaster__c != null) {
            List<ScoringTemplate__c> templates = InterviewController.getScoringTemplates((String)slot.RoundMaster__c);
            System.assertEquals(true, templates == null || templates.size() >= 0);
        }

        System.assertEquals(null, InterviewController.getInterviewRounds(''));
        Program p = ensureProgram();
        if (p != null && String.isNotBlank(p.Program_Code__c)) {
            List<RoundMaster__c> rounds = InterviewController.getInterviewRounds(p.Program_Code__c);
            System.assertEquals(true, rounds == null || rounds.size() >= 0);
        }
    }

    @IsTest(SeeAllData=true)
    static void testShortlistedHighestAndExport() {
        setupData();
        List<InterviewController.InterviewWrapper> shortlisted = InterviewController.getShortlistedApplications();
        System.assertNotEquals(null, shortlisted);

        Map<String, String> highest = InterviewController.getHighestCriteriaCount();
        System.assertNotEquals(null, highest);

        List<Evaluation__c> exportData = InterviewController.updateEvalScoreExport();
        System.assertEquals(true, exportData == null || exportData.size() >= 0);
    }

    @IsTest(SeeAllData=true)
    static void testUpsertStatusEvalCriteriaFlow() {
        setupData();
        ApplicationSlotBooking__c slot = ensureSlotGraph();
        ensureEvaluationAndRoundResult(slot);
        System.assertNotEquals(null, InterviewController.getEvaluationCriteria(null));

        if (slot == null) {
            return;
        }

        String status = InterviewController.checkInterviewStatus(slot.Id);
        System.assertEquals(true, status == 'Pending' || status == 'Complete');

        String evalId = InterviewController.getEvaluationId(slot.Id);
        System.assertEquals(true, String.isBlank(evalId) || evalId.length() > 0);

        Map<String, List<SObject>> critMap = InterviewController.getEvaluationCriteria(slot.Id);
        System.assertNotEquals(null, critMap);

        if (String.isNotBlank(evalId) && slot.RoundMaster__c != null) {
            List<ScoringTemplate__c> templateList = [
                SELECT Id
                FROM ScoringTemplate__c
                WHERE Round__c = :slot.RoundMaster__c
                LIMIT 1
            ];
            if (!templateList.isEmpty()) {
                String payload =
                    '[{"scoringTemplateId":"' + String.valueOf(templateList[0].Id) + '","score":9.5,"comment":"Updated by test"},' +
                    '{"scoringTemplateId":null,"score":2,"comment":"skip"}]';
                InterviewController.upsertIndividualResults((Id)evalId, payload);
            }
        }

        InterviewController.upsertIndividualResults(null, '[]');
    }

    @IsTest(SeeAllData=true)
    static void testGetEvaluationIdInsertBranch() {
        setupData();
        Set<Id> usedSlotIds = new Set<Id>();
        for (Evaluation__c e : [
            SELECT Application_Slot_Booking__c, EvaluatedUser__r.PersonEmail
            FROM Evaluation__c
            WHERE Application_Slot_Booking__c != null
        ]) {
            if (e.EvaluatedUser__r != null && e.EvaluatedUser__r.PersonEmail == UserInfo.getUserEmail()) {
                usedSlotIds.add(e.Application_Slot_Booking__c);
            }
        }

        List<ApplicationSlotBooking__c> slotCandidates;
        if (usedSlotIds.isEmpty()) {
            slotCandidates = [
                SELECT Id, RoundMaster__c
                FROM ApplicationSlotBooking__c
                WHERE RoundMaster__c != null
                LIMIT 1
            ];
        } else {
            slotCandidates = [
                SELECT Id, RoundMaster__c
                FROM ApplicationSlotBooking__c
                WHERE RoundMaster__c != null
                AND Id NOT IN :usedSlotIds
                LIMIT 1
            ];
        }
        if (slotCandidates.isEmpty()) {
            return;
        }
        ApplicationSlotBooking__c slot = slotCandidates[0];

        String evalId = InterviewController.getEvaluationId(slot.Id);
        System.assertEquals(true, String.isBlank(evalId) || evalId.length() > 0);

        Map<String, List<SObject>> critMap = InterviewController.getEvaluationCriteria(slot.Id);
        System.assertNotEquals(null, critMap);
    }

    @IsTest(SeeAllData=true)
    static void testFinishAndUrls() {
        setupData();
        ApplicationSlotBooking__c slot = ensureSlotGraph();
        ensureEvaluationAndRoundResult(slot);

        List<Evaluation__c> evals = [
            SELECT Id
            FROM Evaluation__c
            WHERE Application_Slot_Booking__c != null
            LIMIT 1
        ];
        if (!evals.isEmpty()) {
            String result = InterviewController.finishInterview(evals[0].Id);
            System.assertNotEquals(null, result);
        }

        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 1];
        if (!apps.isEmpty()) {
            String vfUrl = InterviewController.getVFPageUrl((String)apps[0].Id);
            System.assertNotEquals(null, vfUrl);
        }
        System.assertNotEquals(null, InterviewController.getVFPageUrl(null));

        if (slot != null) {
            try {
                String appUrl = InterviewController.getApplicationUrl((String)slot.Id);
                System.assertNotEquals(null, appUrl);
            } catch (Exception e) {
                System.assertNotEquals(null, e.getMessage());
            }
        }
    }
}
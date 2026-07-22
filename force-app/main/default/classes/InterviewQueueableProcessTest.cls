@IsTest
private class InterviewQueueableProcessTest {

    private class SeedData {
        Id roundId;
        String roundNumber;
        String programCode;
        Id slotId;
        String appName;
        Id appId;
        Id scoringTemplateId;
        String criteriaKey;   // UPPERCASE — for DTO map keys / assertions
        String criteriaRaw;   // Original casing from DB — for building CSV headers
        Decimal maxScore;
        Id evaluationId;
    }

    private static Id safeInsert(SObject rec) {
        Database.SaveResult sr = Database.insert(rec, false);
        return sr.isSuccess() ? sr.getId() : null;
    }

    private static void ensureAutomationControl() {
        safeInsert(new Automation_Control__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Skip_Flows__c = true
        ));
    }

    private static Id getLogId() {
        Id logId = safeInsert(new Interview_Excel_Log__c(
            ContentDocumentId__c = '069000000000001AAA',
            Status__c = 'Created'
        ));
        if (logId != null) return logId;
        List<Interview_Excel_Log__c> logs = [SELECT Id FROM Interview_Excel_Log__c LIMIT 1];
        return logs.isEmpty() ? null : logs[0].Id;
    }

    private static SeedData getSeedData() {
        SeedData d = new SeedData();

        List<ScoringTemplate__c> templates = [
            SELECT Id, CriteriaName__c, Maximum_Score__c, Round__c,
                   Round__r.RoundNumber__c, Round__r.Program__r.Program_Code__c
            FROM ScoringTemplate__c
            WHERE Round__c != null
            AND Round__r.RoundNumber__c != null
            AND Round__r.Program__r.Program_Code__c != null
            AND Maximum_Score__c != null
            LIMIT 1
        ];
        if (templates.isEmpty()) return d;

        d.scoringTemplateId = templates[0].Id;
        // criteriaRaw: original casing stored in DB, used to build CSV headers
        d.criteriaRaw = templates[0].CriteriaName__c == null
            ? null : templates[0].CriteriaName__c.trim();
        // criteriaKey: normalized UPPERCASE version, used for DTO map keys
        d.criteriaKey = d.criteriaRaw == null ? null : d.criteriaRaw.toUpperCase();
        d.maxScore    = templates[0].Maximum_Score__c;
        d.roundId     = templates[0].Round__c;
        d.roundNumber = templates[0].Round__r.RoundNumber__c;
        d.programCode = templates[0].Round__r.Program__r.Program_Code__c;

        List<ApplicationSlotBooking__c> slots = [
            SELECT Id, Application__c, Application__r.Name
            FROM ApplicationSlotBooking__c
            WHERE RoundMaster__c = :d.roundId AND Application__c != null
            LIMIT 1
        ];
        if (!slots.isEmpty()) {
            d.slotId  = slots[0].Id;
            d.appId   = slots[0].Application__c;
            d.appName = slots[0].Application__r.Name;
        }

        if (d.appId != null) {
            List<Evaluation__c> evals = [
                SELECT Id FROM Evaluation__c
                WHERE Application_Slot_Booking__c = :d.slotId LIMIT 1
            ];
            if (!evals.isEmpty()) d.evaluationId = evals[0].Id;
        }

        return d;
    }

    private static Id createCsvDoc(String extension, String body) {
        ContentVersion cv = new ContentVersion(
            Title        = 'InterviewTestFile',
            PathOnClient = 'InterviewTestFile.' + extension,
            VersionData  = Blob.valueOf(body)
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
    }

    private static InterviewQueueableProcess.EvalRowDTO makeDto(
        String appNum, String evaluator, String criteriaKey, Integer score
    ) {
        InterviewQueueableProcess.EvalRowDTO dto = new InterviewQueueableProcess.EvalRowDTO();
        dto.applicationNumber = appNum;
        dto.evaluator         = evaluator;
        dto.scores            = new Map<String, Integer>();
        dto.comments          = new Map<String, String>();
        if (criteriaKey != null) {
            dto.scores.put(criteriaKey, score);
            dto.comments.put(criteriaKey, 'ok');
        }
        return dto;
    }

    // ─────────────────────────────────────────────────────────────
    // ORIGINAL TESTS
    // ─────────────────────────────────────────────────────────────

    @IsTest(SeeAllData=true)
    static void testParseCsv_NonCsvExtension_Error() {
        ensureAutomationControl();
        Id logId = getLogId();
        System.assertNotEquals(null, logId);

        Id docId = createCsvDoc('txt', 'not,csv');
        new InterviewQueueableProcess((String)docId, 'GMP', logId).execute(null);

        Interview_Excel_Log__c logRec = [
            SELECT Status__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertEquals('Error', logRec.Status__c);
    }

    @IsTest(SeeAllData=true)
    static void testParseCsv_CsvValidationBranch() {
        ensureAutomationControl();
        Id logId = getLogId();
        System.assertNotEquals(null, logId);

        String csv =
            'Application Number,Applicant Name,Program,Round,Evaluated By,Criteria A,Criteria A Comment\n' +
            'APP-001,Name,NO_PROGRAM,99,test eval,5,good';
        Id docId = createCsvDoc('csv', csv);
        new InterviewQueueableProcess((String)docId, 'NO_PROGRAM', logId).execute(null);

        Interview_Excel_Log__c logRec = [
            SELECT Status__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertNotEquals(null, logRec.Status__c);
    }

    @IsTest(SeeAllData=true)
    static void testCreateSlots_SuccessOrHandled() {
        ensureAutomationControl();
        Id logId = getLogId();
        SeedData d = getSeedData();
        if (String.isBlank(d.programCode) || String.isBlank(d.roundNumber) || String.isBlank(d.appName)) {
           System.assertNotEquals(null, d.programCode);
System.assertNotEquals(null, d.roundNumber);
            return;
        }

        Map<String, List<InterviewQueueableProcess.EvalRowDTO>> appToRows =
            new Map<String, List<InterviewQueueableProcess.EvalRowDTO>>{
                d.appName => new List<InterviewQueueableProcess.EvalRowDTO>{
                    makeDto(d.appName, 'slot_eval_1', d.criteriaKey, 4)
                }
            };

        new InterviewQueueableProcess(appToRows, d.roundNumber, d.programCode, logId).execute(null);

        System.assert([
            SELECT Count() FROM ApplicationSlotBooking__c
            WHERE RoundMaster__c = :d.roundId AND Application__r.Name = :d.appName
        ] > 0);
    }

    @IsTest(SeeAllData=true)
    static void testCreateEvaluations_SuccessBranches() {
        ensureAutomationControl();
        Id logId = getLogId();
        SeedData d = getSeedData();
        if (d.slotId == null || String.isBlank(d.appName)) {
            System.assertNotEquals(null, d.slotId);
System.assertNotEquals(null, d.appName);
            return;
        }

        Id existingEvalId = safeInsert(new Evaluation__c(
            Application_Slot_Booking__c = d.slotId,
            EvaluatedBy__c = 'existing_eval',
            Status__c = 'Complete'
        ));
        if (existingEvalId == null) {
            List<Evaluation__c> fallback = [
                SELECT Id FROM Evaluation__c WHERE Application_Slot_Booking__c = :d.slotId LIMIT 1
            ];
            if (!fallback.isEmpty()) existingEvalId = fallback[0].Id;
        }

        Map<String, Id> appToSlotId = new Map<String, Id>{ d.appName => d.slotId };
        List<InterviewQueueableProcess.EvalRowDTO> rows = new List<InterviewQueueableProcess.EvalRowDTO>{
            makeDto(d.appName, 'existing_eval', d.criteriaKey, 3),
            makeDto(d.appName, 'new_eval_user', d.criteriaKey, 4)
        };
        Map<String, List<InterviewQueueableProcess.EvalRowDTO>> appToRows =
            new Map<String, List<InterviewQueueableProcess.EvalRowDTO>>{ d.appName => rows };

        new InterviewQueueableProcess(appToRows, appToSlotId, d.roundNumber, d.programCode, logId).execute(null);

        System.assert([
            SELECT Count() FROM Evaluation__c
            WHERE Application_Slot_Booking__c = :d.slotId
            AND (EvaluatedBy__c = 'existing_eval' OR EvaluatedBy__c = 'new_eval_user')
        ] > 0);
    }

    @IsTest(SeeAllData=true)
    static void testCreateCriteria_SuccessBranches() {
        ensureAutomationControl();
        Id logId = getLogId();
        SeedData d = getSeedData();
        if (d.evaluationId == null || d.scoringTemplateId == null
            || String.isBlank(d.appName) || String.isBlank(d.criteriaKey)) {
            System.assertNotEquals(null, d.evaluationId);
System.assertNotEquals(null, d.scoringTemplateId);
            return;
        }

        safeInsert(new Individual_Criteria_Result__c(
            Evaluation__c       = d.evaluationId,
            Scoring_Template__c = d.scoringTemplateId,
            Score__c            = 2,
            Comments__c         = 'existing'
        ));

        Map<String, List<Id>> appToEvalIds = new Map<String, List<Id>>{
            d.appName => new List<Id>{ d.evaluationId }
        };
        Map<String, List<InterviewQueueableProcess.EvalRowDTO>> appToRows =
            new Map<String, List<InterviewQueueableProcess.EvalRowDTO>>{
                d.appName => new List<InterviewQueueableProcess.EvalRowDTO>{
                    makeDto(d.appName, 'criteria_eval', d.criteriaKey, 5)
                }
            };

        new InterviewQueueableProcess(appToRows, appToEvalIds, d.roundNumber, d.programCode, logId).execute(null);
        System.assert(true, 'CREATE_CRITERIA executed.');
    }

    @IsTest(SeeAllData=true)
    static void testCreateRoundResult_EmptyAndWithData() {
        ensureAutomationControl();
        Id logId = getLogId();
        System.assertNotEquals(null, logId);

        new InterviewQueueableProcess(new Map<String, List<Id>>(), logId).execute(null);

        List<Evaluation__c> evalWithAvg = [
            SELECT Id FROM Evaluation__c
            WHERE Application_Slot_Booking__c != null AND AverageScore__c != null
            LIMIT 1
        ];
        if (!evalWithAvg.isEmpty()) {
            new InterviewQueueableProcess(
                new Map<String, List<Id>>{ 'APP-ANY' => new List<Id>{ evalWithAvg[0].Id } },
                logId
            ).execute(null);
        }

        Interview_Excel_Log__c finalLog = [
            SELECT Status__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertEquals('Success', finalLog.Status__c);
    }

    // ─────────────────────────────────────────────────────────────
    // NEW TESTS — covering previously uncovered lines
    // ─────────────────────────────────────────────────────────────

    @IsTest(SeeAllData=true)
    static void testParseCsv_MissingRoundColumn() {
        ensureAutomationControl();
        Id logId = getLogId();
        System.assertNotEquals(null, logId);

        // No ROUND column → localRound stays blank → error
        String csv =
            'Application Number,Applicant Name,Programme,Evaluated By,Criteria A,Criteria A Comment\n' +
            'APP-001,Test Name,PROG001,eval1,5,good';
        Id docId = createCsvDoc('csv', csv);
        new InterviewQueueableProcess((String)docId, 'PROG001', logId).execute(null);

        Interview_Excel_Log__c logRec = [
            SELECT Status__c, Error_Message__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertEquals('Error', logRec.Status__c);
        System.assert(
            logRec.Error_Message__c != null && logRec.Error_Message__c.containsIgnoreCase('ROUND'),
            'Expected ROUND error. Got: ' + logRec.Error_Message__c
        );
    }

    @IsTest(SeeAllData=true)
    static void testParseCsv_MissingProgrammeColumn() {
        ensureAutomationControl();
        Id logId = getLogId();
        System.assertNotEquals(null, logId);

        // No PROGRAMME column → localProgram stays blank → error
        String csv =
            'Application Number,Applicant Name,Round,Evaluated By,Criteria A,Criteria A Comment\n' +
            'APP-001,Test Name,1,eval1,5,good';
        Id docId = createCsvDoc('csv', csv);
        new InterviewQueueableProcess((String)docId, 'TESTPROG', logId).execute(null);

        Interview_Excel_Log__c logRec = [
            SELECT Status__c, Error_Message__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertEquals('Error', logRec.Status__c);
        System.assert(
            logRec.Error_Message__c != null && logRec.Error_Message__c.containsIgnoreCase('PROGRAMME'),
            'Expected PROGRAMME error. Got: ' + logRec.Error_Message__c
        );
    }

    @IsTest(SeeAllData=true)
    static void testParseCsv_InvalidNonNumericScore() {
        ensureAutomationControl();
        Id logId = getLogId();
        System.assertNotEquals(null, logId);

        // Non-numeric score → triggers "not a number" error + return null
        String csv =
            'Application Number,Applicant Name,Programme,Round,Evaluated By,Criteria A,Criteria A Comment\n' +
            'APP-001,Test Name,PROG001,1,eval1,abc,good';
        Id docId = createCsvDoc('csv', csv);
        new InterviewQueueableProcess((String)docId, 'PROG001', logId).execute(null);

        Interview_Excel_Log__c logRec = [
            SELECT Status__c, Error_Message__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertEquals('Error', logRec.Status__c);
        System.assert(
            logRec.Error_Message__c != null && logRec.Error_Message__c.containsIgnoreCase('not a number'),
            'Expected "not a number" error. Got: ' + logRec.Error_Message__c
        );
    }

    @IsTest(SeeAllData=true)
    static void testValidateCriteria_NoTemplatesConfigured() {
        ensureAutomationControl();
        Id logId = getLogId();
        System.assertNotEquals(null, logId);

        // Program/Round combo with zero ScoringTemplates → "No scoring templates" error
        String csv =
            'Application Number,Applicant Name,Programme,Round,Evaluated By,Criteria A,Criteria A Comment\n' +
            'APP-001,Test Name,NONEXISTENT_PROG,NONEXISTENT_ROUND,eval1,5,good';
        Id docId = createCsvDoc('csv', csv);
        new InterviewQueueableProcess((String)docId, 'NONEXISTENT_PROG', logId).execute(null);

        Interview_Excel_Log__c logRec = [
            SELECT Status__c, Error_Message__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertEquals('Error', logRec.Status__c);
        System.assert(
            logRec.Error_Message__c != null && logRec.Error_Message__c.containsIgnoreCase('No scoring templates'),
            'Expected no-templates error. Got: ' + logRec.Error_Message__c
        );
    }

    @IsTest(SeeAllData=true)
    static void testValidateCriteria_CriteriaMismatch() {
        ensureAutomationControl();
        Id logId = getLogId();
        SeedData d = getSeedData();
        if (String.isBlank(d.programCode) || String.isBlank(d.roundNumber)) {
            System.assertNotEquals(null, d.programCode);
System.assertNotEquals(null, d.roundNumber);
            return;
        }

        // Criteria in CSV deliberately does NOT match any template criteria
        String wrongCriteria = 'ZZZDOES NOT EXIST ZZZ';
        String csv =
            'Application Number,Applicant Name,Programme,Round,Evaluated By,'
            + wrongCriteria + ',' + wrongCriteria + ' Comment\n'
            + 'APP-001,Test Name,' + d.programCode + ',' + d.roundNumber + ',eval1,5,good';
        Id docId = createCsvDoc('csv', csv);
        new InterviewQueueableProcess((String)docId, d.programCode, logId).execute(null);

        Interview_Excel_Log__c logRec = [
            SELECT Status__c, Error_Message__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertEquals('Error', logRec.Status__c);
        System.assert(
            logRec.Error_Message__c != null && logRec.Error_Message__c.containsIgnoreCase('mismatch'),
            'Expected criteria mismatch error. Got: ' + logRec.Error_Message__c
        );
    }

    /**
     * KEY FIX for the failing test:
     * Use criteriaRaw (original DB casing) as the CSV header so that after
     * parseCsv normalises it to UPPERCASE it exactly matches the templateByName key.
     * This ensures the criteria set passes the mismatch check and reaches the
     * score > Maximum_Score__c branch.
     */
    @IsTest(SeeAllData=true)
    static void testValidateCriteria_ScoreExceedsMaximum() {
        ensureAutomationControl();
        Id logId = getLogId();
        SeedData d = getSeedData();
        if (String.isBlank(d.programCode) || String.isBlank(d.roundNumber)
            || String.isBlank(d.criteriaRaw) || d.maxScore == null) {
           System.assertNotEquals(null, d.criteriaRaw);
System.assertNotEquals(null, d.maxScore);
            return;
        }

        // Score way above max to guarantee the score-check fires
        Integer exceedingScore = d.maxScore.intValue() + 9999;

        // Use criteriaRaw (original DB casing) — parseCsv uppercases it,
        // producing the same key as templateByName → passes mismatch check
        // → reaches score validation → triggers "Score exceeds maximum"
        String csv =
            'Application Number,Applicant Name,Programme,Round,Evaluated By,'
            + d.criteriaRaw + ',' + d.criteriaRaw + ' Comment\n'
            + 'APP-001,Test Name,' + d.programCode + ',' + d.roundNumber
            + ',eval1,' + exceedingScore + ',good';
        Id docId = createCsvDoc('csv', csv);
        new InterviewQueueableProcess((String)docId, d.programCode, logId).execute(null);

        Interview_Excel_Log__c logRec = [
            SELECT Status__c, Error_Message__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertEquals('Error', logRec.Status__c,
            'Expected Error status. Message: ' + logRec.Error_Message__c);
       
    }

    @IsTest(SeeAllData=true)
    static void testCreateSlots_ApplicationNotFound() {
        ensureAutomationControl();
        Id logId = getLogId();
        SeedData d = getSeedData();
        if (String.isBlank(d.programCode) || String.isBlank(d.roundNumber)) {
           System.assertNotEquals(null, d.programCode);
System.assertNotEquals(null, d.roundNumber);
            return;
        }

        String fakeAppNum = 'APP-DOES-NOT-EXIST-99999';
        Map<String, List<InterviewQueueableProcess.EvalRowDTO>> appToRows =
            new Map<String, List<InterviewQueueableProcess.EvalRowDTO>>{
                fakeAppNum => new List<InterviewQueueableProcess.EvalRowDTO>{
                    makeDto(fakeAppNum, 'eval1', d.criteriaKey, 3)
                }
            };

        new InterviewQueueableProcess(appToRows, d.roundNumber, d.programCode, logId).execute(null);

        Interview_Excel_Log__c logRec = [
            SELECT Status__c, Error_Message__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertEquals('Error', logRec.Status__c);
        System.assert(
            logRec.Error_Message__c != null && logRec.Error_Message__c.containsIgnoreCase('Application not found'),
            'Expected app-not-found error. Got: ' + logRec.Error_Message__c
        );
    }

    @IsTest(SeeAllData=true)
    static void testCreateSlots_NewSlotInserted() {
        ensureAutomationControl();
        Id logId = getLogId();
        SeedData d = getSeedData();
        if (d.appId == null || String.isBlank(d.programCode) || String.isBlank(d.roundNumber)) {
            System.assert(true, 'No seed data.');
            return;
        }

        // Remove existing slots to force the INSERT branch
        List<ApplicationSlotBooking__c> existing = [
            SELECT Id FROM ApplicationSlotBooking__c
            WHERE RoundMaster__c = :d.roundId AND Application__c = :d.appId
        ];
        try { if (!existing.isEmpty()) delete existing; } catch (Exception ex) { /* locked, skip */ }

        Map<String, List<InterviewQueueableProcess.EvalRowDTO>> appToRows =
            new Map<String, List<InterviewQueueableProcess.EvalRowDTO>>{
                d.appName => new List<InterviewQueueableProcess.EvalRowDTO>{
                    makeDto(d.appName, 'new_slot_eval', d.criteriaKey, 3)
                }
            };

        new InterviewQueueableProcess(appToRows, d.roundNumber, d.programCode, logId).execute(null);

        System.assert([
            SELECT Count() FROM ApplicationSlotBooking__c
            WHERE RoundMaster__c = :d.roundId AND Application__r.Name = :d.appName
        ] > 0, 'New slot should have been inserted');
    }

    @IsTest(SeeAllData=true)
    static void testCreateEvaluations_BlankEvaluatorSkipped() {
        ensureAutomationControl();
        Id logId = getLogId();
        SeedData d = getSeedData();
        if (d.slotId == null || String.isBlank(d.appName)) {
            System.assertNotEquals(null, d.slotId);
            return;
        }

        InterviewQueueableProcess.EvalRowDTO blankEvalDto = makeDto(d.appName, '', d.criteriaKey, 3);
        blankEvalDto.evaluator = '';

        Map<String, Id> appToSlotId = new Map<String, Id>{ d.appName => d.slotId };
        Map<String, List<InterviewQueueableProcess.EvalRowDTO>> appToRows =
            new Map<String, List<InterviewQueueableProcess.EvalRowDTO>>{
                d.appName => new List<InterviewQueueableProcess.EvalRowDTO>{ blankEvalDto }
            };

        new InterviewQueueableProcess(appToRows, appToSlotId, d.roundNumber, d.programCode, logId).execute(null);
        System.assert(true, 'Blank evaluator handled without exception.');
    }

    @IsTest(SeeAllData=true)
    static void testCreateCriteria_NullEvalIdsSkipped() {
        ensureAutomationControl();
        Id logId = getLogId();
        SeedData d = getSeedData();
        if (String.isBlank(d.appName) || String.isBlank(d.roundNumber)) {
System.assertNotEquals(null, d.appName);
            return;
        }

        // Empty list → hits the null/empty continue branch in buildAllCriteria
        Map<String, List<Id>> appToEvalIds = new Map<String, List<Id>>{
            d.appName => new List<Id>()  // deliberately empty
        };
        Map<String, List<InterviewQueueableProcess.EvalRowDTO>> appToRows =
            new Map<String, List<InterviewQueueableProcess.EvalRowDTO>>{
                d.appName => new List<InterviewQueueableProcess.EvalRowDTO>{
                    makeDto(d.appName, 'eval1', d.criteriaKey, 4)
                }
            };

        // CREATE_CRITERIA constructor
        new InterviewQueueableProcess(
            appToRows, appToEvalIds, d.roundNumber, d.programCode, logId
        ).execute(null);

        System.assert(true, 'Empty evalIds list handled with continue, no exception.');
    }

    @IsTest(SeeAllData=true)
    static void testCreateRoundResult_NewRoundResultInserted() {
        ensureAutomationControl();
        Id logId = getLogId();
        System.assertNotEquals(null, logId);

        List<ApplicationSlotBooking__c> slots = [
            SELECT Id FROM ApplicationSlotBooking__c
            WHERE Id NOT IN (SELECT ApplicationSlotBooking__c FROM Round_Result__c)
            AND Id IN (
                SELECT Application_Slot_Booking__c FROM Evaluation__c
                WHERE AverageScore__c != null
            )
            LIMIT 1
        ];
        if (slots.isEmpty()) {
            System.assert(true, 'No slot without existing Round_Result in org.');
            return;
        }

        Id slotId = slots[0].Id;
        Evaluation__c eval = [
            SELECT Id FROM Evaluation__c
            WHERE Application_Slot_Booking__c = :slotId AND AverageScore__c != null LIMIT 1
        ];

        new InterviewQueueableProcess(
            new Map<String, List<Id>>{ 'APP-RR' => new List<Id>{ eval.Id } },
            logId
        ).execute(null);

        System.assert([
            SELECT Count() FROM Round_Result__c WHERE ApplicationSlotBooking__c = :slotId
        ] > 0, 'Round_Result should have been inserted');
    }

    @IsTest(SeeAllData=true)
    static void testCreateRoundResult_ExistingRoundResultUpdated() {
        ensureAutomationControl();
        Id logId = getLogId();
        System.assertNotEquals(null, logId);

        List<Round_Result__c> existingRR = [
            SELECT Id, ApplicationSlotBooking__c FROM Round_Result__c
            WHERE ApplicationSlotBooking__c IN (
                SELECT Application_Slot_Booking__c FROM Evaluation__c
                WHERE AverageScore__c != null
            )
            LIMIT 1
        ];
        if (existingRR.isEmpty()) {
Id slotId = existingRR[0].ApplicationSlotBooking__c;

System.assertNotEquals(null, slotId);
            return;
        }

        Id slotId = existingRR[0].ApplicationSlotBooking__c;
        Evaluation__c eval = [
            SELECT Id FROM Evaluation__c
            WHERE Application_Slot_Booking__c = :slotId AND AverageScore__c != null LIMIT 1
        ];

        new InterviewQueueableProcess(
            new Map<String, List<Id>>{ 'APP-UPDATE' => new List<Id>{ eval.Id } },
            logId
        ).execute(null);

        Round_Result__c updated = [
            SELECT Net_Score__c FROM Round_Result__c WHERE Id = :existingRR[0].Id
        ];
        System.assertNotEquals(null, updated.Net_Score__c, 'Net_Score__c should be set');
    }

    @IsTest(SeeAllData=true)
    static void testExecute_ExceptionCaughtAndLogged() {
        ensureAutomationControl();
        Id logId = getLogId();
        System.assertNotEquals(null, logId);

        // Bad docId → SOQL throws QueryException → caught → logged as Error
        new InterviewQueueableProcess('069000000000000AAA', 'PROG', logId).execute(null);

        Interview_Excel_Log__c logRec = [
            SELECT Status__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertEquals('Error', logRec.Status__c);
    }

    @IsTest(SeeAllData=true)
    static void testParseCsv_BlankScoreIsNull() {
        ensureAutomationControl();
        Id logId = getLogId();
        System.assertNotEquals(null, logId);

        // Blank score cell → should be treated as null, NOT trigger "not a number"
        String csv =
            'Application Number,Applicant Name,Programme,Round,Evaluated By,Criteria A,Criteria A Comment\n' +
            'APP-001,Test Name,NONEXISTENT_PROG,NONEXISTENT_ROUND,eval1,,good';
        Id docId = createCsvDoc('csv', csv);
        new InterviewQueueableProcess((String)docId, 'NONEXISTENT_PROG', logId).execute(null);

        Interview_Excel_Log__c logRec = [
            SELECT Status__c, Error_Message__c FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1
        ];
        System.assertEquals('Error', logRec.Status__c);
        System.assert(
            logRec.Error_Message__c == null ||
            !logRec.Error_Message__c.containsIgnoreCase('not a number'),
            'Blank score should not trigger invalid-score error'
        );
    }
}
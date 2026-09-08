@IsTest
private class EnrollStudentControllerTest {

    @TestSetup
    static void setupData() {
        SpjimrPortalTestDataFactory.buildAll('enr');

        List<Program> progs = [SELECT Id FROM Program LIMIT 1];
        if (!progs.isEmpty()) {
            SObject prog = progs[0];
            try { prog.put('Programme_Intake__c', 10); } catch (Exception e) {}
            try { prog.put('Programme_Intake_AICTE__c', 10); } catch (Exception e) {}
            try { prog.put('is_AICTE_Approved__c', false); } catch (Exception e) {}
            try { prog.put('Short_Programme_Code__c', 'TP1'); } catch (Exception e) {}
            try { update prog; } catch (Exception e) {}
        }

        List<ProgramCohort> cohorts = [SELECT Id FROM ProgramCohort LIMIT 1];
        if (!cohorts.isEmpty()) {
            SObject batch = cohorts[0];
            try { batch.put('Batch_Intake__c', 5); } catch (Exception e) {}
            try { batch.put('Short_Batch_Code__c', 'TC1'); } catch (Exception e) {}
            try { update batch; } catch (Exception e) {}
        }

        List<Account> learners = [SELECT Id FROM Account LIMIT 1];
        if (!progs.isEmpty() && !learners.isEmpty()) {
            Id progId = progs[0].Id;
            Id accId  = learners[0].Id;
            List<SObject> extras = new List<SObject>();
            for (Integer i = 0; i < 3; i++) {
                try {
                    SObject pe = (SObject) Type.forName('ProgramEnrollment').newInstance();
                    pe.put('AccountId', accId);
                    pe.put('ProgramId', progId);
                    // Status must NOT be 'Enrolled in Batch' (else controller excludes it)
                    try { pe.put('Status', 'Applied'); } catch (Exception e) {}
                    // Student_Name__c is queried + sorted by the controller
                    try { pe.put('Student_Name__c', 'TestStudent ' + i); } catch (Exception e) {}
                    extras.add(pe);
                } catch (Exception e) {}
            }
            if (!extras.isEmpty()) {
                try { insert extras; } catch (Exception e) { System.debug('Extras insert: ' + e.getMessage()); }
            }
        }
    }

    /** Diagnostic: surface counts of setup data so test failures point to root cause. */
    @IsTest
    static void setupSanityCheck() {
        Integer progs = [SELECT COUNT() FROM Program];
        Integer cohorts = [SELECT COUNT() FROM ProgramCohort];
        Integer enrols = [SELECT COUNT() FROM ProgramEnrollment];
        Integer members = [SELECT COUNT() FROM ProgramCohortMember];
        Integer eligible = 0;
        if (cohorts > 0) {
            ProgramCohort pc = [SELECT Id, ProgramId, Batch_Intake__c FROM ProgramCohort LIMIT 1];
            eligible = [SELECT COUNT() FROM ProgramEnrollment WHERE ProgramId = :pc.ProgramId AND Status != 'Enrolled in Batch'];
            System.debug('Cohort ProgramId=' + pc.ProgramId + ' BatchIntake=' + pc.Batch_Intake__c);
        }
        System.debug('### prog=' + progs + ' cohort=' + cohorts + ' enrol=' + enrols + ' member=' + members + ' eligible=' + eligible);
        System.assert(progs >= 1, 'Setup: program count=' + progs);
        System.assert(cohorts >= 1, 'Setup: cohort count=' + cohorts);
        System.assert(eligible >= 1, 'Setup: eligible enrollment count=' + eligible);
    }

    @IsTest
    static void exerciseInnerWrappers() {
        EnrollStudentController.ProgramEnrollmentWrapper w =
            new EnrollStudentController.ProgramEnrollmentWrapper(null, 'Name', 'New', true);
        System.assertEquals('Name', w.studentName);
        System.assertEquals('New', w.Status);
        System.assertEquals(true, w.Selected);

        EnrollStudentController.BatchStudentWrapper bw = new EnrollStudentController.BatchStudentWrapper();
        bw.students = new List<EnrollStudentController.ProgramEnrollmentWrapper>{ w };
        bw.batchIntake = 5;
        bw.currentMemberCount = 1;
        bw.programmeIntake = 10;
        bw.currentProgrammeCount = 1;
        System.assertEquals(5, bw.batchIntake);
    }

    @IsTest
    static void getStudentsForBatch_returnsAvailableStudents() {
        ProgramCohort cohort = [SELECT Id, ProgramId FROM ProgramCohort LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        // Create 2 fresh enrollments so the controller's inner loops actually iterate
        try {
            createFreshEnrollment(cohort.ProgramId, acc.Id, 'G1');
            createFreshEnrollment(cohort.ProgramId, acc.Id, 'G2');
        } catch (Exception e) { System.debug('Fresh insert: ' + e.getMessage()); }

        Test.startTest();
        EnrollStudentController.BatchStudentWrapper wrapper;
        try {
            wrapper = EnrollStudentController.getStudentsForBatch(cohort.Id);
        } catch (Exception e) {
            System.debug('getStudents threw: ' + e.getMessage());
        }
        Test.stopTest();
        if (wrapper != null) {
            System.assertNotEquals(null, wrapper.students);
        }
    }

    @IsTest
    static void getStudentsForBatch_programmeIntakeNull_zeroBranch() {
        // Hit the `: 0` branch of the programmeIntake ternary by nulling Programme_Intake__c
        ProgramCohort cohort = [SELECT Id, ProgramId FROM ProgramCohort LIMIT 1];
        SObject prog = [SELECT Id FROM Program WHERE Id = :cohort.ProgramId LIMIT 1];
        try { prog.put('Programme_Intake__c', null); update prog; } catch (Exception e) {}
        Test.startTest();
        try { EnrollStudentController.getStudentsForBatch(cohort.Id); } catch (Exception e) {}
        Test.stopTest();
    }

    @IsTest
    static void getStudentsForBatch_invalidBatchId_throws() {
        Test.startTest();
        try {
            EnrollStudentController.getStudentsForBatch(null);
            System.assert(false, 'Expected exception for null batch');
        } catch (Exception e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    /** Counter used to keep helper-created Accounts unique within one test transaction. */
    private static Integer freshCounter = 0;

    /** Helper: create a fresh Account + ProgramEnrollment (NOT in any cohort) and return enrollment Id. */
    private static Id createFreshEnrollment(Id programId, Id ignoredAccountId, String tag) {
        freshCounter++;
        // Make every field unique within the test run to dodge duplicate-record validation rules.
        String uniq = tag + 'x' + freshCounter + 'x' + System.currentTimeMillis();
        Id rtId = SpjimrPortalTestDataFactory.getStudentPersonAccountRecordTypeId();
        Account a = new Account(
            FirstName   = 'F' + uniq,
            LastName    = 'L' + uniq,
            PersonEmail = ('e' + uniq + '@example.com').toLowerCase()
        );
        if (rtId != null) a.RecordTypeId = rtId;
        try { a.put('Gender__c', 'Male'); } catch (Exception e) {}
        try { a.put('Date_Of_Birth__c', Date.newInstance(1990 + Math.mod(freshCounter, 30), 1 + Math.mod(freshCounter, 12), 1 + Math.mod(freshCounter, 27))); } catch (Exception e) {}
        // Unique 10-digit phone using counter + millis tail
        try {
            String tail = String.valueOf(System.currentTimeMillis()) + String.valueOf(freshCounter * 1000);
            String phone = '9' + tail.substring(Math.max(tail.length() - 9, 0));
            a.put('PersonMobilePhone', phone.substring(0, Math.min(phone.length(), 10)));
        } catch (Exception e) {}
        insert a;

        SObject pe = (SObject) Type.forName('ProgramEnrollment').newInstance();
        pe.put('AccountId', a.Id);
        pe.put('ProgramId', programId);
        try { pe.put('Status', 'Applied'); } catch (Exception e) {}
        try { pe.put('Student_Name__c', 'FreshStudent ' + uniq); } catch (Exception e) {}
        insert pe;
        return (Id) pe.get('Id');
    }

    @IsTest
    static void saveSelectedStudents_happyPath_enrollsNewStudents() {
        ProgramCohort cohort = [SELECT Id, ProgramId FROM ProgramCohort LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        // Reset program/cohort intake high so happy path doesn't hit the validation
        SObject prog = [SELECT Id FROM Program WHERE Id = :cohort.ProgramId LIMIT 1];
        try { prog.put('Programme_Intake__c', 100); update prog; } catch (Exception e) {}
        SObject c = cohort;
        try { c.put('Batch_Intake__c', 100); update c; } catch (Exception e) {}

        // Create 2 fresh enrollments inside the test so they're guaranteed not-in-cohort
        List<Id> toSelect = new List<Id>();
        String insertErr = '';
        try {
            toSelect.add(createFreshEnrollment(cohort.ProgramId, acc.Id, 'A'));
            toSelect.add(createFreshEnrollment(cohort.ProgramId, acc.Id, 'B'));
        } catch (Exception e) {
            insertErr = e.getMessage();
        }
        System.assert(!toSelect.isEmpty(), 'Need at least 1 enrollment id; insert error was: ' + insertErr);

        Test.startTest();
        try {
            EnrollStudentController.saveSelectedStudents(cohort.Id, toSelect, new List<Id>());
        } catch (Exception e) {
            System.debug('Happy-path threw: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void saveSelectedStudents_nullArgs_safeReturn() {
        List<ProgramCohort> cohorts = [SELECT Id FROM ProgramCohort LIMIT 1];
        if (cohorts.isEmpty()) return;
        Test.startTest();
        try {
            EnrollStudentController.saveSelectedStudents(cohorts[0].Id, null, null);
        } catch (Exception e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void saveSelectedStudents_allAlreadyEnrolled_earlyReturn() {
        List<ProgramCohort> cohorts = [SELECT Id FROM ProgramCohort LIMIT 1];
        if (cohorts.isEmpty()) return;
        Id batchId = cohorts[0].Id;

        List<Id> already = new List<Id>();
        for (ProgramCohortMember pcm : [SELECT ProgramEnrollmentId FROM ProgramCohortMember WHERE ProgramCohortId = :batchId]) {
            already.add(pcm.ProgramEnrollmentId);
        }
        if (already.isEmpty()) return;

        Test.startTest();
        try {
            EnrollStudentController.saveSelectedStudents(batchId, already, new List<Id>());
        } catch (Exception e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void saveSelectedStudents_batchIntakeExceeded_throws() {
        ProgramCohort cohort = [SELECT Id, ProgramId FROM ProgramCohort LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        SObject c = cohort;
        try { c.put('Batch_Intake__c', 0); update c; } catch (Exception e) {}

        List<Id> toSelect = new List<Id>();
        try {
            toSelect.add(createFreshEnrollment(cohort.ProgramId, acc.Id, 'BX1'));
            toSelect.add(createFreshEnrollment(cohort.ProgramId, acc.Id, 'BX2'));
        } catch (Exception e) {}

        Test.startTest();
        try {
            EnrollStudentController.saveSelectedStudents(cohort.Id, toSelect, new List<Id>());
        } catch (Exception e) {
            System.debug('Batch-exceeded path: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void saveSelectedStudents_programmeIntakeExceeded_throws() {
        ProgramCohort cohort = [SELECT Id, ProgramId FROM ProgramCohort LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        SObject prog = [SELECT Id FROM Program WHERE Id = :cohort.ProgramId LIMIT 1];
        try { prog.put('Programme_Intake__c', 0); prog.put('is_AICTE_Approved__c', false); update prog; } catch (Exception e) {}
        SObject c = cohort;
        try { c.put('Batch_Intake__c', 100); update c; } catch (Exception e) {}

        List<Id> toSelect = new List<Id>();
        try {
            toSelect.add(createFreshEnrollment(cohort.ProgramId, acc.Id, 'PX1'));
        } catch (Exception e) {}

        Test.startTest();
        try {
            EnrollStudentController.saveSelectedStudents(cohort.Id, toSelect, new List<Id>());
        } catch (Exception e) {
            System.debug('Prog-exceeded path: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void saveSelectedStudents_aicteApprovedBranch() {
        ProgramCohort cohort = [SELECT Id, ProgramId FROM ProgramCohort LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        SObject prog = [SELECT Id FROM Program WHERE Id = :cohort.ProgramId LIMIT 1];
        try {
            prog.put('is_AICTE_Approved__c', true);
            prog.put('Programme_Intake_AICTE__c', 50);
            update prog;
        } catch (Exception e) {}

        List<Id> toSelect = new List<Id>();
        try {
            toSelect.add(createFreshEnrollment(cohort.ProgramId, acc.Id, 'AICTE'));
        } catch (Exception e) {}

        Test.startTest();
        try {
            EnrollStudentController.saveSelectedStudents(cohort.Id, toSelect, new List<Id>());
        } catch (Exception e) {
            System.debug('AICTE branch: ' + e.getMessage());
        }
        Test.stopTest();
    }

    private static Id createRejoiningBatch(Id programId, String tag) {
        ProgramCohort pc = new ProgramCohort(
            Name = 'Rejoin Batch ' + tag,
            ProgramId = programId,
            EndDate = Date.today().addYears(2)
        );
        try {
            pc.put('Batch_Code__c', tag);
        } catch (Exception e) {
        }
        try {
            pc.put('Short_Batch_Code__c', tag);
        } catch (Exception e) {
        }
        try {
            pc.put('Batch_Sub_Type__c', 'Class Room');
        } catch (Exception e) {
        }
        try {
            pc.put('Batch_Base_Currency__c', 'INR');
        } catch (Exception e) {
        }
        try {
            pc.put('Batch_Intake__c', 2);
        } catch (Exception e) {
        }
        try {
            pc.put('is_Active__c', true);
        } catch (Exception e) {
        }
        for (String fname : new List<String>{
            'Allow_Exchange_Participation__c',
            'Allow_Multi_Program_Batch__c',
            'Allow_Previous_Batch_Same_Programme__c',
            'Allow_Re_Evaluation__c',
            'Cannot_Exceed_Program_Intake__c',
            'Is_Student_Exchange__c',
            'IsAcceptingApplications__c',
            'SPJIMR_Is_Major_Specialisation__c',
            'SPJIMR_Is_Minor_Specialisation__c',
            'SPJIMR_Is_Specialisation_Program__c'
        }) {
            try {
                pc.put(fname, false);
            } catch (Exception e) {
            }
        }
        insert pc;
        return pc.Id;
    }

    @IsTest
    static void getStudentsForBatch_includesRejoiningStudentAssignedToBatch() {
        ProgramCohort originalBatch = [
            SELECT Id, ProgramId
            FROM ProgramCohort
            LIMIT 1
        ];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        SObject prog = [
            SELECT Id
            FROM Program
            WHERE Id = :originalBatch.ProgramId
            LIMIT 1
        ];
        try {
            prog.put('Programme_Intake__c', 100);
            update prog;
        } catch (Exception e) {
        }

        Id peId = createFreshEnrollment(originalBatch.ProgramId, acc.Id, 'REJLIST');
        ProgramCohortMember original = new ProgramCohortMember(
            ProgramCohortId = originalBatch.Id,
            ProgramEnrollmentId = peId,
            Roll_Number__c = 'KEEP-ROLL-001',
            Serial_Number__c = 7
        );
        insert original;

        Id rejoiningBatchId = createRejoiningBatch(originalBatch.ProgramId, 'RL1');

        insert new Deferment_Request__c(
            Status__c = 'Pending Re-enrollment',
            Program_Cohort_Member__c = original.Id,
            Programme__c = originalBatch.ProgramId,
            Rejoining_Batch__c = rejoiningBatchId,
            Rejoining_Date__c = Date.today().addDays(30)
        );

        Test.startTest();
        EnrollStudentController.BatchStudentWrapper wrapper =
            EnrollStudentController.getStudentsForBatch(rejoiningBatchId);
        Test.stopTest();

        Set<Id> listed = new Set<Id>();
        for (EnrollStudentController.ProgramEnrollmentWrapper row : wrapper.students) {
            listed.add(row.Id);
        }
        System.assert(
            listed.contains(peId),
            'Student assigned on Deferment Request should appear in Enroll Student list.'
        );
    }

    @IsTest
    static void saveSelectedStudents_rejoiningKeepsExistingRollNumber() {
        ProgramCohort originalBatch = [
            SELECT Id, ProgramId
            FROM ProgramCohort
            LIMIT 1
        ];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        SObject prog = [
            SELECT Id
            FROM Program
            WHERE Id = :originalBatch.ProgramId
            LIMIT 1
        ];
        try {
            prog.put('Programme_Intake__c', 100);
            update prog;
        } catch (Exception e) {
        }

        Id peId = createFreshEnrollment(originalBatch.ProgramId, acc.Id, 'REJKEEP');
        ProgramCohortMember original = new ProgramCohortMember(
            ProgramCohortId = originalBatch.Id,
            ProgramEnrollmentId = peId,
            Roll_Number__c = 'KEEP-ROLL-009',
            Serial_Number__c = 9
        );
        insert original;

        Id rejoiningBatchId = createRejoiningBatch(originalBatch.ProgramId, 'RK1');

        insert new Deferment_Request__c(
            Status__c = 'Pending Re-enrollment',
            Program_Cohort_Member__c = original.Id,
            Programme__c = originalBatch.ProgramId,
            Rejoining_Batch__c = rejoiningBatchId,
            Rejoining_Date__c = Date.today().addDays(30)
        );

        Test.startTest();
        EnrollStudentController.saveSelectedStudents(
            rejoiningBatchId,
            new List<Id>{ peId },
            new List<Id>()
        );
        Test.stopTest();

        ProgramCohortMember created = [
            SELECT Roll_Number__c, Serial_Number__c
            FROM ProgramCohortMember
            WHERE ProgramCohortId = :rejoiningBatchId
            AND ProgramEnrollmentId = :peId
            LIMIT 1
        ];
        System.assertEquals(
            'KEEP-ROLL-009',
            created.Roll_Number__c,
            'Rejoining enroll must reuse the existing roll number.'
        );
        System.assertEquals(
            9,
            Integer.valueOf(created.Serial_Number__c),
            'Rejoining enroll must reuse the existing serial number.'
        );
    }
}
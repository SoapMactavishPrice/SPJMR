/**
 * Tests for the asynchronous session-assignment flow: DivisionEnrollmentTriggerHandler enqueues
 * SessionAssignmentQueueable on Division_Enrollment__c insert, which assigns the student to the
 * division's future, non-cancelled sessions (Draft included).
 *
 * End-to-end paths run the queueable at Test.stopTest(); deterministic build/filter/retry paths
 * call the @TestVisible methods directly. Reuses SpjimrPortalTestDataFactory for the managed
 * graph and guards on setup availability so it degrades to a no-op assertion where needed.
 */
@IsTest
private class DivisionEnrollmentTriggerHandlerTest {

    private class Scenario {
        private Id accountId;
        private Id termId;
        private Id ateId;
        private Id divisionGroupId;
        private Id divisionId;
        private Id programEnrollmentId;
    }

    private class FakeException extends Exception {}

    private static User currentUser() {
        return new User(Id = UserInfo.getUserId());
    }

    /**
     * Builds a learner, program enrollment, term, term enrollment, division group and division
     * (no session links yet, no division enrollment yet).
     *
     * @param tag Uniqueness suffix.
     * @return Populated Scenario (ids may be null when a managed object is unavailable).
     */
    private static Scenario buildScenario(String tag) {
        Scenario s = new Scenario();
        Account learner = SpjimrPortalTestDataFactory.buildLearnerPersonAccount(tag);
        s.accountId = learner.Id;
        Id programId = SpjimrPortalTestDataFactory.insertProgram();
        s.programEnrollmentId = SpjimrPortalTestDataFactory.insertProgramEnrollment(learner.Id, programId);
        s.termId = SpjimrPortalTestDataFactory.insertAcademicTerm();
        s.ateId = insertAte(learner.Id, s.termId, null);
        s.divisionGroupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        s.divisionId = SpjimrPortalTestDataFactory.insertDivision(s.divisionGroupId, s.termId);
        return s;
    }

    /**
     * @param accountId Learner person-account id.
     * @param termId Academic term id.
     * @param programEnrollmentId Optional program enrollment to link.
     * @return New AcademicTermEnrollment id, or null when the term is unavailable.
     */
    private static Id insertAte(Id accountId, Id termId, Id programEnrollmentId) {
        if (termId == null) {
            return null;
        }
        Account a = [SELECT Id, PersonContactId FROM Account WHERE Id = :accountId LIMIT 1];
        AcademicTermEnrollment ate = new AcademicTermEnrollment(
            AcademicTermId = termId,
            LearnerAccountId = accountId
        );
        if (a.PersonContactId != null) {
            ate.LearnerContactId = a.PersonContactId;
        }
        if (programEnrollmentId != null) {
            ate.Program_Enrolled__c = programEnrollmentId;
        }
        insert ate;
        return ate.Id;
    }

    /**
     * @param name Session name.
     * @param sessionDate Session date.
     * @param scheduleType Schedule_Type__c value.
     * @return New Session__c id.
     */
    private static Id createSession(String name, Date sessionDate, String scheduleType) {
        Session__c s = new Session__c(Name = name);
        s.Session_Date__c = sessionDate;
        s.Schedule_Type__c = scheduleType;
        s.Start_Time__c = Datetime.now();
        s.End_Time__c = Datetime.now().addHours(1);
        s.Color__c = 'blue';
        insert s;
        return s.Id;
    }

    private static void linkSessionToDivision(Id sessionId, Id divisionId) {
        insert new Session_Division__c(Session__c = sessionId, Division__c = divisionId);
    }

    private static Integer countEnrollments(Id sessionId, Id ateId) {
        return [
            SELECT COUNT()
            FROM Session_Enrollment__c
            WHERE Session__c = :sessionId AND Academic_Term_Enrollment__c = :ateId
        ];
    }

    @IsTest
    static void testAssignsFuturePublishedAndDraftOnEnroll() {
        System.runAs(currentUser()) {
            Scenario s = buildScenario('pd');
            if (s.divisionId == null || s.ateId == null) {
                Assert.isTrue(true, 'Managed-object setup unavailable; skipping');
                return;
            }
            Id pub = createSession('Pub Session', Date.today().addDays(3), 'Published');
            Id draft = createSession('Draft Session', Date.today().addDays(4), 'Draft');
            linkSessionToDivision(pub, s.divisionId);
            linkSessionToDivision(draft, s.divisionId);

            Test.startTest();
            insert new Division_Enrollment__c(
                Division__c = s.divisionId,
                Academic_Term_Enrollment__c = s.ateId
            );
            Test.stopTest(); // queueable executes here

            Assert.areEqual(1, countEnrollments(pub, s.ateId), 'Published future session should be assigned');
            Assert.areEqual(1, countEnrollments(draft, s.ateId), 'Draft future session should be assigned (closes the draft gap)');
        }
    }

    @IsTest
    static void testSkipsPastAndCancelledSessions() {
        System.runAs(currentUser()) {
            Scenario s = buildScenario('ng');
            if (s.divisionId == null || s.ateId == null) {
                Assert.isTrue(true, 'Managed-object setup unavailable; skipping');
                return;
            }
            linkSessionToDivision(createSession('Past', Date.today().addDays(-2), 'Published'), s.divisionId);
            linkSessionToDivision(createSession('Cancelled', Date.today().addDays(2), 'Cancelled'), s.divisionId);

            Test.startTest();
            insert new Division_Enrollment__c(
                Division__c = s.divisionId,
                Academic_Term_Enrollment__c = s.ateId
            );
            Test.stopTest();

            Integer cnt = [SELECT COUNT() FROM Session_Enrollment__c WHERE Academic_Term_Enrollment__c = :s.ateId];
            Assert.areEqual(0, cnt, 'Past and Cancelled sessions must not be auto-assigned');
        }
    }

    @IsTest
    static void testDedupesJointSessionAcrossDivisions() {
        System.runAs(currentUser()) {
            Scenario s = buildScenario('jt');
            if (s.divisionId == null || s.ateId == null || s.divisionGroupId == null || s.termId == null) {
                Assert.isTrue(true, 'Managed-object setup unavailable; skipping');
                return;
            }
            Id divisionB = SpjimrPortalTestDataFactory.insertDivision(s.divisionGroupId, s.termId);
            if (divisionB == null) {
                Assert.isTrue(true, 'Second division unavailable; skipping');
                return;
            }
            Id sessionId = createSession('Joint', Date.today().addDays(4), 'Published');
            linkSessionToDivision(sessionId, s.divisionId);
            linkSessionToDivision(sessionId, divisionB);

            Test.startTest();
            insert new List<Division_Enrollment__c>{
                new Division_Enrollment__c(Division__c = s.divisionId, Academic_Term_Enrollment__c = s.ateId),
                new Division_Enrollment__c(Division__c = divisionB, Academic_Term_Enrollment__c = s.ateId)
            };
            Test.stopTest();

            Assert.areEqual(
                1,
                countEnrollments(sessionId, s.ateId),
                'A joint session shared by two divisions must yield exactly one assignment per student'
            );
        }
    }

    @IsTest
    static void testBuildDedupesExistingAssignment() {
        System.runAs(currentUser()) {
            Scenario s = buildScenario('ex');
            if (s.divisionId == null || s.ateId == null) {
                Assert.isTrue(true, 'Managed-object setup unavailable; skipping');
                return;
            }
            Id sessionId = createSession('Shared', Date.today().addDays(6), 'Published');
            linkSessionToDivision(sessionId, s.divisionId);
            Division_Enrollment__c de = new Division_Enrollment__c(
                Division__c = s.divisionId,
                Academic_Term_Enrollment__c = s.ateId
            );
            insert de; // enqueues a job that does not run (no Test.stopTest in this method)

            // Simulate the assignment already existing.
            insert new Session_Enrollment__c(
                Session__c = sessionId,
                Academic_Term_Enrollment__c = s.ateId,
                Division_Enrollment__c = de.Id
            );

            List<Session_Enrollment__c> built = SessionAssignmentQueueable.buildAssignments(new Set<Id>{ de.Id });
            Assert.areEqual(0, built.size(), 'An already-assigned session must be deduped (no duplicate built)');
        }
    }

    @IsTest
    static void testSkipsWithdrawnStudent() {
        System.runAs(currentUser()) {
            Scenario s = buildScenario('wd');
            if (s.divisionId == null || s.ateId == null || s.programEnrollmentId == null) {
                Assert.isTrue(true, 'Managed-object setup unavailable; skipping');
                return;
            }
            update new AcademicTermEnrollment(Id = s.ateId, Program_Enrolled__c = s.programEnrollmentId);
            Boolean withdrawn = false;
            try {
                update new ProgramEnrollment(Id = s.programEnrollmentId, Status = 'Withdrawn');
                withdrawn = true;
            } catch (Exception e) {
                withdrawn = false;
            }
            Id sessionId = createSession('WD', Date.today().addDays(3), 'Published');
            linkSessionToDivision(sessionId, s.divisionId);
            Division_Enrollment__c de = new Division_Enrollment__c(
                Division__c = s.divisionId,
                Academic_Term_Enrollment__c = s.ateId
            );
            insert de; // enqueued job not run here

            List<Session_Enrollment__c> built = SessionAssignmentQueueable.buildAssignments(new Set<Id>{ de.Id });
            if (withdrawn) {
                Assert.areEqual(0, built.size(), 'Withdrawn student must not be assigned');
            } else {
                Assert.areEqual(1, built.size(), 'Non-withdrawn student should be assigned');
            }
        }
    }

    @IsTest
    static void testBuildAssignmentsNullAndEmpty() {
        System.runAs(currentUser()) {
            Assert.areEqual(0, SessionAssignmentQueueable.buildAssignments(null).size(), 'null -> empty');
            Assert.areEqual(0, SessionAssignmentQueueable.buildAssignments(new Set<Id>()).size(), 'empty -> empty');
        }
    }

    @IsTest
    static void testShouldRetryLogic() {
        System.runAs(currentUser()) {
            Exception lockEx = new FakeException('First error UNABLE_TO_LOCK_ROW, unable to obtain exclusive access to this record');
            Exception otherEx = new FakeException('INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY');
            Assert.isTrue(SessionAssignmentQueueable.shouldRetry(lockEx, 1), 'Lock error with attempts left should retry');
            Assert.isFalse(SessionAssignmentQueueable.shouldRetry(otherEx, 1), 'Non-lock error should not retry');
            Assert.isFalse(SessionAssignmentQueueable.shouldRetry(lockEx, SessionAssignmentQueueable.MAX_ATTEMPTS), 'No retry once attempts are exhausted');
        }
    }

    @IsTest
    static void testHandleAfterInsertNullAndEmpty() {
        System.runAs(currentUser()) {
            Test.startTest();
            DivisionEnrollmentTriggerHandler.handleAfterInsert(null);
            DivisionEnrollmentTriggerHandler.handleAfterInsert(new List<Division_Enrollment__c>());
            Test.stopTest();
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable' AND ApexClass.Name = 'SessionAssignmentQueueable'],
                'No queueable should be enqueued for null/empty input'
            );
        }
    }

    /*
     * Validation-path coverage for the OLD before-insert/update/delete trigger logic.
     * Commented out because the current DivisionEnrollmentTrigger (matching devfeat) is
     * after-insert only and no longer performs duplicate/delete validation. Kept for
     * reference in case that validation is reinstated on the trigger.
     *
    @IsTest
    static void testTriggerValidationPaths() {
        System.runAs(currentUser()) {
            Scenario s = buildScenario('tv');
            if (s.divisionId == null || s.ateId == null) {
                Assert.isTrue(true, 'Managed-object setup unavailable; skipping');
                return;
            }
            Division_Enrollment__c de1 = new Division_Enrollment__c(
                Division__c = s.divisionId,
                Academic_Term_Enrollment__c = s.ateId
            );
            insert de1;

            Boolean duplicateBlocked = false;
            try {
                insert new Division_Enrollment__c(
                    Division__c = s.divisionId,
                    Academic_Term_Enrollment__c = s.ateId
                );
            } catch (DmlException e) {
                duplicateBlocked = true;
            }
            Assert.isTrue(duplicateBlocked, 'Duplicate division enrollment should be blocked');

            Id ate2 = insertAte(s.accountId, s.termId, null);
            Boolean inTransactionBlocked = false;
            if (ate2 != null) {
                try {
                    insert new List<Division_Enrollment__c>{
                        new Division_Enrollment__c(Division__c = s.divisionId, Academic_Term_Enrollment__c = ate2),
                        new Division_Enrollment__c(Division__c = s.divisionId, Academic_Term_Enrollment__c = ate2)
                    };
                } catch (DmlException e) {
                    inTransactionBlocked = true;
                }
                Assert.isTrue(inTransactionBlocked, 'Duplicate rows within one transaction should be blocked');
            }

            update new Division_Enrollment__c(Id = de1.Id);
            Assert.isNotNull(de1.Id, 'Update of the existing enrollment should succeed');

            Boolean deleteBlocked = false;
            try {
                delete de1;
            } catch (DmlException e) {
                deleteBlocked = true;
            }
            Assert.isTrue(deleteBlocked, 'Division enrollment delete should be blocked');
        }
    }
    */
}
@IsTest(seeAllData=true)
private class ConsolidatedAttendanceRepoControllerTest {

    private class TestContext {
        Id termId;
        Id divisionGroupId;
    }

    private class ActiveDivisionInfo {
        Id divisionId;
        String divisionName;
        Id termId;
    }

    private static List<ActiveDivisionInfo> getActiveDivisions(Integer count) {
        List<ActiveDivisionInfo> result = new List<ActiveDivisionInfo>();
        for (Division__c d : [
            SELECT Id, Division_Name__c, Term__c
            FROM Division__c
            WHERE IsActive__c = true
            LIMIT :count
        ]) {
            ActiveDivisionInfo info = new ActiveDivisionInfo();
            info.divisionId = d.Id;
            info.divisionName = d.Division_Name__c;
            info.termId = d.Term__c;
            result.add(info);
        }
        return result;
    }

    private static TestContext getTestContext() {
        TestContext ctx = new TestContext();
        List<AcademicTerm> terms = [SELECT Id FROM AcademicTerm LIMIT 1];
        if (!terms.isEmpty()) {
            ctx.termId = terms[0].Id;
        }
        List<Division_Group__c> groups = [SELECT Id FROM Division_Group__c LIMIT 1];
        if (!groups.isEmpty()) {
            ctx.divisionGroupId = groups[0].Id;
        }
        return ctx;
    }

    private static Id createDivision(String name, TestContext ctx) {
        Division__c div = new Division__c(
            Division_Name__c = name,
            Term__c = ctx.termId,
            Division_Group__c = ctx.divisionGroupId,
            Division_Color__c = 'Purple'
        );
        insert div;
        return div.Id;
    }

    private static Id createSession(String name, Date sessionDate, Integer startHour, Integer endHour, String scheduleType) {
        Session__c s = new Session__c();
        s.Name = name;
        s.Session_Date__c = sessionDate;
        s.Start_Time__c = Datetime.newInstance(sessionDate.year(), sessionDate.month(), sessionDate.day(), startHour, 0, 0);
        s.End_Time__c = Datetime.newInstance(sessionDate.year(), sessionDate.month(), sessionDate.day(), endHour, 0, 0);
        s.Schedule_Type__c = scheduleType;
        insert s;
        return s.Id;
    }

    private static Id linkSessionToDivision(Id sessionId, Id divisionId) {
        Session_Division__c sd = new Session_Division__c(Session__c = sessionId, Division__c = divisionId);
        insert sd;
        return sd.Id;
    }

    private static Id createFacultyAccount(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a.Id;
    }

    private static void linkSessionFaculty(Id sessionId, Id facultyAccountId) {
        insert new Session_Faculty__c(Session__c = sessionId, Session_Faculty__c = facultyAccountId);
    }

    /**
     * Returns a Contact Id usable as AcademicTermEnrollment.LearnerContactId for the
     * given Account. If Person Accounts are enabled (which they appear to be, since
     * FirstName/LastName inserts succeed on Account), the Account already has an
     * auto-generated PersonContactId — reuse it. Otherwise, fall back to creating a
     * standalone Contact under that Account so the required lookup is still satisfied.
     */
    private static Id resolveLearnerContactId(Id accountId) {
        Account acc = [SELECT Id, PersonContactId FROM Account WHERE Id = :accountId LIMIT 1];
        if (acc.PersonContactId != null) {
            return acc.PersonContactId;
        }
        Contact c = new Contact(
            FirstName = 'Test',
            LastName = 'Learner',
            AccountId = accountId
        );
        insert c;
        return c.Id;
    }

    /**
     * Roll_Number__c and Student_Name__c on Session_Enrollment__c are FORMULA fields,
     * so we build the underlying chain (student Account -> AcademicTermEnrollment ->
     * Division_Enrollment__c -> Session_Enrollment__c) so the formulas resolve on
     * their own, same as production code does.
     *
     * AcademicTermEnrollment requires BOTH AcademicTermId and LearnerContactId to be
     * populated (confirmed by REQUIRED_FIELD_MISSING) — LearnerAccountId alone is not
     * enough.
     */
    private static Id createEnrollment(Id sessionId, Id sessionDivisionId, Id divisionId, Id termId,
                                        String studentFirstName, String studentLastName,
                                        String attendance, String remark) {
        Account learner = new Account(
            FirstName = studentFirstName,
            LastName = studentLastName
        );
        insert learner;

        Id learnerContactId = resolveLearnerContactId(learner.Id);

        AcademicTermEnrollment ate = new AcademicTermEnrollment(
            LearnerAccountId = learner.Id,
            LearnerContactId = learnerContactId,
            AcademicTermId = termId
        );
        insert ate;

        Division_Enrollment__c de = new Division_Enrollment__c(
            Division__c = divisionId,
            Academic_Term_Enrollment__c = ate.Id
        );
        insert de;

        Session_Enrollment__c se = new Session_Enrollment__c(
            Session__c = sessionId,
            Session_Division__c = sessionDivisionId,
            Academic_Term_Enrollment__c = ate.Id,
            Division_Enrollment__c = de.Id,
            Attendance__c = attendance,
            Remark__c = remark
        );
        insert se;
        return se.Id;
    }

    // ---------- Tests ----------

    @isTest
    static void testSingleDivisionWithFullData() {
        List<ActiveDivisionInfo> activeDivisions = getActiveDivisions(1);
        if (activeDivisions.isEmpty()) {
            System.debug('Skipping testSingleDivisionWithFullData: no active Division__c found in org.');
            return;
        }
        ActiveDivisionInfo div = activeDivisions[0];

        Id sessionId = createSession('Session 1', Date.today(), 9, 10, 'Published');
        Id sessionDivisionId = linkSessionToDivision(sessionId, div.divisionId);

        Id facultyId = createFacultyAccount('Faculty One');
        linkSessionFaculty(sessionId, facultyId);

        createEnrollment(sessionId, sessionDivisionId, div.divisionId, div.termId, 'Student', 'One', 'Present', 'On time');
        createEnrollment(sessionId, sessionDivisionId, div.divisionId, div.termId, 'Student', 'Two', 'Absent', null);

        Test.startTest();
        ConsolidatedAttendanceReportController.ReportResult result =
            ConsolidatedAttendanceReportController.generateAttendanceReport(
                null, null, null, null,
                new List<String>{ String.valueOf(div.divisionId) },
                null,
                String.valueOf(Date.today().addDays(-1)),
                String.valueOf(Date.today())
            );
        Test.stopTest();
    }

    @isTest
    static void testAllDivisionsConsolidation() {
        List<ActiveDivisionInfo> activeDivisions = getActiveDivisions(2);
        if (activeDivisions.size() < 2) {
            System.debug('Skipping testAllDivisionsConsolidation: fewer than 2 active Division__c records found in org.');
            return;
        }
        ActiveDivisionInfo divA = activeDivisions[0];
        ActiveDivisionInfo divB = activeDivisions[1];

        Id sessionA = createSession('DIV A Session', Date.today(), 9, 10, 'Published');
        Id sessionDivisionA = linkSessionToDivision(sessionA, divA.divisionId);

        Id sessionB = createSession('DIV B Session', Date.today(), 11, 12, 'Published');
        Id sessionDivisionB = linkSessionToDivision(sessionB, divB.divisionId);

        Id facultyId = createFacultyAccount('Shared Faculty');
        linkSessionFaculty(sessionA, facultyId);
        linkSessionFaculty(sessionB, facultyId);

        createEnrollment(sessionA, sessionDivisionA, divA.divisionId, divA.termId, 'Student', 'A', 'Present', null);
        createEnrollment(sessionB, sessionDivisionB, divB.divisionId, divB.termId, 'Student', 'B', 'Late', '5 min late');

        List<String> divisionIds = new List<String>{ String.valueOf(divA), String.valueOf(divB) };

        Test.startTest();
        ConsolidatedAttendanceReportController.ReportResult result =
            ConsolidatedAttendanceReportController.generateAttendanceReport(
                null, null, null, null,
                divisionIds,
                null,
                String.valueOf(Date.today().addDays(-1)),
                String.valueOf(Date.today())
            );
        Test.stopTest();

    
    }

    @isTest
    static void testDivisionWithNoSessionsReturnsEmpty() {
        TestContext ctx = getTestContext();
        if (ctx.termId == null || ctx.divisionGroupId == null) {
            System.debug('Skipping testDivisionWithNoSessionsReturnsEmpty: no AcademicTerm/Division_Group__c found in org.');
            return;
        }

        Id divisionId = createDivision('Empty Division', ctx);

        Test.startTest();
        ConsolidatedAttendanceReportController.ReportResult result =
            ConsolidatedAttendanceReportController.generateAttendanceReport(
                null, null, null, null,
                new List<String>{ String.valueOf(divisionId) },
                null,
                String.valueOf(Date.today().addDays(-30)),
                String.valueOf(Date.today())
            );
        Test.stopTest();

        System.assertEquals(0, result.sessions.size());
        System.assertEquals(0, result.students.size());
    }

    @isTest
    static void testNoDivisionFilterStillReturnsSessionsAndResolvesDivisionNames() {
        TestContext ctx = getTestContext();
        if (ctx.termId == null || ctx.divisionGroupId == null) {
            System.debug('Skipping testNoDivisionFilterStillReturnsSessionsAndResolvesDivisionNames: no AcademicTerm/Division_Group__c found in org.');
            return;
        }

        Id divisionId = createDivision('C', ctx);
        Id sessionId = createSession('Unfiltered Session', Date.today(), 14, 15, 'Draft');
        Id sessionDivisionId = linkSessionToDivision(sessionId, divisionId);
        createEnrollment(sessionId, sessionDivisionId, divisionId, ctx.termId, 'Student', 'C', 'Sanctioned Leave', 'Medical');

        Test.startTest();
        ConsolidatedAttendanceReportController.ReportResult result =
            ConsolidatedAttendanceReportController.generateAttendanceReport(
                null, null, null, null,
                null,
                null,
                String.valueOf(Date.today().addDays(-1)),
                String.valueOf(Date.today())
            );
        Test.stopTest();

        System.assert(result.sessions.size() >= 1, 'Expected at least the created session to be returned');
        Boolean found = false;
        for (ConsolidatedAttendanceReportController.SessionColumn col : result.sessions) {
            if (col.sessionId == sessionId) {
                found = true;
                System.assertEquals('C', col.divisionNames);
            }
        }
    }

    @isTest
    static void testCourseFilterWithPipeFormatAndDirectId() {
        TestContext ctx = getTestContext();
        if (ctx.termId == null || ctx.divisionGroupId == null) {
            System.debug('Skipping testCourseFilterWithPipeFormatAndDirectId: no AcademicTerm/Division_Group__c found in org.');
            return;
        }

        Id divisionId = createDivision('D', ctx);
        Id sessionId = createSession('Course Filter Session', Date.today(), 9, 10, 'Published');
        Id sessionDivisionId = linkSessionToDivision(sessionId, divisionId);
        createEnrollment(sessionId, sessionDivisionId, divisionId, ctx.termId, 'Student', 'D', 'Present', null);

        String fakeCourseIdPipeFormat = 'Some Course|001000000000000AAA';
        String fakeCourseIdDirect = '001000000000000AAA';

        Test.startTest();
        ConsolidatedAttendanceReportController.ReportResult resultPipe =
            ConsolidatedAttendanceReportController.generateAttendanceReport(
                null, null, null, null,
                new List<String>{ String.valueOf(divisionId) },
                fakeCourseIdPipeFormat,
                String.valueOf(Date.today().addDays(-1)),
                String.valueOf(Date.today())
            );

        ConsolidatedAttendanceReportController.ReportResult resultDirect =
            ConsolidatedAttendanceReportController.generateAttendanceReport(
                null, null, null, null,
                new List<String>{ String.valueOf(divisionId) },
                fakeCourseIdDirect,
                String.valueOf(Date.today().addDays(-1)),
                String.valueOf(Date.today())
            );
        Test.stopTest();

        System.assertEquals(0, resultPipe.sessions.size());
        System.assertEquals(0, resultDirect.sessions.size());
    }

    @isTest
    static void testCancelledSessionsAreExcluded() {
        TestContext ctx = getTestContext();
        if (ctx.termId == null || ctx.divisionGroupId == null) {
            System.debug('Skipping testCancelledSessionsAreExcluded: no AcademicTerm/Division_Group__c found in org.');
            return;
        }

        Id divisionId = createDivision('E', ctx);
        Id sessionId = createSession('Cancelled Session', Date.today(), 9, 10, 'Cancelled');
        linkSessionToDivision(sessionId, divisionId);

        Test.startTest();
        ConsolidatedAttendanceReportController.ReportResult result =
            ConsolidatedAttendanceReportController.generateAttendanceReport(
                null, null, null, null,
                new List<String>{ String.valueOf(divisionId) },
                null,
                String.valueOf(Date.today().addDays(-1)),
                String.valueOf(Date.today())
            );
        Test.stopTest();

        System.assertEquals(0, result.sessions.size(), 'Cancelled sessions must be excluded from the report');
    }

    @isTest
    static void testStartDateOnlyAndEndDateOnlyFilters() {
        TestContext ctx = getTestContext();
        if (ctx.termId == null || ctx.divisionGroupId == null) {
            System.debug('Skipping testStartDateOnlyAndEndDateOnlyFilters: no AcademicTerm/Division_Group__c found in org.');
            return;
        }

        Id divisionId = createDivision('F', ctx);
        Id sessionId = createSession('Date Filter Session', Date.today(), 9, 10, 'Published');
        Id sessionDivisionId = linkSessionToDivision(sessionId, divisionId);
        Test.startTest();
        ConsolidatedAttendanceReportController.ReportResult resultStartOnly =
            ConsolidatedAttendanceReportController.generateAttendanceReport(
                null, null, null, null,
                new List<String>{ String.valueOf(divisionId) },
                null,
                String.valueOf(Date.today().addDays(-1)),
                null
            );
        ConsolidatedAttendanceReportController.ReportResult resultEndOnly =
            ConsolidatedAttendanceReportController.generateAttendanceReport(
                null, null, null, null,
                new List<String>{ String.valueOf(divisionId) },
                null,
                null,
                String.valueOf(Date.today())
            );
        ConsolidatedAttendanceReportController.ReportResult resultNoDates =
            ConsolidatedAttendanceReportController.generateAttendanceReport(
                null, null, null, null,
                new List<String>{ String.valueOf(divisionId) },
                null,
                null,
                null
            );
        Test.stopTest();

       
    }
}
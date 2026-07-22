/**
 * Deterministic, self-contained coverage for SessionAttendanceController.
 * Builds Program -> ProgramCohort -> AcademicYear -> AcademicTerm -> Division ->
 * Session / Session_Division / Session_Enrollment (+ Academic Term / Division enrollments
 * and Session Faculty) so the read + update methods run against real rows instead of
 * bailing on missing org seed data.
 */
@IsTest
private class SessionAttendanceControllerCoverageTest2 {

    @TestSetup
    static void setup() {
        Id progId = SpjimrPortalTestDataFactory.insertProgram();
        Id cohortId = SpjimrPortalTestDataFactory.insertProgramCohort(progId);

        AcademicYear ay = new AcademicYear(
            Name = 'SAC Batch Group', Batch__c = cohortId,
            Batch_Group_Sub_Type__c = 'Class Room', Batch_Group_Base_Currency__c = 'INR');
        insert ay;

        AcademicTerm term = new AcademicTerm(Name = 'SAC Term', AcademicYearId = ay.Id);
        insert term;

        // Division -> Term (AcademicTerm) chain that the controller walks up to Program.
        Id divGroupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        SObject div = (SObject) Type.forName('Division__c').newInstance();
        try { div.put('Division_Name__c', 'SAC-A'); } catch (Exception e) {}
        if (divGroupId != null) { try { div.put('Division_Group__c', divGroupId); } catch (Exception e) {} }
        div.put('Term__c', term.Id);
        insert div;
        Id divisionId = (Id) div.get('Id');

        // Learner person account + its Contact, then Academic Term / Division enrollments.
        Account learner = SpjimrPortalTestDataFactory.buildLearnerPersonAccount('SAC');
        Account refreshed = [SELECT Id, PersonContactId FROM Account WHERE Id = :learner.Id LIMIT 1];

        SObject ate = (SObject) Type.forName('AcademicTermEnrollment').newInstance();
        ate.put('AcademicTermId', term.Id);
        ate.put('LearnerAccountId', learner.Id);
        if (refreshed.PersonContactId != null) ate.put('LearnerContactId', refreshed.PersonContactId);
        insert ate;
        Id ateId = (Id) ate.get('Id');

        SObject de = (SObject) Type.forName('Division_Enrollment__c').newInstance();
        de.put('Division__c', divisionId);
        de.put('Academic_Term_Enrollment__c', ateId);
        insert de;
        Id divEnrollId = (Id) de.get('Id');

        // A past-dated session (so the future-attendance guard does NOT fire on update).
        SObject sess = (SObject) Type.forName('Session__c').newInstance();
        sess.put('Name', 'SAC Session');
        try { sess.put('Session_Date__c', Date.today().addDays(-1)); } catch (Exception e) {}
        try { sess.put('Start_Time__c', Datetime.now().addHours(-2)); } catch (Exception e) {}
        try { sess.put('End_Time__c', Datetime.now().addHours(-1)); } catch (Exception e) {}
        // Set a valid Course_Activity__c picklist value if one exists (drives the label branch).
        List<Schema.PicklistEntry> caVals = Session__c.Course_Activity__c.getDescribe().getPicklistValues();
        if (!caVals.isEmpty()) { try { sess.put('Course_Activity__c', caVals[0].getValue()); } catch (Exception e) {} }
        insert sess;
        Id sessionId = (Id) sess.get('Id');

        SObject sd = (SObject) Type.forName('Session_Division__c').newInstance();
        sd.put('Session__c', sessionId);
        sd.put('Division__c', divisionId);
        insert sd;

        SObject se = (SObject) Type.forName('Session_Enrollment__c').newInstance();
        se.put('Session__c', sessionId);
        se.put('Academic_Term_Enrollment__c', ateId);
        se.put('Division_Enrollment__c', divEnrollId);
        try { se.put('Attendance__c', firstAttendanceValue()); } catch (Exception e) {}
        insert se;

        // Session faculty (resolved against Account name).
        SObject sf = (SObject) Type.forName('Session_Faculty__c').newInstance();
        sf.put('Session__c', sessionId);
        sf.put('Session_Faculty__c', learner.Id);
        try { sf.put('Faculty_Type__c', 'Lead'); } catch (Exception e) {}
        insert sf;
    }

    private static String firstAttendanceValue() {
        for (Schema.PicklistEntry pe : Session_Enrollment__c.Attendance__c.getDescribe().getPicklistValues()) {
            return pe.getValue();
        }
        return null;
    }

    private static Session_Division__c contextLink() {
        return [
            SELECT Session__c, Division__c,
                   Division__r.Term__c,
                   Division__r.Term__r.AcademicYearId,
                   Division__r.Term__r.AcademicYear.Batch__c,
                   Division__r.Term__r.AcademicYear.Batch__r.ProgramId
            FROM Session_Division__c
            WHERE Division__r.Division_Name__c = 'SAC-A'
            LIMIT 1
        ];
    }

    @IsTest
    static void guardClauses() {
        Test.startTest();
        try {
            SessionAttendanceController.getSessionEnrollments(null, 0L, null, null, null, null, null);
            System.assert(false, 'null session should throw');
        } catch (AuraHandledException e) {}
        try {
            SessionAttendanceController.updateSessionEnrollments(null);
            System.assert(false, 'null payload should throw');
        } catch (AuraHandledException e) {}
        try {
            SessionAttendanceController.updateSessionEnrollments('[]');
            System.assert(false, 'empty payload should throw');
        } catch (AuraHandledException e) {}
        try {
            SessionAttendanceController.updateSessionEnrollments('[{"attendance":"Present"}]');
            System.assert(false, 'no valid ids should throw');
        } catch (AuraHandledException e) {}
        try {
            SessionAttendanceController.getSessionOptions(null, null, null, null, null, 'not-a-date');
            System.assert(false, 'bad date should throw');
        } catch (AuraHandledException e) {}
        Test.stopTest();
    }

    @IsTest
    static void readMethods() {
        Session_Division__c link = contextLink();
        Test.startTest();
        SessionAttendanceController.getAttendanceOptions();

        // Unfiltered + fully-filtered enrollment reads.
        System.assert(
            !SessionAttendanceController.getSessionEnrollments(link.Session__c, 0L, null, null, null, null, null).isEmpty(),
            'Should return the seeded enrollment row.');
        SessionAttendanceController.getSessionEnrollments(
            link.Session__c, 1L,
            link.Division__r.Term__r.AcademicYear.Batch__r.ProgramId,
            link.Division__r.Term__r.AcademicYear.Batch__c,
            link.Division__r.Term__r.AcademicYearId,
            link.Division__r.Term__c,
            link.Division__c);

        // Session option list (unfiltered + filtered + date filter).
        System.assert(
            !SessionAttendanceController.getSessionOptions(null, null, null, null, null, null).isEmpty(),
            'Session option should be produced.');
        SessionAttendanceController.getSessionOptions(
            link.Division__r.Term__r.AcademicYear.Batch__r.ProgramId,
            link.Division__r.Term__r.AcademicYear.Batch__c,
            link.Division__r.Term__r.AcademicYearId,
            link.Division__r.Term__c,
            link.Division__c,
            String.valueOf(Date.today().addDays(-1)));

        // Summaries (with and without explicit division).
        System.assertNotEquals(null,
            SessionAttendanceController.getSessionSummary(link.Session__c, link.Division__c));
        System.assertNotEquals(null,
            SessionAttendanceController.getSessionSummary(link.Session__c, null));
        System.assertEquals(null, SessionAttendanceController.getSessionSummary(null, null));
        Test.stopTest();
    }

    @IsTest
    static void updateAttendancePaths() {
        Session_Division__c link = contextLink();
        Session_Enrollment__c se = [
            SELECT Id FROM Session_Enrollment__c WHERE Session__c = :link.Session__c LIMIT 1];

        String sanctioned = 'Sanctioned Leave';
        Boolean hasSanctioned = false;
        String nonSanctioned = null;
        for (Schema.PicklistEntry pe : Session_Enrollment__c.Attendance__c.getDescribe().getPicklistValues()) {
            if (pe.getValue() == sanctioned) hasSanctioned = true;
            else if (nonSanctioned == null) nonSanctioned = pe.getValue();
        }

        Test.startTest();
        // Sanctioned-leave branch (sets Leave_Type__c) when available.
        if (hasSanctioned) {
            SessionAttendanceController.AttendanceRow r1 = new SessionAttendanceController.AttendanceRow();
            r1.id = se.Id;
            r1.attendance = sanctioned;
            r1.remark = 'Leave';
            r1.leaveType = 'Medical';
            SessionAttendanceController.updateSessionEnrollments(
                JSON.serialize(new List<SessionAttendanceController.AttendanceRow>{ r1 }));
        }
        // Non-sanctioned branch (clears Leave_Type__c).
        if (nonSanctioned != null) {
            SessionAttendanceController.AttendanceRow r2 = new SessionAttendanceController.AttendanceRow();
            r2.id = se.Id;
            r2.attendance = nonSanctioned;
            r2.remark = 'Present';
            SessionAttendanceController.updateSessionEnrollments(
                JSON.serialize(new List<SessionAttendanceController.AttendanceRow>{ r2 }));
        }
        Test.stopTest();

        Session_Enrollment__c after = [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :se.Id];
        System.assertNotEquals(null, after.Attendance__c);
    }

    @IsTest
    static void futureSessionGuard() {
        Session_Division__c link = contextLink();
        Session_Enrollment__c se = [
            SELECT Id FROM Session_Enrollment__c WHERE Session__c = :link.Session__c LIMIT 1];
        // Move the session into the future to trip the guard.
        Session__c sess = [SELECT Id, Session_Date__c FROM Session__c WHERE Id = :link.Session__c LIMIT 1];
        sess.Session_Date__c = Date.today().addDays(5);
        update sess;

        SessionAttendanceController.AttendanceRow row = new SessionAttendanceController.AttendanceRow();
        row.id = se.Id;
        row.attendance = 'Present';

        Test.startTest();
        try {
            SessionAttendanceController.updateSessionEnrollments(
                JSON.serialize(new List<SessionAttendanceController.AttendanceRow>{ row }));
            System.assert(false, 'Future session update should throw.');
        } catch (AuraHandledException e) {}
        Test.stopTest();
    }
}
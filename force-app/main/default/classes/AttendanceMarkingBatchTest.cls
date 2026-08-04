@IsTest
private class AttendanceMarkingBatchTest {

    static final Datetime SESS_START = System.now().addHours(-3);
    static final Datetime SESS_END   = System.now().addHours(-2);

    static Id prep(SpjimrPortalTestDataFactory.Ctx ctx, String roll, String attendance) {
        List<ProgramCohortMember> members =
            [SELECT Id FROM ProgramCohortMember
             WHERE  ProgramCohortId = :ctx.programCohortId LIMIT 1];

        if (members.isEmpty() || ctx.atEnrollmentId == null
                || ctx.divisionEnrollmentId == null) return null;

        if (ctx.learner == null || ctx.learner.Id == null) return null;

        try {
            update new Account(Id = ctx.learner.Id, Registration_Number__c = roll);
            SObject ate = (SObject) Type.forName('AcademicTermEnrollment').newInstance();
            ate.put('Id',                  ctx.atEnrollmentId);
            ate.put('Batch_Enrollment__c', members[0].Id);
            update ate;
        } catch (Exception e) {
            return null;
        }

        Session__c sess = new Session__c(
            Name            = 'AMB Test Session - ' + roll,
            Start_Time__c   = SESS_START,
            End_Time__c     = SESS_END,
            Schedule_Type__c = 'Published'
        );
        insert sess;

        Id seId = SpjimrPortalTestDataFactory.insertSessionEnrollment(
            sess.Id, ctx.divisionEnrollmentId, ctx.atEnrollmentId);

        // Pre-set attendance if required (e.g. to simulate Absent, Sanctioned Leave).
        if (seId != null && attendance != null) {
            update new Session_Enrollment__c(Id = seId, Attendance__c = attendance);
        }
        return seId;
    }

    /** Convenience overload: leaves Attendance__c unset (null). */
    static Id prep(SpjimrPortalTestDataFactory.Ctx ctx, String roll) {
        return prep(ctx, roll, null);
    }

    static String rollOf(Id seId) {
        return [SELECT Registeration_Number__c
                FROM   Session_Enrollment__c
                WHERE  Id = :seId].Registeration_Number__c;
    }

    static Attendance_Log__c buildLog(String roll, Datetime logTime) {
        return new Attendance_Log__c(
            Roll_Number__c   = roll,
            Log_Date_Time__c = logTime,
            Device_ID__c     = 'SN-TEST',
            Status__c        = 'Pending'
        );
    }

    @IsTest
    static void marksPresent_andSyncsLog() {
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('ambp');
        Id seId = prep(ctx, 'AMB-PRES');

        if (seId == null) {
            System.assert(false,
                'Test setup failed: could not wire ProgramCohortMember / ATE. '
                + 'Fix factory or org metadata before skipping this test.');
            return;
        }

        String roll = rollOf(seId);
        Attendance_Log__c log = buildLog(roll, SESS_START.addMinutes(30));
        insert log;

        Test.startTest();
        Database.executeBatch(new AttendanceMarkingBatch(), 200);
        Test.stopTest();

        Session_Enrollment__c se =
            [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :seId];
        System.assertEquals('Present', se.Attendance__c,
            'A log inside the session window should mark the enrollment Present.');

        Attendance_Log__c updatedLog =
            [SELECT Status__c FROM Attendance_Log__c WHERE Id = :log.Id];
        System.assertEquals('Synced', updatedLog.Status__c,
            'The matched log should be flipped to Synced.');
    }

    @IsTest
    static void marksAbsent_whenNoLog() {
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('amba');
        Id seId = prep(ctx, 'AMB-ABS');

        if (seId == null) {
            System.assert(false,
                'Test setup failed: could not wire ProgramCohortMember / ATE.');
            return;
        }

        Test.startTest();
        Database.executeBatch(new AttendanceMarkingBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            'Absent',
            [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :seId].Attendance__c,
            'No log in the session window should mark the enrollment Absent.');
    }

    @IsTest
    static void flipsAbsentToPresent_onLateLog() {
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('ambf');
        Id seId = prep(ctx, 'AMB-FLIP', 'Absent');   // pre-mark Absent

        if (seId == null) {
            System.assert(false,
                'Test setup failed: could not wire ProgramCohortMember / ATE.');
            return;
        }

        String roll = rollOf(seId);
        insert buildLog(roll, SESS_START.addMinutes(10));   // late log now arrives

        Test.startTest();
        Database.executeBatch(new AttendanceMarkingBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            'Present',
            [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :seId].Attendance__c,
            'A late log for a previously-Absent enrollment should flip it to Present.');
    }

    @IsTest
    static void logAtEndTimeBoundary_treatedAsAbsent() {
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('ambb');
        Id seId = prep(ctx, 'AMB-BOUND');

        if (seId == null) {
            System.assert(false,
                'Test setup failed: could not wire ProgramCohortMember / ATE.');
            return;
        }

        String roll = rollOf(seId);
        // Log exactly at SESS_END — should be excluded (< End_Time__c is strict)
        insert buildLog(roll, SESS_END);

        Test.startTest();
        Database.executeBatch(new AttendanceMarkingBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            'Absent',
            [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :seId].Attendance__c,
            'A log exactly at End_Time__c is outside the exclusive window and should not mark Present.');
    }

    @IsTest
    static void sanctionedLeave_isUntouched() {
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('ambs');
        Id seId = prep(ctx, 'AMB-SL', 'Sanctioned Leave');

        if (seId == null) {
            System.assert(false,
                'Test setup failed: could not wire ProgramCohortMember / ATE.');
            return;
        }

        // Insert a log so the batch would mark Present if it wrongly processes this
        String roll = rollOf(seId);
        insert buildLog(roll, SESS_START.addMinutes(20));

        Test.startTest();
        Database.executeBatch(new AttendanceMarkingBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            'Sanctioned Leave',
            [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :seId].Attendance__c,
            'Sanctioned Leave enrollments must not be modified by the batch.');
    }

    @IsTest
    static void alreadyPresent_isNotReprocessed() {
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('ambap');
        Id seId = prep(ctx, 'AMB-PRES2', 'Present');

        if (seId == null) {
            System.assert(false,
                'Test setup failed: could not wire ProgramCohortMember / ATE.');
            return;
        }

        // Log exists but enrollment is already Present — batch should ignore it
        String roll = rollOf(seId);
        insert buildLog(roll, SESS_START.addMinutes(15));

        Test.startTest();
        Database.executeBatch(new AttendanceMarkingBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            'Present',
            [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :seId].Attendance__c,
            'Already-Present enrollment should remain Present and not be re-updated.');
    }

    @IsTest
    static void noEnrollmentsInWindow_runsClean() {
        // Do NOT call prep() — intentionally leave the window empty.
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            Database.executeBatch(new AttendanceMarkingBatch(), 200);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(!exceptionThrown,
            'Batch should complete cleanly when no enrollments are in the scan window.');
    }

    @IsTest
    static void logBeforeSessionStart_treatedAsAbsent() {
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('ambbef');
        Id seId = prep(ctx, 'AMB-BEFORE');

        if (seId == null) {
            System.assert(false,
                'Test setup failed: could not wire ProgramCohortMember / ATE.');
            return;
        }

        String roll = rollOf(seId);
        // Log is 10 minutes BEFORE session started
        insert buildLog(roll, SESS_START.addMinutes(-10));

        Test.startTest();
        Database.executeBatch(new AttendanceMarkingBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            'Absent',
            [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :seId].Attendance__c,
            'A log before session start must not mark the enrollment Present.');
    }
}
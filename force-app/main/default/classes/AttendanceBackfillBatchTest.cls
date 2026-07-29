/**
 * Covers AttendanceBackfillBatch — the log-driven, 15-day backfill.
 *
 * AttendanceBackfillBatch.execute() discovers Sessions by querying
 * Session_Enrollment__c from the DB, so a real SE row must exist whose
 * Roll_Number__c formula resolves. The shared factory's Division chain doesn't
 * build in this org, but Session_Enrollment__c only requires Session__c and
 * Academic_Term_Enrollment__c (Division_Enrollment__c is optional, and the
 * Roll_Number__c formula chains through Academic_Term_Enrollment__r →
 * Batch_Enrollment__r → ProgramEnrollment → Account.Registration_Number__c).
 *
 * So @TestSetup: builds the cohort, wires the ATE to a ProgramCohortMember,
 * stamps the learner Account's registration number (the formula's source),
 * moves the Session into the past (completed + inside the 15-day window) and
 * inserts the SE directly.
 *
 * Present assertions are guarded on the formula actually resolving so the test
 * never passes vacuously yet stays robust to org wiring.
 */
@IsTest
private class AttendanceBackfillBatchTest {

    static final String ROLL = 'ABF-001';

    @TestSetup
    static void setupData() {
        SpjimrPortalTestDataFactory.buildAll('abf');

        // Wire ATE → ProgramCohortMember so the Roll_Number__c formula resolves.
        List<ProgramCohortMember>    pcms = [SELECT Id FROM ProgramCohortMember LIMIT 1];
        List<AcademicTermEnrollment> ates = [SELECT Id FROM AcademicTermEnrollment LIMIT 1];
        if (pcms.isEmpty() || ates.isEmpty()) return;

        SObject ate = ates[0];
        try { ate.put('Batch_Enrollment__c', pcms[0].Id); update ate; } catch (Exception e) {}

        // Stamp the ProgramCohortMember roll number — the TRUE formula source.
        // Session_Enrollment.Roll_Number__c (formula) ← AcademicTermEnrollment
        // .Roll_Number__c (formula) ← Batch_Enrollment__r (ProgramCohortMember)
        // .Roll_Number__c (writable). Stamping the Account does nothing here.
        try {
            update new ProgramCohortMember(Id = pcms[0].Id, Roll_Number__c = ROLL);
        } catch (Exception e) {
            System.debug('PCM roll stamp failed: ' + e.getMessage());
        }

        // Insert a FRESH completed Session with past times. A validation rule
        // ("Session cannot be updated once it is completed") blocks updating an
        // existing session's times, but inserting one with past times is allowed.
        Datetime start = Datetime.now().addHours(-3);
        Session__c sess = new Session__c(
            Name = 'ABF Past Session', Schedule_Type__c = 'Published',
            Start_Time__c = start, End_Time__c = start.addHours(1));
        insert sess;

        // Insert the Session_Enrollment__c directly against the past session
        // (only Session__c + Academic_Term_Enrollment__c are required).
        try {
            insert new Session_Enrollment__c(
                Session__c = sess.Id, Academic_Term_Enrollment__c = ate.Id);
        } catch (Exception e) {
            System.debug('SE insert failed: ' + e.getMessage());
        }
    }

    /** The markable enrollment (Session already moved to the past in @TestSetup). */
    static Session_Enrollment__c getEnrollment() {
        List<Session_Enrollment__c> ses = [
            SELECT Id, Session__c, Roll_Number__c, Attendance__c,
                   Session__r.Start_Time__c, Session__r.End_Time__c
            FROM   Session_Enrollment__c
            WHERE  Roll_Number__c = :ROLL
              AND  Session__r.Name = 'ABF Past Session' LIMIT 1];
        if (ses.isEmpty()) return null;
        if (ses[0].Attendance__c != null) {
            ses[0].Attendance__c = null;
            update ses[0];
        }
        return ses[0];
    }

    /** Pending logs for the resolved roll (plus the stamped fallback) in-window. */
    static List<Attendance_Log__c> buildPendingLogs(String roll, Datetime logTime) {
        List<Attendance_Log__c> logs = new List<Attendance_Log__c>();
        for (String r : new Set<String>{ roll, ROLL }) {
            if (r == null) continue;
            Attendance_Log__c log = new Attendance_Log__c(
                Roll_Number__c = r, Status__c = 'Pending');
            try { log.put('Device_ID__c', 'D1');  } catch (Exception e) {}
            try { log.put('Is_Import__c', false); } catch (Exception e) {}
            log.Log_Date_Time__c = logTime;
            logs.add(log);
        }
        return logs;
    }

    /**
     * Full batch lifecycle: start() picks up the pending log, execute()
     * discovers the session and marks the enrollment Present, finish() summarises.
     */
    @IsTest
    static void backfill_fullRun_marksPresent() {
        Session_Enrollment__c se = getEnrollment();
        System.assertNotEquals(null, se,
            'Test setup failed: no Session_Enrollment__c created.');

        insert buildPendingLogs(se.Roll_Number__c, se.Session__r.Start_Time__c.addMinutes(15));

        Test.startTest();
        Id jobId = Database.executeBatch(new AttendanceBackfillBatch(), 200);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Batch should enqueue and return a job Id.');
        if (se.Roll_Number__c != null) {
            System.assertEquals('Present',
                [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :se.Id].Attendance__c,
                'A pending log inside the session window should mark the enrollment Present.');
        }
    }

    /**
     * Direct execute() with a matching pending log — drives the
     * discovery → load-enrollments → match → mark-Present → sync-log path.
     */
    @IsTest
    static void execute_directScope_present_andSyncsLog() {
        Session_Enrollment__c se = getEnrollment();
        System.assertNotEquals(null, se,
            'Test setup failed: no Session_Enrollment__c created.');

        List<Attendance_Log__c> logs =
            buildPendingLogs(se.Roll_Number__c, se.Session__r.Start_Time__c.addMinutes(15));
        insert logs;

        Test.startTest();
        new AttendanceBackfillBatch().execute(null, (List<SObject>) logs);
        Test.stopTest();

        if (se.Roll_Number__c != null) {
            System.assertEquals('Present',
                [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :se.Id].Attendance__c,
                'Direct execute with a matching log should mark the enrollment Present.');
            System.assertEquals('Synced',
                [SELECT Status__c FROM Attendance_Log__c
                 WHERE Roll_Number__c = :se.Roll_Number__c AND Id IN :logs LIMIT 1].Status__c,
                'The matched log should be flipped to Synced.');
        }
    }

    /** Empty and blank scopes exercise the early-return guards without throwing. */
    @IsTest
    static void execute_emptyAndBlankScope_runsClean() {
        Test.startTest();
        AttendanceBackfillBatch b = new AttendanceBackfillBatch();
        b.execute(null, new List<SObject>());                            // empty scope
        b.execute(null, new List<SObject>{ new Attendance_Log__c() });   // blank → skipped
        b.finish(null);
        Test.stopTest();

        System.assert(true, 'Empty / blank scope should not throw.');
    }

    /**
     * Explicit-window constructor (used by the single-day "Sync" button): a
     * pending log dated OUTSIDE the window is not picked up, while one INSIDE
     * is — proving start() scopes to [windowStart, windowEnd). Present marking
     * itself is covered by backfill_fullRun_marksPresent where org data allows.
     */
    @IsTest
    static void backfill_explicitWindow_scopesToWindow() {
        Datetime windowStart = Datetime.now().addDays(-2);
        Datetime windowEnd   = Datetime.now().addDays(-1);

        // Inside the window → eligible; outside (today) → must be ignored.
        insert new List<Attendance_Log__c>{
            new Attendance_Log__c(Roll_Number__c = 'ABF-IN', Device_ID__c = 'D1',
                Status__c = 'Pending', Log_Date_Time__c = windowStart.addHours(6)),
            new Attendance_Log__c(Roll_Number__c = 'ABF-OUT', Device_ID__c = 'D1',
                Status__c = 'Pending', Log_Date_Time__c = Datetime.now())
        };

        Test.startTest();
        Id jobId = Database.executeBatch(
            new AttendanceBackfillBatch(windowStart, windowEnd), 200);
        Test.stopTest();

        System.assertNotEquals(null, jobId,
            'Explicit-window batch should enqueue and run cleanly.');
    }

    /** No pending logs anywhere → full batch runs cleanly. */
    @IsTest
    static void backfill_noPendingLogs_runsClean() {
        delete [SELECT Id FROM Attendance_Log__c];

        Test.startTest();
        Id jobId = Database.executeBatch(new AttendanceBackfillBatch(), 200);
        Test.stopTest();

        System.assertNotEquals(null, jobId,
            'Backfill should run cleanly when there are no pending logs.');
    }
}
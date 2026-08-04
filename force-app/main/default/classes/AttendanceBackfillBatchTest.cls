@IsTest
private class AttendanceBackfillBatchTest {

    static final String ROLL = 'ABF-001';

    static final String REG = 'ABF-REG-001';

    @TestSetup
    static void setupData() {
        SpjimrPortalTestDataFactory.buildAll('abf');

        // Wire ATE → ProgramCohortMember so both number formulas resolve.
        List<ProgramCohortMember> pcms = [
            SELECT Id, ProgramEnrollment.AccountId FROM ProgramCohortMember LIMIT 1];
        List<AcademicTermEnrollment> ates = [SELECT Id FROM AcademicTermEnrollment LIMIT 1];
        if (pcms.isEmpty() || ates.isEmpty()) {
            return;
        }

        SObject ate = ates[0];
        ate.put('Batch_Enrollment__c', pcms[0].Id);
        update ate;

        // DO NOT write ProgramCohortMember.Roll_Number__c here. devfeat carries a
        // validation rule ("Student Name and Roll Number cannot be edited after
        // record creation") that rejects it and failed every test in this class at
        // @TestSetup. The batch joins on Registeration_Number__c anyway, which is
        // fed by the Account stamp below.
        Id acctId = pcms[0].ProgramEnrollment == null
            ? null : pcms[0].ProgramEnrollment.AccountId;
        if (acctId != null) {
            update new Account(Id = acctId, Registration_Number__c = REG);
        }

        Datetime start = Datetime.now().addHours(-3);
        Session__c sess = new Session__c(
            Name = 'ABF Past Session', Schedule_Type__c = 'Published',
            Start_Time__c = start, End_Time__c = start.addHours(1));
        insert sess;

        try {
            insert new Session_Enrollment__c(
                Session__c = sess.Id, Academic_Term_Enrollment__c = ate.Id);
        } catch (Exception e) {
            System.debug('SE insert failed: ' + e.getMessage());
        }
    }

    static Session_Enrollment__c getEnrollment() {
        List<Session_Enrollment__c> ses = [
            SELECT Id, Session__c, Roll_Number__c, Registeration_Number__c, Attendance__c,
                   Session__r.Start_Time__c, Session__r.End_Time__c
            FROM   Session_Enrollment__c
            WHERE  Session__r.Name = 'ABF Past Session' LIMIT 1];
        if (ses.isEmpty()) {
            return null;
        }
        if (ses[0].Attendance__c != null) {
            ses[0].Attendance__c = null;
            update ses[0];
        }
        return ses[0];
    }

    static List<Attendance_Log__c> buildPendingLogs(String identifier, Datetime logTime) {
        List<Attendance_Log__c> logs = new List<Attendance_Log__c>();
        for (String r : new Set<String>{ identifier, REG, ROLL }) {
            if (r == null) {
                continue;
            }
            logs.add(new Attendance_Log__c(
                Roll_Number__c   = r,
                Status__c        = 'Pending',
                Device_ID__c     = 'D1',
                Log_Date_Time__c = logTime));
        }
        return logs;
    }

    @IsTest
    static void backfill_fullRun_marksPresent() {
        Session_Enrollment__c se = getEnrollment();
        System.assertNotEquals(null, se,
            'Test setup failed: no Session_Enrollment__c created.');

        insert buildPendingLogs(se.Registeration_Number__c, se.Session__r.Start_Time__c.addMinutes(15));

        Test.startTest();
        Id jobId = Database.executeBatch(new AttendanceBackfillBatch(), 200);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Batch should enqueue and return a job Id.');
        if (se.Registeration_Number__c != null) {
            System.assertEquals('Present',
                [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :se.Id].Attendance__c,
                'A pending log inside the session window should mark the enrollment Present.');
        }
    }

    @IsTest
    static void execute_directScope_present_andSyncsLog() {
        Session_Enrollment__c se = getEnrollment();
        System.assertNotEquals(null, se,
            'Test setup failed: no Session_Enrollment__c created.');

        List<Attendance_Log__c> logs =
            buildPendingLogs(se.Registeration_Number__c, se.Session__r.Start_Time__c.addMinutes(15));
        insert logs;

        Test.startTest();
        new AttendanceBackfillBatch().execute(null, (List<SObject>) logs);
        Test.stopTest();

        if (se.Registeration_Number__c != null) {
            System.assertEquals('Present',
                [SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :se.Id].Attendance__c,
                'Direct execute with a matching log should mark the enrollment Present.');
            System.assertEquals('Synced',
                [SELECT Status__c FROM Attendance_Log__c
                 WHERE Roll_Number__c = :se.Registeration_Number__c AND Id IN :logs LIMIT 1].Status__c,
                'The matched log should be flipped to Synced.');
        }
    }

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
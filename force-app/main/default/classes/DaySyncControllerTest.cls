/**
 * Tests for DaySyncController + DaySyncSessionResult — the "Sync" list-view
 * button on Attendance_Log__c.
 *
 * Validation branches (null / future / too-old) need no callout. The success
 * path fires BiometricAttendanceBatch, whose start() calls the ESSL SOAP
 * service, so those tests inject dummy credentials via configOverride and a
 * WebServiceMock. finish() intentionally skips the chained marking batch under
 * Test.isRunningTest(); the marking logic itself is covered by
 * AttendanceBackfillBatchTest.
 *
 * The RESULT phase reconstructs "before" values from Session_Enrollment__History,
 * and field history rows are NOT written inside Apex tests. Those tests therefore
 * inject the pre-run values through the @TestVisible `beforeOverride` seam and
 * assert the tally / roll-up logic against real Session_Enrollment__c rows.
 *
 * @TestSetup mirrors AttendanceBackfillBatchTest: the Roll_Number__c formula
 * source is ProgramCohortMember.Roll_Number__c, and a fresh past-dated Session
 * must be INSERTED (a validation rule blocks updating a completed session).
 */
@IsTest
private class DaySyncControllerTest {

    private static final String SESSION_NAME = 'DSC Past Session';

    /** Minimal SOAP mock so BiometricAttendanceBatch.start() returns cleanly. */
    private class DaySyncSoapMock implements WebServiceMock {
        /**
         * Returns one canned punch row instead of calling the ESSL service.
         * @param stub         the generated stub (unused)
         * @param request      the request element (unused)
         * @param response     the map the response element is written into
         * @param endpoint     the service endpoint (unused)
         * @param soapAction   the SOAP action (unused)
         * @param requestName  the request element name (unused)
         * @param responseNs   the response namespace (unused)
         * @param responseName the response element name (unused)
         * @param responseType the response type name (unused)
         */
        @SuppressWarnings('PMD.ExcessiveParameterList')
        public void doInvoke(
            Object stub, Object request, Map<String, Object> response,
            String endpoint, String soapAction, String requestName,
            String responseNs, String responseName, String responseType
        ) {
            tempuriOrgLive.GetTransactionsLogResponse_element resp =
                new tempuriOrgLive.GetTransactionsLogResponse_element();
            resp.strDataList = 'R001\t2026-01-01 10:00:00\n';
            response.put('response_x', resp);
        }
    }

    @TestSetup
    static void setupData() {
        SpjimrPortalTestDataFactory.buildAll('dsc');

        List<ProgramCohortMember>    pcms = [SELECT Id FROM ProgramCohortMember LIMIT 1];
        List<AcademicTermEnrollment> ates = [SELECT Id FROM AcademicTermEnrollment LIMIT 1];
        if (pcms.isEmpty() || ates.isEmpty()) {
            return;
        }

        SObject ate = ates[0];
        ate.put('Batch_Enrollment__c', pcms[0].Id);
        update ate;

        // DO NOT write ProgramCohortMember.Roll_Number__c here. devfeat carries a
        // validation rule ("Student Name and Roll Number cannot be edited after
        // record creation") that rejects it, which failed every test in this
        // class at @TestSetup. It is also unnecessary: the batch joins on
        // Registeration_Number__c, whose chain is fed by the Account below.

        // A completed session on a past day — inserted, not updated.
        Datetime startTime = Datetime.now().addDays(-3);
        Session__c sess = new Session__c(
            Name = SESSION_NAME, Schedule_Type__c = 'Published',
            Start_Time__c = startTime, End_Time__c = startTime.addHours(1));
        insert sess;

        insert new Session_Enrollment__c(
            Session__c = sess.Id, Academic_Term_Enrollment__c = ate.Id);
    }

    /**
     * The seeded enrollment on the past session.
     * @return the enrollment, or null when org wiring prevented setup
     */
    private static Session_Enrollment__c seededEnrollment() {
        List<Session_Enrollment__c> ses = [
            SELECT Id, Attendance__c, Session__c,
                   Session__r.Start_Time__c, Session__r.End_Time__c
            FROM   Session_Enrollment__c
            WHERE  Session__r.Name = :SESSION_NAME
            LIMIT  1
        ];
        return ses.isEmpty() ? null : ses[0];
    }

    /** Injects dummy credentials so the batch doesn't abort on missing config. */
    private static void seedConfig() {
        BiometricAttendanceBatch.configOverride = new Biometric_API_Config__mdt(
            Api_User__c = 'api', Api_Password__c = 'test-pass');
    }

    /**
     * The running user, for the per-method System.runAs wrapper.
     * @return a User reference to the current user
     */
    private static User self() {
        return new User(Id = UserInfo.getUserId());
    }

    @IsTest
    static void gettersReturnIsoDateStrings() {
        System.runAs(self()) {
            Test.startTest();
            DaySyncController ctrl = new DaySyncController();
            String minStr = ctrl.getMinDateStr();
            String maxStr = ctrl.getMaxDateStr();
            Test.stopTest();

            System.assertEquals(10, minStr.length(), 'min should be a yyyy-MM-dd string');
            System.assertEquals(10, maxStr.length(), 'max should be a yyyy-MM-dd string');
            System.assert(maxStr > minStr, 'max (yesterday) should be after min (90 days ago)');
            System.assertEquals(true, ctrl.getIsForm(), 'a fresh controller starts on the form');
            System.assertEquals(false, ctrl.getIsRunning(), 'nothing is running yet');
            System.assertEquals(false, ctrl.getIsResult(), 'there are no results yet');
        }
    }

    @IsTest
    static void submitNullDateRejected() {
        System.runAs(self()) {
            Test.startTest();
            DaySyncController ctrl = new DaySyncController();
            ctrl.selectedDate = null;
            ctrl.submit();
            Test.stopTest();

            System.assertEquals(false, ctrl.isSuccess, 'null date must be rejected');
            System.assertEquals(true, ctrl.getIsForm(), 'a rejected date keeps the form open');
            System.assert(ctrl.resultMessage.contains('select a date'),
                'should ask the user to select a date');
        }
    }

    @IsTest
    static void submitFutureDateRejected() {
        System.runAs(self()) {
            Test.startTest();
            DaySyncController ctrl = new DaySyncController();
            ctrl.selectedDate = Date.today().addDays(1);
            ctrl.submit();
            Test.stopTest();

            System.assertEquals(false, ctrl.isSuccess, 'future date must be rejected');
            System.assert(ctrl.resultMessage.containsIgnoreCase('at least 2 days old'),
                'a future date should hit the 2-day-minimum rule: ' + ctrl.resultMessage);
        }
    }

    /** Yesterday is now blocked too — only dates 2+ days old are syncable. */
    @IsTest
    static void submitYesterdayRejected() {
        System.runAs(self()) {
            Test.startTest();
            DaySyncController ctrl = new DaySyncController();
            ctrl.selectedDate = Date.today().addDays(-1);
            ctrl.submit();
            Test.stopTest();

            System.assertEquals(false, ctrl.isSuccess, 'yesterday must be rejected');
            System.assert(ctrl.resultMessage.containsIgnoreCase('at least 2 days old'),
                'should explain the 2-day minimum: ' + ctrl.resultMessage);
        }
    }

    /** The boundary: exactly 2 days old is the newest date accepted. */
    @IsTest
    static void submitTwoDaysOldIsTheBoundary() {
        System.runAs(self()) {
            Test.startTest();
            DaySyncController ctrl = new DaySyncController();
            String maxStr = ctrl.getMaxDateStr();
            Test.stopTest();

            System.assertEquals(String.valueOf(Date.today().addDays(-2)), maxStr,
                'the date input max must be today minus 2 days');
        }
    }

    @IsTest
    static void submitTooOldDateRejected() {
        System.runAs(self()) {
            Test.startTest();
            DaySyncController ctrl = new DaySyncController();
            ctrl.selectedDate = Date.today().addDays(-200);
            ctrl.submit();
            Test.stopTest();

            System.assertEquals(false, ctrl.isSuccess,
                'date older than 90 days must be rejected');
            System.assert(ctrl.resultMessage.contains('too far back'),
                'should say the date is too far back');
        }
    }

    @IsTest
    static void submitValidPastDateStartsJobAndEntersRunning() {
        System.runAs(self()) {
            seedConfig();
            Test.setMock(WebServiceMock.class, new DaySyncSoapMock());

            Test.startTest();
            DaySyncController ctrl = new DaySyncController();
            ctrl.selectedDate = Date.today().addDays(-5);
            ctrl.submit();
            Boolean runningWhileQueued = ctrl.getIsRunning();
            ctrl.refreshStatus();   // job still Queued inside startTest/stopTest
            String queuedDetail = ctrl.statusDetail;
            Test.stopTest();

            System.assertEquals(true, ctrl.isSuccess, ctrl.resultMessage);
            System.assertEquals(true, runningWhileQueued,
                'a successful submit should move the page into its RUNNING phase');
            System.assertNotEquals(null, ctrl.fetchJobId,
                'the fetch job id should be retained');
            System.assert(ctrl.resultMessage.contains('Job Id'),
                'success message should include the job id');
            System.assert(queuedDetail.containsIgnoreCase('punches'),
                'a queued fetch job should report reading punches: ' + queuedDetail);

            // Two-step tracker: step 1 running, step 2 not started yet.
            System.assertEquals('active', ctrl.step1State, 'step 1 should be in progress');
            System.assertEquals('pending', ctrl.step2State, 'step 2 should not have started');
            System.assertEquals(35, ctrl.progressPercent,
                'a fetch still in flight should sit at 35%');
        }
    }

    /** A brand-new controller shows both steps idle and the bar at zero. */
    @IsTest
    static void progressStartsIdleAtZero() {
        System.runAs(self()) {
            Test.startTest();
            DaySyncController ctrl = new DaySyncController();
            Test.stopTest();

            System.assertEquals('pending', ctrl.step1State, 'step 1 starts pending');
            System.assertEquals('pending', ctrl.step2State, 'step 2 starts pending');
            System.assertEquals(0, ctrl.progressPercent, 'the bar starts empty');
        }
    }

    /** refreshStatus() is a no-op unless the page is mid-run. */
    @IsTest
    static void refreshStatusNotRunningIsNoOp() {
        System.runAs(self()) {
            Test.startTest();
            DaySyncController ctrl = new DaySyncController();
            ctrl.refreshStatus();
            Test.stopTest();

            System.assertEquals(true, ctrl.getIsForm(),
                'polling on the form must not change phase');
            System.assertEquals(null, ctrl.statusDetail, 'no status should be produced');
        }
    }

    /**
     * Once the fetch job reports Completed, the poller must START step 2 itself
     * (AttendanceBackfillBatch) and record that job's real Id — the controller
     * no longer hunts for a batch chained from BiometricAttendanceBatch.finish().
     */
    @IsTest
    static void refreshStatusStartsMarkingBatchItself() {
        System.runAs(self()) {
            seedConfig();
            Test.setMock(WebServiceMock.class, new DaySyncSoapMock());

            DaySyncController ctrl = new DaySyncController();
            ctrl.selectedDate = Date.today().addDays(-5);

            Test.startTest();
            ctrl.submit();
            Test.stopTest();               // fetch batch runs to Completed here

            System.assertEquals(null, ctrl.markJobId,
                'the marking job should not exist before the fetch completes');

            ctrl.refreshStatus();          // sees Completed -> launches step 2

            System.assertNotEquals(null, ctrl.markJobId,
                'the poller should have started AttendanceBackfillBatch and kept its Id');
            System.assertEquals(true, ctrl.getIsRunning(),
                'the page keeps polling while step 2 runs');
            System.assertEquals('complete', ctrl.step1State,
                'the fetch step should be ticked off');
            System.assertEquals('active', ctrl.step2State,
                'the marking step should now be the active one');
            System.assertEquals(50, ctrl.progressPercent,
                'step 1 of 2 done should read 50%');
        }
    }

    /** A fetch job that failed must stop the run and never start step 2. */
    @IsTest
    static void refreshStatusFetchFailedStopsBeforeMarking() {
        System.runAs(self()) {
            DaySyncController ctrl = new DaySyncController();
            ctrl.phase    = 'RUNNING';
            ctrl.runStart = Datetime.now().addMinutes(-5);
            ctrl.dayStart = Datetime.now().addDays(-2);
            ctrl.dayEnd   = Datetime.now().addDays(-1);
            // Point at a job id that does not resolve to a completed fetch job.
            ctrl.fetchJobId = null;

            Test.startTest();
            ctrl.refreshStatus();
            Test.stopTest();

            System.assertEquals(null, ctrl.markJobId,
                'no marking batch may start when there is no completed fetch job');
            System.assertEquals(true, ctrl.getIsRunning(),
                'a missing fetch job leaves the page in its running phase');
        }
    }

    /**
     * The tally itself: an enrollment that this run flipped from unmarked to
     * Present must show Before = Not Marked and After = Present, with the
     * session's time range and roll-up totals populated.
     */
    @IsTest
    static void buildResultsTalliesBeforeAndAfter() {
        System.runAs(self()) {
            Session_Enrollment__c se = seededEnrollment();
            System.assertNotEquals(null, se,
                'Test setup failed: no Session_Enrollment__c created.');

            se.Attendance__c = 'Present';
            update se;

            DaySyncController ctrl = new DaySyncController();
            ctrl.runStart = Datetime.now().addHours(-1);
            ctrl.dayStart = se.Session__r.Start_Time__c.addHours(-2);
            ctrl.dayEnd   = se.Session__r.Start_Time__c.addHours(2);
            // Stand in for the field-history row this run would have written.
            DaySyncResultBuilder.beforeOverride = new Map<Id, String>{ se.Id => null };

            Test.startTest();
            ctrl.buildResults();
            Test.stopTest();

            System.assertEquals(1, ctrl.sessionResults.size(),
                'the one affected session should be reported');
            DaySyncSessionResult row = ctrl.sessionResults[0];

            System.assertEquals(SESSION_NAME, row.sessionName,
                'the session name should carry through');
            System.assertEquals(1, row.total, 'the session has one enrollment');
            System.assertEquals(0, row.beforePresent, 'it was not Present before');
            System.assertEquals(1, row.beforeNotMarked,
                'a null OldValue counts as Not Marked');
            System.assertEquals(1, row.afterPresent, 'it is Present after');
            System.assertEquals(0, row.afterNotMarked, 'nothing is left unmarked');
            System.assertEquals(1, row.changed, 'one enrollment changed');
            System.assertEquals(1, row.newPresent, 'one was newly marked Present');
            System.assertEquals(0, row.newAbsent, 'none were marked Absent');
            System.assertEquals('+1', row.getPresentDelta(), 'net Present should read +1');
            System.assertEquals(false, row.getIsUnchanged(), 'the row did change');
            System.assert(row.getTimeRange().contains('–'),
                'the time range should show start – end: ' + row.getTimeRange());
            System.assertEquals(11, row.getDateStr().length(),
                'the date should render as "dd MMM yyyy": ' + row.getDateStr());

            System.assertEquals(1, ctrl.totalSessions, 'one session in the roll-up');
            System.assertEquals(1, ctrl.totalStudents, 'one student in the roll-up');
            System.assertEquals(1, ctrl.totalChanged, 'one record updated in the roll-up');
            System.assertEquals(1, ctrl.totalNewPresent, 'one marked Present in the roll-up');
            System.assertEquals(0, ctrl.totalNewAbsent, 'none marked Absent in the roll-up');
        }
    }

    /** A session outside the synced day must be filtered out of the report. */
    @IsTest
    static void buildResultsExcludesSessionsOffTheSyncedDay() {
        System.runAs(self()) {
            Session_Enrollment__c se = seededEnrollment();
            System.assertNotEquals(null, se,
                'Test setup failed: no Session_Enrollment__c created.');

            se.Attendance__c = 'Present';
            update se;

            DaySyncController ctrl = new DaySyncController();
            ctrl.runStart = Datetime.now().addHours(-1);
            // A window that does NOT contain the session.
            ctrl.dayStart = se.Session__r.Start_Time__c.addDays(-10);
            ctrl.dayEnd   = se.Session__r.Start_Time__c.addDays(-9);
            DaySyncResultBuilder.beforeOverride = new Map<Id, String>{ se.Id => 'Absent' };

            Test.startTest();
            ctrl.buildResults();
            Test.stopTest();

            System.assertEquals(0, ctrl.sessionResults.size(),
                'a session outside the synced day must not be reported');
            System.assertEquals(0, ctrl.totalSessions, 'nothing rolls up');
        }
    }

    /** No history rows for the run → an empty, non-null results list. */
    @IsTest
    static void buildResultsNoChangesReturnsEmpty() {
        System.runAs(self()) {
            DaySyncController ctrl = new DaySyncController();
            ctrl.runStart = Datetime.now().addHours(-1);
            ctrl.dayStart = Datetime.now().addDays(-2);
            ctrl.dayEnd   = Datetime.now().addDays(-1);
            DaySyncResultBuilder.beforeOverride = new Map<Id, String>();

            Test.startTest();
            ctrl.buildResults();
            Test.stopTest();

            System.assertEquals(0, ctrl.sessionResults.size(), 'no changes → no rows');
            System.assertEquals(0, ctrl.totalSessions, 'no sessions in the roll-up');
        }
    }

    /**
     * With no override, the builder runs its real Session_Enrollment__History
     * query. Apex tests never write history rows, so this must come back empty
     * rather than throwing — it exercises the production read path.
     */
    @IsTest
    static void buildResultsReadsFieldHistoryWhenNotOverridden() {
        System.runAs(self()) {
            DaySyncResultBuilder builder = new DaySyncResultBuilder(
                Datetime.now().addHours(-1),
                Datetime.now().addDays(-2),
                Datetime.now().addDays(-1));

            Test.startTest();
            builder.build();
            Test.stopTest();

            System.assertEquals(0, builder.rows.size(),
                'no field history in a test context → no rows');
            System.assertEquals(0, builder.totalSessions, 'nothing to roll up');
            System.assertEquals(0, builder.logsFetched,
                'no punch logs were imported by this pseudo-run');
        }
    }

    /** Sanity-check the wrapper's own branches without touching the database. */
    @IsTest
    static void sessionResultCountsEveryPicklistValue() {
        System.runAs(self()) {
            Datetime startTime = Datetime.newInstance(2026, 7, 27, 9, 25, 0);
            Session__c sess = new Session__c(
                Name = 'Wrapper Session', Start_Time__c = startTime,
                End_Time__c = startTime.addMinutes(60));

            Test.startTest();
            DaySyncSessionResult row = new DaySyncSessionResult(null, sess);
            row.add('Absent', 'Present');        // flipped to Present
            row.add('Not Marked', 'Absent');     // newly Absent
            row.add('Present', 'Present');       // untouched
            row.add('Late', 'Late');             // untouched, counted as Other
            row.add('Sanctioned Leave', 'Sanctioned Leave');
            row.add('Not Marked', 'Not Marked'); // still unmarked
            Test.stopTest();

            System.assertEquals(6, row.total, 'six students folded in');
            System.assertEquals(1, row.beforePresent, 'one was already Present');
            System.assertEquals(1, row.beforeAbsent, 'one was Absent');
            System.assertEquals(2, row.beforeNotMarked, 'two were unmarked');
            System.assertEquals(2, row.beforeOther, 'Late + Sanctioned Leave count as Other');
            System.assertEquals(2, row.afterPresent, 'two are Present after');
            System.assertEquals(1, row.afterAbsent, 'one is Absent after');
            System.assertEquals(1, row.afterNotMarked, 'one is still unmarked');
            System.assertEquals(2, row.afterOther, 'Other is untouched by the sync');
            System.assertEquals(2, row.changed, 'two enrollments changed');
            System.assertEquals(1, row.newPresent, 'one newly Present');
            System.assertEquals(1, row.newAbsent, 'one newly Absent');
            System.assertEquals('+1', row.getPresentDelta(), 'net Present is +1');
        }
    }

    /** A null session and a missing end time must not break the row. */
    @IsTest
    static void sessionResultNullSessionRendersSafely() {
        System.runAs(self()) {
            Test.startTest();
            DaySyncSessionResult nullRow = new DaySyncSessionResult(null, null);
            DaySyncSessionResult noEndRow = new DaySyncSessionResult(
                null, new Session__c(Name = 'No End', Start_Time__c = Datetime.now()));
            Test.stopTest();

            System.assertEquals('(unnamed session)', nullRow.sessionName,
                'a null session should fall back to a placeholder name');
            System.assertEquals('—', nullRow.getTimeRange(), 'no start time → an em dash');
            System.assertEquals('', nullRow.getDateStr(), 'no start time → a blank date');
            System.assertEquals(true, nullRow.getIsUnchanged(), 'an empty row is unchanged');
            System.assertEquals('0', nullRow.getPresentDelta(), 'an empty row has no delta');
            System.assert(noEndRow.getTimeRange().endsWith('?'),
                'a missing end time should render as "?": ' + noEndRow.getTimeRange());
        }
    }

    /** Rows sort by session start time, with null start times pushed last. */
    @IsTest
    static void sessionResultSortsByStartTime() {
        System.runAs(self()) {
            Datetime baseTime = Datetime.newInstance(2026, 7, 27, 9, 0, 0);

            Test.startTest();
            List<DaySyncSessionResult> rows = new List<DaySyncSessionResult>{
                new DaySyncSessionResult(null,
                    new Session__c(Name = 'Late',  Start_Time__c = baseTime.addHours(3))),
                new DaySyncSessionResult(null, null),
                new DaySyncSessionResult(null,
                    new Session__c(Name = 'Early', Start_Time__c = baseTime)),
                new DaySyncSessionResult(null,
                    new Session__c(Name = 'Same',  Start_Time__c = baseTime))
            };
            rows.sort();
            Test.stopTest();

            System.assertEquals(4, rows.size(), 'sorting keeps every row');
            System.assertEquals(baseTime, rows[0].startTime,
                'the earliest session comes first');
            System.assertEquals(baseTime.addHours(3), rows[2].startTime,
                'the later session follows the two equal ones');
            System.assertEquals(null, rows[3].startTime, 'a null start time sorts last');
        }
    }

    /** syncAnotherDay() clears every trace of the previous run. */
    @IsTest
    static void syncAnotherDayResetsToForm() {
        System.runAs(self()) {
            Test.startTest();
            DaySyncController ctrl = new DaySyncController();
            ctrl.phase        = 'RESULT';
            ctrl.selectedDate = Date.today().addDays(-4);
            ctrl.runStart     = Datetime.now();
            ctrl.syncAnotherDay();
            Test.stopTest();

            System.assertEquals(true, ctrl.getIsForm(), 'the page should return to the form');
            System.assertEquals(null, ctrl.selectedDate, 'the previous date should be cleared');
            System.assertEquals(null, ctrl.resultMessage,
                'the previous message should be cleared');
            System.assertEquals(null, ctrl.fetchJobId, 'the previous job id should be cleared');
            System.assertEquals(false, ctrl.hasWarning,
                'the previous warning should be cleared');
        }
    }

    /** A sync already in flight is refused rather than stacked. */
    @IsTest
    static void submitWhileJobRunningIsBlocked() {
        System.runAs(self()) {
            seedConfig();
            Test.setMock(WebServiceMock.class, new DaySyncSoapMock());

            Test.startTest();
            // The first submit enqueues a batch that stays Queued until stopTest().
            DaySyncController first = new DaySyncController();
            first.selectedDate = Date.today().addDays(-5);
            first.submit();

            DaySyncController second = new DaySyncController();
            second.selectedDate = Date.today().addDays(-6);
            second.submit();
            Test.stopTest();

            System.assertEquals(true, first.isSuccess, 'the first sync should start');
            System.assertEquals(false, second.isSuccess,
                'a second sync must be refused while one is queued');
            System.assert(second.resultMessage.containsIgnoreCase('already running'),
                'the refusal should say a sync is already running: ' + second.resultMessage);
        }
    }
}
/**
 * @class   DaySyncController
 * @purpose Controller for the DaySync Visualforce page, which backs the "Sync"
 *          list-view button on Attendance_Log__c.
 *
 *          The page runs in three phases, all served by this one controller:
 *
 *            FORM    → the user picks a single PAST date (within the last
 *                      MAX_LOOKBACK_DAYS) and clicks Submit. This fires
 *                      BiometricAttendanceBatch for that whole IST day, pulling
 *                      the day's punches from ESSL into Attendance_Log__c.
 *
 *            RUNNING → an apex:actionPoller calls refreshStatus() every few
 *                      seconds. It follows the fetch job and, once that is
 *                      Completed, STARTS the day-scoped AttendanceBackfillBatch
 *                      itself and follows that too.
 *
 *                      This controller owns the 2-step orchestration on purpose.
 *                      BiometricAttendanceBatch used to chain the marking batch
 *                      from its own finish() via a `chainMarking` flag; that flag
 *                      was removed from the batch on 2026-07-29, and driving both
 *                      steps from the poller is the better arrangement anyway:
 *                        - BiometricAttendanceBatch stays generic, with no
 *                          knowledge of this button
 *                        - we learn the marking job's REAL Id instead of guessing
 *                          it by class name + timestamp (a chained batch carries
 *                          no ParentJobId), so no grace-window heuristic is needed
 *                        - every punch is already committed by the time the fetch
 *                          job reports Completed, so starting step 2 here is at
 *                          least as safe as chaining from finish()
 *
 *            RESULT  → once both jobs are done, DaySyncResultBuilder reports every
 *                      session touched on that day with its BEFORE and AFTER
 *                      Present / Absent / Not-Marked headcounts. The page stays
 *                      open until the user clicks Close — it never auto-closes.
 *
 *          Server-side validation is authoritative: the date must be non-null,
 *          strictly in the past (IST), and no older than MAX_LOOKBACK_DAYS.
 *
 * @see     DaySyncJobTracker    — async-job lookups for the polling loop
 * @see     DaySyncResultBuilder — before/after tally from Attendance field history
 * @see     DaySyncSessionResult — one table row
 */
public with sharing class DaySyncController {

    private static final String  IST_TZ            = 'Asia/Kolkata';
    private static final Integer IST_OFFSET_MIN    = 330; // IST = UTC + 5:30
    private static final Integer MAX_LOOKBACK_DAYS = 90;

    // The newest selectable date is today MINUS this many days. 2 means today and
    // yesterday are both blocked, so the earliest a user can sync is the day
    // before yesterday — by then the 23:39 final sweep has already re-pulled that
    // day from the device, so the punches are settled.
    // private static final Integer MIN_AGE_DAYS = 1; // old: yesterday was allowed
    private static final Integer MIN_AGE_DAYS = 2;
    private static final Integer BATCH_SCOPE       = 200;

    /** Clock-skew cushion when scoping history rows to this run. */
    private static final Integer RUN_START_BUFFER_SEC = 2;

    private static final String PHASE_FORM    = 'FORM';
    private static final String PHASE_RUNNING = 'RUNNING';
    private static final String PHASE_RESULT  = 'RESULT';

    // Step states for the RUNNING panel's two-step tracker. These double as CSS
    // class suffixes on the page (ds-pending / ds-active / ds-complete / ds-error).
    private static final String STEP_PENDING  = 'pending';
    private static final String STEP_ACTIVE   = 'active';
    private static final String STEP_COMPLETE = 'complete';
    private static final String STEP_ERROR    = 'error';

    // ── Form state ────────────────────────────────────────────────────────────

    /** Bound to the date input on the page. */
    public Date selectedDate { get; set; }

    /** Validation error on the form, or the "sync started" note. */
    public String resultMessage { get; private set; }

    /** True once a sync has been successfully enqueued. */
    public Boolean isSuccess { get; private set; }

    // ── Run state (retained in view state across poller callbacks) ────────────
    @TestVisible private String   phase;
    @TestVisible private Id       fetchJobId;
    @TestVisible private Id       markJobId;
    @TestVisible private Datetime runStart;
    @TestVisible private Datetime dayStart;
    @TestVisible private Datetime dayEnd;

    /** "What is happening right now" headline for the RUNNING panel. */
    public String statusDetail { get; private set; }

    // ── Two-step progress tracker (RUNNING panel) ─────────────────────────────

    /** Step 1 (fetch) state: pending | active | complete | error. */
    public String step1State { get; private set; }

    /** Short status line under step 1. */
    public String step1Detail { get; private set; }

    /** Step 2 (mark) state: pending | active | complete | error. */
    public String step2State { get; private set; }

    /** Short status line under step 2. */
    public String step2Detail { get; private set; }

    /** Overall completion of the two-step sync, 0-100, for the progress bar. */
    public Integer progressPercent { get; private set; }

    /** The synced day, formatted for display. */
    public String syncedDateStr { get; private set; }

    /** True when the run finished but something went wrong. */
    public Boolean hasWarning { get; private set; }

    /** The warning to show above the results table. */
    public String warningText { get; private set; }

    // ── Result state ──────────────────────────────────────────────────────────

    /** One row per session whose attendance this run touched. */
    public List<DaySyncSessionResult> sessionResults { get; private set; }

    /** Punch logs imported by this run. */
    public Integer logsFetched { get; private set; }

    /** Number of sessions in the report. */
    public Integer totalSessions { get; private set; }

    /** Enrollments across all reported sessions. */
    public Integer totalStudents { get; private set; }

    /** Enrollments whose attendance this run changed. */
    public Integer totalChanged { get; private set; }

    /** Enrollments this run moved to Present. */
    public Integer totalNewPresent { get; private set; }

    /** Enrollments this run moved to Absent. */
    public Integer totalNewAbsent { get; private set; }

    /** Starts the page on its date-picker phase with empty counters. */
    public DaySyncController() {
        this.isSuccess       = false;
        this.hasWarning      = false;
        this.phase           = PHASE_FORM;
        this.sessionResults  = new List<DaySyncSessionResult>();
        this.logsFetched     = 0;
        this.totalSessions   = 0;
        this.totalStudents   = 0;
        this.totalChanged    = 0;
        this.totalNewPresent = 0;
        this.totalNewAbsent  = 0;

        this.step1State      = STEP_PENDING;
        this.step2State      = STEP_PENDING;
        this.progressPercent = 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PHASE FLAGS — drive the rendered= attributes on the page
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Whether the date-picker form should be shown.
     * @return true while no sync has been started
     */
    public Boolean getIsForm() {
        return PHASE_FORM.equals(phase);
    }

    /**
     * Whether the in-progress panel (spinner + poller) should be shown.
     * @return true while either batch is still running
     */
    public Boolean getIsRunning() {
        return PHASE_RUNNING.equals(phase);
    }

    /**
     * Whether the before/after results table should be shown.
     * @return true once both batches have finished
     */
    public Boolean getIsResult() {
        return PHASE_RESULT.equals(phase);
    }

    /**
     * Whether this run changed nothing at all.
     * @return true when the results table has no rows
     */
    public Boolean getIsEmptyResult() {
        return getIsResult() && sessionResults.isEmpty();
    }

    /**
     * Earliest selectable date (yyyy-MM-dd), for the input's `min` attribute.
     * @return MAX_LOOKBACK_DAYS before today (IST)
     */
    public String getMinDateStr() {
        return String.valueOf(todayIst().addDays(-MAX_LOOKBACK_DAYS));
    }

    /**
     * Latest selectable date (yyyy-MM-dd), for the input's `max` attribute.
     * @return today (IST) minus MIN_AGE_DAYS — today and yesterday are blocked
     */
    public String getMaxDateStr() {
        return String.valueOf(todayIst().addDays(-MIN_AGE_DAYS));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ACTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Page action for the Submit button. Validates the date, then fires the
     * fetch-and-mark batch for that whole IST day and moves the page into its
     * RUNNING phase.
     * @return null (the page re-renders in place)
     */
    public PageReference submit() {
        try {
            validate(selectedDate);
            if (DaySyncJobTracker.isAnySyncRunning()) {
                throw new SyncException(
                    'A sync is already running. Please wait for it to finish.');
            }

            this.dayStart      = istMidnightAsUtc(selectedDate);
            this.dayEnd        = istMidnightAsUtc(selectedDate.addDays(1));
            this.syncedDateStr = selectedDate.format();
            this.runStart      = Datetime.now().addSeconds(-RUN_START_BUFFER_SEC);

            // 2-arg ctor: step 2 is started by refreshStatus(), NOT chained from
            // the batch's finish(). Do not reintroduce a chainMarking argument.
            this.fetchJobId = Database.executeBatch(
                new BiometricAttendanceBatch(dayStart, dayEnd), BATCH_SCOPE);

            this.isSuccess     = true;
            this.phase         = PHASE_RUNNING;
            this.resultMessage = 'Sync started for ' + syncedDateStr
                + '. (Job Id: ' + fetchJobId + ')';
            setProgress(STEP_ACTIVE,  'Contacting the biometric device…',
                        STEP_PENDING, 'Waiting for step 1', 25);
        } catch (SyncException se) {
            this.isSuccess     = false;
            this.resultMessage = se.getMessage();
        } catch (Exception e) {
            this.isSuccess     = false;
            this.resultMessage = 'Could not start Sync: ' + e.getMessage();
        }
        return null;
    }

    /**
     * Poller / "Refresh now" action. Advances the page from RUNNING to RESULT
     * once the fetch batch and its chained marking batch are both finished.
     * @return null (the page re-renders in place)
     */
    public PageReference refreshStatus() {
        if (!getIsRunning() || fetchJobId == null) {
            return null;
        }

        AsyncApexJob fetchJob = DaySyncJobTracker.load(fetchJobId);
        if (!DaySyncJobTracker.isDone(fetchJob)) {
            setProgress(STEP_ACTIVE,  'Reading punches for ' + syncedDateStr + '…',
                        STEP_PENDING, 'Waiting for step 1', 35);
            return null;
        }
        if (!DaySyncJobTracker.isCompleted(fetchJob)) {
            setProgress(STEP_ERROR,   'Could not read the device',
                        STEP_PENDING, 'Not started', 100);
            finishWithWarning('The biometric fetch job ' + fetchJob.Status.toLowerCase()
                + '. No attendance was marked. ' + String.valueOf(fetchJob.ExtendedStatus));
            return null;
        }

        trackMarkingJob();
        return null;
    }

    /**
     * Resets the page back to the date picker so another day can be synced.
     * @return null (the page re-renders in place)
     */
    public PageReference syncAnotherDay() {
        this.phase          = PHASE_FORM;
        this.isSuccess      = false;
        this.hasWarning     = false;
        this.warningText    = null;
        this.resultMessage  = null;
        this.statusDetail   = null;
        this.fetchJobId     = null;
        this.markJobId      = null;
        this.runStart       = null;
        this.selectedDate   = null;
        this.sessionResults = new List<DaySyncSessionResult>();
        setProgress(STEP_PENDING, null, STEP_PENDING, null, 0);
        this.statusDetail   = null;
        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RUNNING → RESULT transition
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Step 2. Starts the day-scoped AttendanceBackfillBatch the first time the
     * fetch job is seen Completed, then follows it on subsequent polls. Every
     * punch is committed by then, so launching the marking batch here is at
     * least as safe as the old chain-from-finish() arrangement.
     */
    private void trackMarkingJob() {
        if (markJobId == null) {
            this.markJobId = Database.executeBatch(
                new AttendanceBackfillBatch(dayStart, dayEnd), BATCH_SCOPE);
            setProgress(STEP_COMPLETE, 'Punches imported',
                        STEP_ACTIVE,   'Marking Present / Absent…', 50);
            return;
        }

        AsyncApexJob markJob = DaySyncJobTracker.load(markJobId);
        if (!DaySyncJobTracker.isDone(markJob)) {
            setProgress(STEP_COMPLETE, 'Punches imported',
                        STEP_ACTIVE,   'Comparing punches to session times…', 75);
            return;
        }

        buildResults();
        this.phase = PHASE_RESULT;
        if (DaySyncJobTracker.isCompleted(markJob)) {
            setProgress(STEP_COMPLETE, 'Punches imported',
                        STEP_COMPLETE, 'Attendance marked', 100);
        } else {
            setProgress(STEP_COMPLETE, 'Punches imported',
                        STEP_ERROR,    'Marking did not finish', 100);
            this.hasWarning  = true;
            this.warningText = 'The marking job ' + markJob.Status.toLowerCase()
                + ' — the results below may be incomplete. '
                + String.valueOf(markJob.ExtendedStatus);
        }
    }

    /**
     * Sets the two-step tracker and progress bar shown on the RUNNING panel.
     * The headline (statusDetail) follows whichever step is currently active.
     * @param s1State  step 1 state: pending | active | complete | error
     * @param s1Detail short status line under step 1
     * @param s2State  step 2 state: pending | active | complete | error
     * @param s2Detail short status line under step 2
     * @param percent  overall completion, 0-100
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private void setProgress(String s1State, String s1Detail,
                             String s2State, String s2Detail, Integer percent) {
        this.step1State      = s1State;
        this.step1Detail     = s1Detail;
        this.step2State      = s2State;
        this.step2Detail     = s2Detail;
        this.progressPercent = percent;
        this.statusDetail    = STEP_ACTIVE.equals(s1State) ? s1Detail : s2Detail;
    }

    /**
     * Ends the run early and shows the (possibly empty) results with a warning.
     * @param message the warning to display above the table
     */
    private void finishWithWarning(String message) {
        buildResults();
        this.phase       = PHASE_RESULT;
        this.hasWarning  = true;
        this.warningText = message;
    }

    /** Delegates the before/after tally and copies its output onto the page. */
    @TestVisible
    private void buildResults() {
        DaySyncResultBuilder builder =
            new DaySyncResultBuilder(runStart, dayStart, dayEnd);
        builder.build();

        this.sessionResults  = builder.rows;
        this.logsFetched     = builder.logsFetched;
        this.totalSessions   = builder.totalSessions;
        this.totalStudents   = builder.totalStudents;
        this.totalChanged    = builder.totalChanged;
        this.totalNewPresent = builder.totalNewPresent;
        this.totalNewAbsent  = builder.totalNewAbsent;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Rejects a null, today/future, or too-old date.
     * @param d the user-selected date (IST calendar date)
     */
    private void validate(Date d) {
        if (d == null) {
            throw new SyncException('Please select a date.');
        }
        Date today = todayIst();
        if (d > today.addDays(-MIN_AGE_DAYS)) {
            throw new SyncException(
                'Please select a date at least ' + MIN_AGE_DAYS + ' days old. '
                + 'Today, yesterday and future dates are not allowed — that day\'s '
                + 'punches may not have been fully pulled from the device yet.');
        }
        if (d < today.addDays(-MAX_LOOKBACK_DAYS)) {
            throw new SyncException(
                'Date is too far back. Please pick a date within the last '
                + MAX_LOOKBACK_DAYS + ' days.');
        }
    }

    /**
     * Today's calendar date in IST.
     * @return the IST calendar date
     */
    private static Date todayIst() {
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', IST_TZ));
    }

    /**
     * The UTC instant of 00:00 IST on the given date, matching how
     * BiometricAttendanceScheduler constructs its windows.
     * @param  d IST calendar date
     * @return the equivalent UTC Datetime
     */
    private static Datetime istMidnightAsUtc(Date d) {
        return Datetime.newInstanceGmt(d.year(), d.month(), d.day(), 0, 0, 0)
                       .addMinutes(-IST_OFFSET_MIN);
    }

    /** Thrown for user-facing validation / guard failures. */
    public class SyncException extends Exception {}
}
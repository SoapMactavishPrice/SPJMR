/**
 * @class   BiometricAttendanceBatch
 * @purpose Fetches raw biometric punch-in logs from the device API for a
 *          fixed 2-hour window and stores them as Attendance_Log__c records
 *          with Status__c = 'Pending'.
 *
 * @schedule Every 2 hours (8AM → 8PM) + 23:39 final sweep, all 7 days (Mon–Sun).
 *           Window is ANCHORED by the scheduler — immune to early/late execution.
 *
 * @design  Callouts run once in start() (one per active device); the parsed
 *          records are RETURNED from start() so the batch framework chunks the
 *          inserts in execute() (scope set by the scheduler). This keeps each
 *          insert within DML row limits and keeps heap low.
 *
 * @creds   API username/password come from the protected Custom Metadata record
 *          Biometric_API_Config__mdt 'Default' — never hard-coded here.
 *
 * @note    Deduplication is intentionally NOT done here.
 *          Batch 2 (AttendanceMarkingBatch) handles it at the session level.
 */
public class BiometricAttendanceBatch implements Database.Batchable<SObject>,
                                                  Database.AllowsCallouts,
                                                  Database.Stateful {

    // ── Credentials (from protected CMDT, never hard-coded) ───────────────────
    // Device serial numbers live in Biometric_Device__mdt (one record per device).
    // The API user/password live in Biometric_API_Config__mdt 'Default'.
    private static final String CONFIG_NAME = 'Default';

    /** Test-only override so tests can supply credentials without an org record. */
    @TestVisible
    private static Biometric_API_Config__mdt configOverride;

    @TestVisible
    private static Biometric_API_Config__mdt apiConfig() {
        if (configOverride != null) {
            return configOverride;
        }
        return Biometric_API_Config__mdt.getInstance(CONFIG_NAME);
    }

    // Raised around the batch's DML so AttendanceLogTrigger can apply its
    // IST timezone correction only for biometric inserts. UI inserts leave
    // this false and the trigger skips the time shift.
    @TestVisible
    public static Boolean isBiometricInsert = false;

    // ── Anchored Time Window (injected by scheduler, never Datetime.now()) ────
    private final Datetime windowStart;
    private final Datetime windowEnd;

    // When true, finish() chains a day-scoped AttendanceBackfillBatch over the
    // window just fetched, so a manual fetch is immediately followed by
    // Present/Absent marking. Used ONLY by the "Sync" button. Scheduled runs
    // leave this false — their marking is handled by AttendanceMarkingBatch.
    private final Boolean chainMarking;

    // ── Stateful Counters (accumulated across execute() chunks) ───────────────
    private Integer totalParsed  = 0;
    private Integer totalSuccess = 0;
    private Integer totalFailed  = 0;

    // ─────────────────────────────────────────────────────────────────────────
    // CONSTRUCTORS
    //
    //   BiometricAttendanceBatch(anchorTime)
    //       Daytime use. Window = [anchorTime - 2h  →  anchorTime].
    //
    //   BiometricAttendanceBatch(windowStart, windowEnd)
    //       Explicit-window use, e.g. the 23:39 IST final sweep that needs to
    //       cover everything from the last daytime sync (20:00 IST) to now —
    //       a span wider than 2 hours.
    // ─────────────────────────────────────────────────────────────────────────
    public BiometricAttendanceBatch(Datetime anchorTime) {
        this.windowEnd    = anchorTime;
        this.windowStart  = anchorTime.addHours(-2);
        this.chainMarking = false;
    }

    public BiometricAttendanceBatch(Datetime windowStart, Datetime windowEnd) {
        this.windowStart  = windowStart;
        this.windowEnd    = windowEnd;
        this.chainMarking = false;
    }

    //   BiometricAttendanceBatch(windowStart, windowEnd, chainMarking)
    //       "Sync" button use. Fetches the window, then (when chainMarking) runs
    //       a day-scoped AttendanceBackfillBatch over the SAME window to mark
    //       Present/Absent from the punches just inserted.
    public BiometricAttendanceBatch(Datetime windowStart, Datetime windowEnd, Boolean chainMarking) {
        this.windowStart  = windowStart;
        this.windowEnd    = windowEnd;
        this.chainMarking = chainMarking == true;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // START — Call API, parse response, RETURN records for chunked insert
    // ─────────────────────────────────────────────────────────────────────────
    public Iterable<SObject> start(Database.BatchableContext bc) {

        List<Attendance_Log__c> records = new List<Attendance_Log__c>();

        Biometric_API_Config__mdt cfg = apiConfig();
        if (cfg == null || String.isBlank(cfg.Api_User__c) || String.isBlank(cfg.Api_Password__c)) {
            System.debug(LoggingLevel.ERROR,
                'Batch1 | Biometric_API_Config__mdt "' + CONFIG_NAME
                + '" is missing API User/Password — aborting run (no records fetched).');
            return records; // empty → execute() never runs, finish() logs zeros
        }
        String apiUser = cfg.Api_User__c;
        String apiPass = cfg.Api_Password__c;

        String fromStr = windowStart.format('yyyy-MM-dd HH:mm:ss');
        String toStr   = windowEnd.format('yyyy-MM-dd HH:mm:ss');

        System.debug('========================================');
        System.debug('Batch1 | Window    : ' + fromStr + '  →  ' + toStr);
        System.debug('Batch1 | Actual Run: ' + Datetime.now());
        System.debug('========================================');

        List<Biometric_Device__mdt> devices = [
            SELECT MasterLabel, Serial_Number__c
            FROM Biometric_Device__mdt
            WHERE Is_Active__c = true
        ];
        System.debug('Batch1 | Querying ' + devices.size() + ' active device(s).');

        // One callout per device. Per-device try/catch so a single device
        // outage doesn't abort the whole run — the others still get fetched.
        for (Biometric_Device__mdt device : devices) {
            try {
                tempuriOrgLive.WebAPIServiceSoap svc = new tempuriOrgLive.WebAPIServiceSoap();
                tempuriOrgLive.GetTransactionsLogResponse_element res =
                    svc.GetTransactionsLog(fromStr, toStr, device.Serial_Number__c,
                                           apiUser, apiPass, '1');

                if (String.isNotBlank(res.strDataList)) {
                    List<Attendance_Log__c> parsed =
                        parseAndBuild(res.strDataList, device.Serial_Number__c);
                    records.addAll(parsed);
                    System.debug('Batch1 | ' + device.MasterLabel
                        + ' (' + device.Serial_Number__c + ') → ' + parsed.size() + ' records.');
                } else {
                    System.debug('Batch1 | ' + device.MasterLabel
                        + ' (' + device.Serial_Number__c + ') → no data for this window.');
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'Batch1 | ' + device.MasterLabel
                    + ' (' + device.Serial_Number__c + ') callout failed: ' + e.getMessage());
            }
        }

        totalParsed = records.size();
        System.debug('Batch1 | Total parsed across all devices: ' + totalParsed);

        // Returned to the framework, which chunks these into execute() calls.
        return records;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXECUTE — Insert one chunk (partial success: failures logged, not thrown)
    // ─────────────────────────────────────────────────────────────────────────
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        Database.SaveResult[] results;
        isBiometricInsert = true;
        try {
            results = Database.insert(scope, false);
        } finally {
            isBiometricInsert = false;
        }

        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                totalSuccess++;
            } else {
                totalFailed++;
                for (Database.Error err : sr.getErrors()) {
                    System.debug(LoggingLevel.WARN,
                        'Batch1 | Insert failed: ' + err.getStatusCode()
                        + ' — ' + err.getMessage());
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FINISH — Log summary
    // ─────────────────────────────────────────────────────────────────────────
    public void finish(Database.BatchableContext bc) {
        System.debug('========================================');
        System.debug('Batch1 | COMPLETE');
        System.debug('Window   : ' + windowStart + '  →  ' + windowEnd);
        System.debug('Parsed   : ' + totalParsed);
        System.debug('Inserted : ' + totalSuccess);
        System.debug('Failed   : ' + totalFailed);
        System.debug('========================================');

        // "Sync" button: mark Present/Absent for the day just fetched. Chained
        // here (not in the scheduler) so marking only runs after the punches are
        // committed. Guarded by !Test.isRunningTest() ONLY to avoid the platform
        // limit on chaining a second batch from a test context; the marking path
        // itself is covered directly by AttendanceBackfillBatchTest.
        if (chainMarking && !Test.isRunningTest()) {
            Database.executeBatch(
                new AttendanceBackfillBatch(windowStart, windowEnd), 200);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PARSE — Tab-delimited API response  →  Attendance_Log__c records
    // Expected format: Col[0] = Roll Number  |  Col[1] = Log DateTime
    // deviceSerial is stamped on each resulting record so multi-device runs
    // retain provenance (which physical machine recorded each punch).
    // ─────────────────────────────────────────────────────────────────────────
    private List<Attendance_Log__c> parseAndBuild(String raw, String deviceSerial) {
        List<Attendance_Log__c> records = new List<Attendance_Log__c>();

        for (String line : raw.split('\n')) {
            line = line.trim();
            if (String.isBlank(line)) continue;

            String[] cols = line.split('\t');
            if (cols.size() < 2) continue;

            String   rollNumber = cols[0].trim();
            String   logDtStr   = cols[1].trim();
            Datetime logDt      = safeParseDateTime(logDtStr);

            if (String.isBlank(rollNumber) || logDt == null) continue;

            records.add(new Attendance_Log__c(
                Roll_Number__c   = rollNumber,
                Log_Date_Time__c = logDt,
                Device_ID__c     = deviceSerial,
                Status__c        = 'Pending'
            ));
        }

        return records;
    }

    private Datetime safeParseDateTime(String s) {
        try {
            return Datetime.valueOf(s);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Batch1 | Skipping bad datetime: ' + s);
            return null;
        }
    }
}
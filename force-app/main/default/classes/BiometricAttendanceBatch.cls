/**
 * @class   BiometricAttendanceBatch
 * @purpose Fetches raw biometric punch logs from the eSSL device API for an
 *          anchored time window and stores them as Attendance_Log__c records with
 *          Status__c = 'Pending'.
 *
 * @design  Callouts run once in start() (one per active device) and the parsed
 *          records are RETURNED from start(), so the batch framework chunks the
 *          inserts across execute() calls. That keeps each insert inside DML row
 *          limits and keeps heap low.
 *
 * @dedup   Punches are deduplicated on ROLL_NUMBER + LOG_DATE_TIME before insert,
 *          at two levels:
 *            1. within this fetch — the same punch reported twice in one response,
 *               or by two devices, is collapsed to one row;
 *            2. against what is already stored — every existing log in the span
 *               being inserted is loaded and matching keys are skipped.
 *          This matters because the windows deliberately OVERLAP: each daytime run
 *          covers 2 hours and the 23:39 final sweep re-pulls from the PREVIOUS
 *          day 06:00 IST, so without this guard every punch would be stored
 *          several times over.
 *          NOTE the key ignores Device_ID__c — two different devices reporting the
 *          same roll number at the same second are treated as ONE punch.
 *
 * @creds   API username/password come from the protected Custom Metadata record
 *          Biometric_API_Config__mdt 'Default' — never hard-coded here.
 *
 * @suppress ApexCRUDViolation — a scheduled integration job running in system
 *           context; the Attendance_Log__c read below exists only to avoid
 *           inserting duplicates of rows this same job created.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class BiometricAttendanceBatch implements Database.Batchable<SObject>,
                                                                Database.AllowsCallouts,
                                                                Database.Stateful {

    private static final String CONFIG_NAME = 'Default';

    @TestVisible
    private static Biometric_API_Config__mdt configOverride;

    /**
     * Credentials for the device API.
     * @return the 'Default' config record, or the test override when set
     */
    @TestVisible
    private static Biometric_API_Config__mdt apiConfig() {
        if (configOverride != null) {
            return configOverride;
        }
        return Biometric_API_Config__mdt.getInstance(CONFIG_NAME);
    }

    /** Raised around this batch's DML so AttendanceLogTrigger can tell the source. */
    @TestVisible
    public static Boolean isBiometricInsert = false;

    // ── Anchored Time Window (injected by scheduler, never Datetime.now()) ────
    private final Datetime windowStart;
    private final Datetime windowEnd;

    // ── Stateful Counters (accumulated across execute() chunks) ───────────────
    private Integer totalParsed  = 0;
    private Integer totalSuccess = 0;
    private Integer totalFailed  = 0;

    /** Punches dropped by the dedup guard. Exposed so tests can assert on it. */
    @TestVisible
    private Integer totalSkippedDuplicates = 0;

    /**
     * Daytime use: a rolling 2-hour window ending at the anchor.
     * @param anchorTime the scheduled hour this run represents
     */
    public BiometricAttendanceBatch(Datetime anchorTime) {
        this.windowEnd   = anchorTime;
        this.windowStart = anchorTime.addHours(-2);
    }

    /**
     * Explicit-window use, e.g. the 23:39 IST final sweep.
     * @param windowStart inclusive start of the window to request
     * @param windowEnd   inclusive end of the window to request
     */
    public BiometricAttendanceBatch(Datetime windowStart, Datetime windowEnd) {
        this.windowStart = windowStart;
        this.windowEnd   = windowEnd;
    }

    /**
     * Calls the device API once per active device, parses the responses and returns
     * the NEW punches only — see @dedup on the class.
     * @param  bc the batch context
     * @return the deduplicated Attendance_Log__c records to insert
     */
    public Iterable<SObject> start(Database.BatchableContext bc) {

        List<Attendance_Log__c> records = new List<Attendance_Log__c>();

        Biometric_API_Config__mdt cfg = apiConfig();
        if (cfg == null || String.isBlank(cfg.Api_User__c) || String.isBlank(cfg.Api_Password__c)) {
            // Missing credentials: return empty so execute() never runs.
            return records;
        }
        String apiUser = cfg.Api_User__c;
        String apiPass = cfg.Api_Password__c;

        String fromStr = windowStart.format('yyyy-MM-dd HH:mm:ss');
        String toStr   = windowEnd.format('yyyy-MM-dd HH:mm:ss');

        List<Biometric_Device__mdt> devices = [
            SELECT MasterLabel, Serial_Number__c
            FROM Biometric_Device__mdt
            WHERE Is_Active__c = true
        ];

        // One callout per device. Per-device try/catch so a single device outage
        // doesn't abort the whole run — the others still get fetched.
        for (Biometric_Device__mdt device : devices) {
            try {
                tempuriOrgLive.WebAPIServiceSoap svc = new tempuriOrgLive.WebAPIServiceSoap();
                tempuriOrgLive.GetTransactionsLogResponse_element res =
                    svc.GetTransactionsLog(fromStr, toStr, device.Serial_Number__c,
                                           apiUser, apiPass, '1');

                if (String.isNotBlank(res.strDataList)) {
                    records.addAll(parseAndBuild(res.strDataList, device.Serial_Number__c));
                }
            } catch (Exception e) {
                // Swallowed on purpose: one device failing must not stop the rest.
                this.totalFailed++;
            }
        }

        totalParsed = records.size();
        return dropDuplicates(records);
    }

    /**
     * Inserts one chunk. Partial success is tolerated: failures are counted, not
     * thrown, so one bad row cannot lose the whole chunk.
     * @param bc    the batch context
     * @param scope the chunk of Attendance_Log__c records to insert
     */
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
            }
        }
    }

    /**
     * Required by Database.Batchable; this job needs no post-processing.
     * @param bc the batch context
     */
    @SuppressWarnings('PMD.EmptyStatementBlock')
    public void finish(Database.BatchableContext bc) {
        // Intentionally empty — marking is handled by AttendanceMarkingBatch on a
        // schedule, and by DaySyncController's polling loop for the Sync button.
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DEDUP
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Removes punches already stored, and collapses repeats inside this fetch.
     * @param  parsed every punch parsed from every device this run
     * @return only the punches not already present, each key appearing once
     */
    private List<Attendance_Log__c> dropDuplicates(List<Attendance_Log__c> parsed) {
        if (parsed.isEmpty()) {
            return parsed;
        }

        List<Datetime> span = spanOf(parsed);
        Set<String>    seen = existingKeys(span[0], span[1]);

        List<Attendance_Log__c> fresh = new List<Attendance_Log__c>();
        for (Attendance_Log__c log : parsed) {
            String key = dedupKey(log.Roll_Number__c, log.Log_Date_Time__c);
            if (seen.contains(key)) {
                this.totalSkippedDuplicates++;
                continue;
            }
            seen.add(key);   // also blocks repeats within this same fetch
            fresh.add(log);
        }
        return fresh;
    }

    /**
     * The earliest and latest punch instant in a parsed batch.
     * @param  parsed the punches to measure
     * @return a two-element list: [min, max]
     */
    private static List<Datetime> spanOf(List<Attendance_Log__c> parsed) {
        Datetime minLog = null;
        Datetime maxLog = null;
        for (Attendance_Log__c log : parsed) {
            if (minLog == null || log.Log_Date_Time__c < minLog) {
                minLog = log.Log_Date_Time__c;
            }
            if (maxLog == null || log.Log_Date_Time__c > maxLog) {
                maxLog = log.Log_Date_Time__c;
            }
        }
        return new List<Datetime>{ minLog, maxLog };
    }

    /**
     * Loads the dedup keys already stored across a span. Scoped to the exact span
     * being inserted rather than the requested window, so the read stays as small
     * as possible on an object that holds hundreds of thousands of rows.
     * @param  minLog earliest punch instant being inserted
     * @param  maxLog latest punch instant being inserted
     * @return the keys already present in that span
     */
    private static Set<String> existingKeys(Datetime minLog, Datetime maxLog) {
        Set<String> seen = new Set<String>();
        for (Attendance_Log__c existing : [
            SELECT Roll_Number__c, Log_Date_Time__c
            FROM   Attendance_Log__c
            WHERE  Log_Date_Time__c >= :minLog
              AND  Log_Date_Time__c <= :maxLog
              AND  Roll_Number__c   != NULL
        ]) {
            seen.add(dedupKey(existing.Roll_Number__c, existing.Log_Date_Time__c));
        }
        return seen;
    }

    /**
     * The uniqueness key for a punch: roll number + punch instant.
     * @param  rollNumber the identifier the device reported
     * @param  logDt      the punch instant
     * @return a stable key, GMT-formatted so it never shifts with timezone
     */
    @TestVisible
    private static String dedupKey(String rollNumber, Datetime logDt) {
        return rollNumber + '|'
            + (logDt == null ? '' : logDt.formatGmt('yyyy-MM-dd HH:mm:ss'));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PARSE — tab-delimited API response → Attendance_Log__c
    // Col[0] = Roll Number | Col[1] = Log DateTime
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Parses one device's tab-delimited response.
     * @param  raw          the raw strDataList payload
     * @param  deviceSerial the device that produced it, stamped for provenance
     * @return unsaved Attendance_Log__c records, not yet deduplicated
     */
    private List<Attendance_Log__c> parseAndBuild(String raw, String deviceSerial) {
        List<Attendance_Log__c> records = new List<Attendance_Log__c>();

        for (String line : raw.split('\n')) {
            String trimmed = line.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }

            String[] cols = trimmed.split('\t');
            if (cols.size() < 2) {
                continue;
            }

            String   rollNumber = cols[0].trim();
            Datetime logDt      = safeParseDateTime(cols[1].trim());

            if (String.isBlank(rollNumber) || logDt == null) {
                continue;
            }

            records.add(new Attendance_Log__c(
                Roll_Number__c   = rollNumber,
                Log_Date_Time__c = logDt,
                Device_ID__c     = deviceSerial,
                Status__c        = 'Pending'
            ));
        }

        return records;
    }

    /**
     * Parses a device datetime string, skipping unparseable values.
     * @param  s the raw datetime text
     * @return the parsed Datetime, or null if it could not be read
     */
    private Datetime safeParseDateTime(String s) {
        try {
            return Datetime.valueOf(s);
        } catch (Exception e) {
            return null;   // bad row: skipped rather than failing the whole fetch
        }
    }
}
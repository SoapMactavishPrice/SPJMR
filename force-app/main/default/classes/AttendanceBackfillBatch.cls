/**
 * @class   AttendanceBackfillBatch
 * @purpose On-demand backfill for late / historically-uploaded biometric logs.
 *
 *          Unlike AttendanceMarkingBatch (session-driven, 2-day window, runs on
 *          a schedule), this batch is LOG-DRIVEN and meant to be fired manually
 *          from a button after attendance logs going back up to LOOKBACK_DAYS
 *          have been uploaded.
 *
 *          Flow:
 *            1. start()   → every Attendance_Log__c still in 'Pending' status
 *                           whose Log_Date_Time__c is within the last
 *                           LOOKBACK_DAYS.
 *            2. execute() → from those logs, DISCOVER the Sessions they fall
 *                           into, then load EVERY Session_Enrollment__c of those
 *                           Sessions and decide attendance:
 *                             - log inside the session window → Present
 *                             - no log in window              → Absent
 *                           Marking a session fully (not just the students who
 *                           have a log) is what lets this batch set Absent — a
 *                           pure log scan can only ever set Present.
 *
 *          Same safety rules as AttendanceMarkingBatch:
 *            - Only NULL or 'Absent' enrollments are touched. 'Present', 'Late'
 *              and 'Sanctioned Leave' are left untouched.
 *            - A late log flips a previously-Absent enrollment back to Present.
 *            - 'Absent' is only set on enrollments that are still NULL.
 *            - Only "Completed" sessions (End_Time__c at least
 *              ABSENT_BUFFER_MIN minutes in the past) are evaluated.
 *
 * @note    Sessions with ZERO logs are not discoverable here (no log to anchor
 *          on); those are handled by the routine AttendanceMarkingBatch when the
 *          session ends.
 */
public class AttendanceBackfillBatch implements Database.Batchable<SObject>,
                                                Database.Stateful {

    private static final Integer ABSENT_BUFFER_MIN = 15;
    private static final Integer LOOKBACK_DAYS      = 15;

    // Stateful counters / dedup across execute() chunks
    private Set<Id> processedSessionIds  = new Set<Id>();
    private Integer totalPendingLogs     = 0;
    private Integer sessionsProcessed     = 0;
    private Integer enrollmentsExamined   = 0;
    private Integer markedPresent         = 0;
    private Integer markedAbsent          = 0;
    private Integer logsSynced            = 0;
    private Integer failed                = 0;

    // ── start: every Pending log within the lookback window ───────────────────
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime windowStart = System.now().addDays(-LOOKBACK_DAYS);

        return Database.getQueryLocator([
            SELECT Id, Roll_Number__c, Log_Date_Time__c, Status__c
            FROM   Attendance_Log__c
            WHERE  Status__c        = 'Pending'
              AND  Log_Date_Time__c >= :windowStart
              AND  Roll_Number__c   != NULL
            ORDER BY Log_Date_Time__c ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Attendance_Log__c> pendingLogs = (List<Attendance_Log__c>) scope;
        totalPendingLogs += pendingLogs.size();

        Datetime completedCutoff = System.now().addMinutes(-ABSENT_BUFFER_MIN);

        // ── 1. Group the Pending logs in this chunk by roll number ────────────
        Map<String, List<Attendance_Log__c>> pendingByRoll =
            new Map<String, List<Attendance_Log__c>>();
        Datetime minLog = null;
        Datetime maxLog = null;

        for (Attendance_Log__c log : pendingLogs) {
            if (log.Roll_Number__c == null || log.Log_Date_Time__c == null) continue;
            if (!pendingByRoll.containsKey(log.Roll_Number__c)) {
                pendingByRoll.put(log.Roll_Number__c, new List<Attendance_Log__c>());
            }
            pendingByRoll.get(log.Roll_Number__c).add(log);
            if (minLog == null || log.Log_Date_Time__c < minLog) minLog = log.Log_Date_Time__c;
            if (maxLog == null || log.Log_Date_Time__c > maxLog) maxLog = log.Log_Date_Time__c;
        }
        if (pendingByRoll.isEmpty()) return;

        // ── 2. Discover the Sessions those logs fall into ─────────────────────
        // Candidate enrollments for these students whose session window overlaps
        // the log span; a session is "discovered" only if a Pending log actually
        // lands inside its [Start, End) window.
        Set<Id> discoveredSessionIds = new Set<Id>();

        for (Session_Enrollment__c se : [
            SELECT Id, Session__c, Roll_Number__c,
                   Session__r.Start_Time__c, Session__r.End_Time__c
            FROM   Session_Enrollment__c
            WHERE  Roll_Number__c         IN :pendingByRoll.keySet()
              AND  Session__c               != NULL
              AND  Session__r.Start_Time__c <= :maxLog
              AND  Session__r.End_Time__c   >  :minLog
              AND  Session__r.End_Time__c   <  :completedCutoff
        ]) {
            if (se.Session__r.Start_Time__c == null || se.Session__r.End_Time__c == null) continue;
            if (processedSessionIds.contains(se.Session__c)) continue;

            for (Attendance_Log__c log : pendingByRoll.get(se.Roll_Number__c)) {
                if (log.Log_Date_Time__c >= se.Session__r.Start_Time__c
                    && log.Log_Date_Time__c <  se.Session__r.End_Time__c) {
                    discoveredSessionIds.add(se.Session__c);
                    break;
                }
            }
        }
        if (discoveredSessionIds.isEmpty()) return;
        processedSessionIds.addAll(discoveredSessionIds);

        // ── 3. Load EVERY markable enrollment of the discovered sessions ──────
        List<Session_Enrollment__c> enrollments = [
            SELECT Id, Roll_Number__c, Attendance__c, Session__c,
                   Session__r.Start_Time__c, Session__r.End_Time__c
            FROM   Session_Enrollment__c
            WHERE  Session__c IN :discoveredSessionIds
              AND  (Attendance__c = NULL OR Attendance__c = 'Absent')
              AND  Roll_Number__c != NULL
        ];
        if (enrollments.isEmpty()) return;
        sessionsProcessed += discoveredSessionIds.size();

        // ── 4. Fetch ALL logs (any status) that could match this enrollment set
        Set<String> rollNumbers = new Set<String>();
        Datetime spanStart = null;
        Datetime spanEnd   = null;
        for (Session_Enrollment__c se : enrollments) {
            if (se.Session__r.Start_Time__c == null || se.Session__r.End_Time__c == null) continue;
            rollNumbers.add(se.Roll_Number__c);
            if (spanStart == null || se.Session__r.Start_Time__c < spanStart) spanStart = se.Session__r.Start_Time__c;
            if (spanEnd   == null || se.Session__r.End_Time__c   > spanEnd)   spanEnd   = se.Session__r.End_Time__c;
        }

        Map<String, List<Attendance_Log__c>> logMap =
            new Map<String, List<Attendance_Log__c>>();
        for (Attendance_Log__c log : [
            SELECT Id, Roll_Number__c, Log_Date_Time__c, Status__c
            FROM   Attendance_Log__c
            WHERE  Roll_Number__c   IN :rollNumbers
              AND  Log_Date_Time__c >= :spanStart
              AND  Log_Date_Time__c <  :spanEnd
        ]) {
            if (!logMap.containsKey(log.Roll_Number__c)) {
                logMap.put(log.Roll_Number__c, new List<Attendance_Log__c>());
            }
            logMap.get(log.Roll_Number__c).add(log);
        }

        // ── 5. Decide Present / Absent ────────────────────────────────────────
        List<Session_Enrollment__c> enrollmentsToUpdate = new List<Session_Enrollment__c>();
        Map<Id, Attendance_Log__c>  logsToSync          = new Map<Id, Attendance_Log__c>();

        for (Session_Enrollment__c se : enrollments) {
            enrollmentsExamined++;
            if (se.Session__r.Start_Time__c == null || se.Session__r.End_Time__c == null) continue;

            Attendance_Log__c matchedLog = null;
            List<Attendance_Log__c> studentLogs = logMap.get(se.Roll_Number__c);
            if (studentLogs != null) {
                for (Attendance_Log__c log : studentLogs) {
                    if (log.Log_Date_Time__c >= se.Session__r.Start_Time__c
                        && log.Log_Date_Time__c <  se.Session__r.End_Time__c) {
                        matchedLog = log;
                        break;
                    }
                }
            }

            if (matchedLog != null) {
                if (se.Attendance__c != 'Present') {
                    se.Attendance__c = 'Present';
                    enrollmentsToUpdate.add(se);
                    markedPresent++;
                }
                if (matchedLog.Status__c != 'Synced') {
                    matchedLog.Status__c = 'Synced';
                    logsToSync.put(matchedLog.Id, matchedLog);
                }
            } else if (se.Attendance__c == null) {
                // No log in window — Absent only if still unmarked
                se.Attendance__c = 'Absent';
                enrollmentsToUpdate.add(se);
                markedAbsent++;
            }
        }

        // ── 6. Persist ────────────────────────────────────────────────────────
        if (!enrollmentsToUpdate.isEmpty()) {
            for (Database.SaveResult sr : Database.update(enrollmentsToUpdate, false)) {
                if (!sr.isSuccess()) {
                    failed++;
                    for (Database.Error err : sr.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'AttendanceBackfillBatch | Enrollment update failed: '
                            + err.getStatusCode() + ' - ' + err.getMessage());
                    }
                }
            }
        }
        if (!logsToSync.isEmpty()) {
            Database.update(logsToSync.values(), false);
            logsSynced += logsToSync.size();
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('========================================');
        System.debug('AttendanceBackfillBatch | COMPLETE');
        System.debug('Pending logs scanned : ' + totalPendingLogs);
        System.debug('Sessions processed   : ' + sessionsProcessed);
        System.debug('Enrollments examined : ' + enrollmentsExamined);
        System.debug('Marked Present       : ' + markedPresent);
        System.debug('Marked Absent        : ' + markedAbsent);
        System.debug('Logs synced          : ' + logsSynced);
        System.debug('Failed               : ' + failed);
        System.debug('========================================');
    }
}
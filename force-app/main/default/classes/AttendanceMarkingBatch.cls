/**
 * @class   AttendanceMarkingBatch
 * @purpose For every Session_Enrollment__c whose Session has already ended
 *          (Completed Session), decide attendance based on Attendance_Log__c
 *          rows received from the ESSL biometric server:
 *            - log inside the session window → Present
 *            - no log in window              → Absent
 *
 *          A late log arriving after an enrollment was already marked Absent
 *          will flip it back to Present. Already-Present and
 *          Sanctioned-Leave enrollments are left untouched.
 *
 * @schedule Every 2 hours 08:10–20:10 IST + a final sweep at 23:49 IST,
 *           Monday to Saturday (see AttendanceMarkingScheduler).
 *
 * @completed A session is considered "Completed" once End_Time__c is at least
 *            ABSENT_BUFFER_MIN minutes in the past. The buffer absorbs late
 *            ESSL syncs and clock skew.
 *
 * @window  Each run looks back LOOKBACK_DAYS to absorb missed runs / outages
 *          and to safely straddle the IST↔UTC midnight boundary.
 */
public class AttendanceMarkingBatch implements Database.Batchable<SObject>,
                                               Database.Stateful {

    private static final Integer ABSENT_BUFFER_MIN = 15;
    private static final Integer LOOKBACK_DAYS     = 2;

    private Integer totalProcessed     = 0;
    private Integer totalMarkedPresent = 0;
    private Integer totalMarkedAbsent  = 0;
    private Integer totalSkipped       = 0;
    private Integer totalFailed        = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime completedCutoff = System.now().addMinutes(-ABSENT_BUFFER_MIN);
        Datetime windowStart     = System.now().addDays(-LOOKBACK_DAYS);

        return Database.getQueryLocator([
            SELECT Id,
                   Roll_Number__c,
                   Attendance__c,
                   Session__r.Start_Time__c,
                   Session__r.End_Time__c
            FROM   Session_Enrollment__c
            WHERE  (Attendance__c = NULL OR Attendance__c = 'Absent')
              AND  Session__r.Schedule_Type__c = 'Published'
              AND  Session__r.End_Time__c   <  :completedCutoff
              AND  Session__r.Start_Time__c >= :windowStart
            ORDER BY Session__r.Start_Time__c ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Session_Enrollment__c> enrollments = (List<Session_Enrollment__c>) scope;

        // ── 1. Collect roll numbers + datetime span of the session set ────────
        Set<String> rollNumbers = new Set<String>();
        Datetime minStart = null;
        Datetime maxEnd   = null;

        for (Session_Enrollment__c se : enrollments) {
            if (se.Roll_Number__c == null
                || se.Session__r.Start_Time__c == null
                || se.Session__r.End_Time__c   == null) continue;

            rollNumbers.add(se.Roll_Number__c);
            if (minStart == null || se.Session__r.Start_Time__c < minStart) {
                minStart = se.Session__r.Start_Time__c;
            }
            if (maxEnd == null || se.Session__r.End_Time__c > maxEnd) {
                maxEnd = se.Session__r.End_Time__c;
            }
        }

        if (rollNumbers.isEmpty()) return;

        // ── 2. Fetch every log that could possibly match this set ─────────────
        List<Attendance_Log__c> logs = [
            SELECT Id, Roll_Number__c, Log_Date_Time__c, Status__c
            FROM   Attendance_Log__c
            WHERE  Roll_Number__c   IN :rollNumbers
              AND  Log_Date_Time__c >= :minStart
              AND  Log_Date_Time__c <  :maxEnd
        ];

        Map<String, List<Attendance_Log__c>> logMap =
            new Map<String, List<Attendance_Log__c>>();

        for (Attendance_Log__c log : logs) {
            if (!logMap.containsKey(log.Roll_Number__c)) {
                logMap.put(log.Roll_Number__c, new List<Attendance_Log__c>());
            }
            logMap.get(log.Roll_Number__c).add(log);
        }

        // ── 3. Decide Present / Absent for each enrollment ────────────────────
        List<Session_Enrollment__c> enrollmentsToUpdate = new List<Session_Enrollment__c>();
        List<Attendance_Log__c>     logsToSync          = new List<Attendance_Log__c>();

        for (Session_Enrollment__c se : enrollments) {
            totalProcessed++;

            if (se.Roll_Number__c == null
                || se.Session__r.Start_Time__c == null
                || se.Session__r.End_Time__c   == null) {
                totalSkipped++;
                continue;
            }

            Attendance_Log__c matchedLog = null;
            List<Attendance_Log__c> studentLogs = logMap.get(se.Roll_Number__c);

            if (studentLogs != null) {
                for (Attendance_Log__c log : studentLogs) {
                    if (log.Log_Date_Time__c >= se.Session__r.Start_Time__c
                        && log.Log_Date_Time__c < se.Session__r.End_Time__c) {
                        matchedLog = log;
                        break;
                    }
                }
            }

            if (matchedLog != null) {
                // Either currently NULL (first marking) or 'Absent' (late-log correction)
                if (se.Attendance__c != 'Present') {
                    se.Attendance__c = 'Present';
                    enrollmentsToUpdate.add(se);
                    totalMarkedPresent++;
                }
                if (matchedLog.Status__c != 'Synced') {
                    matchedLog.Status__c = 'Synced';
                    logsToSync.add(matchedLog);
                }
                continue;
            }

            // No log in window — mark Absent only if not already marked.
            if (se.Attendance__c == null) {
                se.Attendance__c = 'Absent';
                enrollmentsToUpdate.add(se);
                totalMarkedAbsent++;
            } else {
                totalSkipped++;
            }
        }

        if (!enrollmentsToUpdate.isEmpty()) {
            Database.SaveResult[] seResults = Database.update(enrollmentsToUpdate, false);
            for (Database.SaveResult sr : seResults) {
                if (!sr.isSuccess()) {
                    totalFailed++;
                    for (Database.Error err : sr.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'AttendanceMarkingBatch | Enrollment update failed: '
                            + err.getStatusCode() + ' - ' + err.getMessage());
                    }
                }
            }
        }

        if (!logsToSync.isEmpty()) {
            Database.update(logsToSync, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('========================================');
        System.debug('AttendanceMarkingBatch | COMPLETE');
        System.debug('Processed      : ' + totalProcessed);
        System.debug('Marked Present : ' + totalMarkedPresent);
        System.debug('Marked Absent  : ' + totalMarkedAbsent);
        System.debug('Skipped        : ' + totalSkipped);
        System.debug('Failed         : ' + totalFailed);
        System.debug('========================================');
    }
}
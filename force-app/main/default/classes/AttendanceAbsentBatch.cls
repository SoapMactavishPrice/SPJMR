public class AttendanceAbsentBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Integer totalProcessed = 0;
    private Integer totalMarked    = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {

        // Only pick sessions:
        // - Not yet marked
        // - Already ended + 15 min buffer
        // - Scheduled for today — avoids reprocessing old unmarked rows
        return Database.getQueryLocator([
            SELECT Id,
                   Roll_Number__c,
                   Attendance__c,
                   Session__r.Start_Time__c,
                   Session__r.End_Time__c
            FROM Session_Enrollment__c
            WHERE Attendance__c = NULL
            AND Session__r.End_Time__c < :System.now().addMinutes(-15)
            AND Session__r.Start_Time__c = TODAY
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {

        List<Session_Enrollment__c> enrollments = (List<Session_Enrollment__c>) scope;

        // ── Collect Roll Numbers and Time Windows ─────────────────────
        Set<String> rollNumbers = new Set<String>();
        Datetime minStart;
        Datetime maxEnd;

        for (Session_Enrollment__c se : enrollments) {
            if (se.Roll_Number__c == null ||
                se.Session__r.Start_Time__c == null ||
                se.Session__r.End_Time__c == null) continue;

            rollNumbers.add(se.Roll_Number__c);

            if (minStart == null || se.Session__r.Start_Time__c < minStart) {
                minStart = se.Session__r.Start_Time__c;
            }
            if (maxEnd == null || se.Session__r.End_Time__c > maxEnd) {
                maxEnd = se.Session__r.End_Time__c;
            }
        }

        if (rollNumbers.isEmpty()) return;

        // ── Fetch logs in ONE query (bulk safe) ───────────────────────
        List<Attendance_Log__c> logs = [
            SELECT Id, Roll_Number__c, Log_Date_Time__c
            FROM Attendance_Log__c
            WHERE Roll_Number__c IN :rollNumbers
            AND Log_Date_Time__c >= :minStart
            AND Log_Date_Time__c < :maxEnd
        ];

        // ── Build Map: RollNumber → List of Logs ──────────────────────
        Map<String, List<Attendance_Log__c>> logMap = new Map<String, List<Attendance_Log__c>>();

        for (Attendance_Log__c log : logs) {
            if (!logMap.containsKey(log.Roll_Number__c)) {
                logMap.put(log.Roll_Number__c, new List<Attendance_Log__c>());
            }
            logMap.get(log.Roll_Number__c).add(log);
        }

        // ── Evaluate each enrollment ──────────────────────────────────
        List<Session_Enrollment__c> toUpdate = new List<Session_Enrollment__c>();

        for (Session_Enrollment__c se : enrollments) {
            totalProcessed++;

            List<Attendance_Log__c> studentLogs = logMap.get(se.Roll_Number__c);

            Boolean hasLogInWindow = false;

            if (studentLogs != null) {
                for (Attendance_Log__c log : studentLogs) {
                    if (log.Log_Date_Time__c >= se.Session__r.Start_Time__c &&
                        log.Log_Date_Time__c < se.Session__r.End_Time__c) {

                        hasLogInWindow = true;
                        break;
                    }
                }
            }

            // No log found → mark Absent
            if (!hasLogInWindow) {
                se.Attendance__c = 'Absent';
                toUpdate.add(se);
                totalMarked++;
            }
        }

        // ── Bulk update ───────────────────────────────────────────────
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('========================================');
        System.debug('Absent Batch Completed');
        System.debug('Processed : ' + totalProcessed);
        System.debug('Marked Absent : ' + totalMarked);
        System.debug('========================================');
    }
}
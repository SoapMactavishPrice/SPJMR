public class AttendanceBackfillBatch implements Database.Batchable<SObject>,
                                                Database.Stateful {

    private static final Integer ABSENT_BUFFER_MIN = 15;
    private static final Integer LOOKBACK_DAYS      = 15;

    private Set<Id> processedSessionIds  = new Set<Id>();
    private Integer totalPendingLogs     = 0;
    private Integer sessionsProcessed     = 0;
    private Integer enrollmentsExamined   = 0;
    private Integer markedPresent         = 0;
    private Integer markedAbsent          = 0;
    private Integer logsSynced            = 0;
    private Integer failed                = 0;

    private final Datetime windowStartOverride;
    private final Datetime windowEndOverride;

    public AttendanceBackfillBatch() {
        this.windowStartOverride = null;
        this.windowEndOverride   = null;
    }

    public AttendanceBackfillBatch(Datetime windowStart, Datetime windowEnd) {
        this.windowStartOverride = windowStart;
        this.windowEndOverride   = windowEnd;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (windowStartOverride != null && windowEndOverride != null) {
            Datetime ws = windowStartOverride;
            Datetime we = windowEndOverride;
            return Database.getQueryLocator([
                SELECT Id, Roll_Number__c, Log_Date_Time__c, Status__c
                FROM   Attendance_Log__c
                WHERE  Status__c        = 'Pending'
                  AND  Log_Date_Time__c >= :ws
                  AND  Log_Date_Time__c <  :we
                  AND  Roll_Number__c   != NULL
                ORDER BY Log_Date_Time__c ASC
            ]);
        }

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

        Set<Id> discoveredSessionIds = new Set<Id>();

        for (Session_Enrollment__c se : [
            SELECT Id, Session__c, Registeration_Number__c,
                   Session__r.Start_Time__c, Session__r.End_Time__c
            FROM   Session_Enrollment__c
            WHERE  Registeration_Number__c IN :pendingByRoll.keySet()
              AND  Session__c               != NULL
              AND  Session__r.Start_Time__c <= :maxLog
              AND  Session__r.End_Time__c   >  :minLog
              AND  Session__r.End_Time__c   <  :completedCutoff
        ]) {
            if (se.Session__r.Start_Time__c == null || se.Session__r.End_Time__c == null) continue;
            if (processedSessionIds.contains(se.Session__c)) continue;

            for (Attendance_Log__c log : pendingByRoll.get(se.Registeration_Number__c)) {
                if (log.Log_Date_Time__c >= se.Session__r.Start_Time__c
                    && log.Log_Date_Time__c <  se.Session__r.End_Time__c) {
                    discoveredSessionIds.add(se.Session__c);
                    break;
                }
            }
        }
        if (discoveredSessionIds.isEmpty()) return;
        processedSessionIds.addAll(discoveredSessionIds);

        List<Session_Enrollment__c> enrollments = [
            SELECT Id, Registeration_Number__c, Attendance__c, Session__c,
                   Session__r.Start_Time__c, Session__r.End_Time__c
            FROM   Session_Enrollment__c
            WHERE  Session__c IN :discoveredSessionIds
              AND  (Attendance__c = NULL OR Attendance__c = 'Absent')
              AND  Registeration_Number__c != NULL
        ];
        if (enrollments.isEmpty()) return;
        sessionsProcessed += discoveredSessionIds.size();

        Set<String> rollNumbers = new Set<String>();
        Datetime spanStart = null;
        Datetime spanEnd   = null;
        for (Session_Enrollment__c se : enrollments) {
            if (se.Session__r.Start_Time__c == null || se.Session__r.End_Time__c == null) continue;
            rollNumbers.add(se.Registeration_Number__c);
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

        List<Session_Enrollment__c> enrollmentsToUpdate = new List<Session_Enrollment__c>();
        Map<Id, Attendance_Log__c>  logsToSync          = new Map<Id, Attendance_Log__c>();

        for (Session_Enrollment__c se : enrollments) {
            enrollmentsExamined++;
            if (se.Session__r.Start_Time__c == null || se.Session__r.End_Time__c == null) continue;

            Attendance_Log__c matchedLog = null;
            List<Attendance_Log__c> studentLogs = logMap.get(se.Registeration_Number__c);
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
        
    }
}
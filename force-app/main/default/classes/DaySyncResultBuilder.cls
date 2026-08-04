@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class DaySyncResultBuilder {

    private static final String VAL_NOT_MARKED   = 'Not Marked';
    private static final String ATTENDANCE_FIELD = 'Attendance__c';

    @TestVisible private static Map<Id, String> beforeOverride;

    private final Datetime runStart;
    private final Datetime dayStart;
    private final Datetime dayEnd;

    public List<DaySyncSessionResult> rows { get; private set; }

    public Integer logsFetched { get; private set; }

    public Integer totalSessions { get; private set; }

    public Integer totalStudents { get; private set; }

    public Integer totalChanged { get; private set; }

    public Integer totalNewPresent { get; private set; }

    public Integer totalNewAbsent { get; private set; }

    public DaySyncResultBuilder(Datetime runStart, Datetime dayStart, Datetime dayEnd) {
        this.runStart = runStart;
        this.dayStart = dayStart;
        this.dayEnd   = dayEnd;

        this.rows            = new List<DaySyncSessionResult>();
        this.logsFetched     = 0;
        this.totalSessions   = 0;
        this.totalStudents   = 0;
        this.totalChanged    = 0;
        this.totalNewPresent = 0;
        this.totalNewAbsent  = 0;
    }

    public void build() {
        this.logsFetched = countImportedLogs();

        Map<Id, String> beforeByEnrollment = loadBeforeValues();
        if (beforeByEnrollment.isEmpty()) {
            return;
        }

        Set<Id> sessionIds = sessionsOnSyncedDay(beforeByEnrollment.keySet());
        if (sessionIds.isEmpty()) {
            return;
        }

        this.rows = tallySessions(sessionIds, beforeByEnrollment);
        this.rows.sort();
        rollUpTotals();
    }

    private Integer countImportedLogs() {
        Id me = UserInfo.getUserId();
        return [
            SELECT COUNT()
            FROM   Attendance_Log__c
            WHERE  CreatedById  = :me
              AND  CreatedDate >= :runStart
        ];
    }

    private Map<Id, String> loadBeforeValues() {
        if (beforeOverride != null) {
            return beforeOverride;
        }
        Id me = UserInfo.getUserId();
        Map<Id, String> beforeByEnrollment = new Map<Id, String>();

        for (Session_Enrollment__History h : [
            SELECT ParentId, OldValue, CreatedDate
            FROM   Session_Enrollment__History
            WHERE  Field        = :ATTENDANCE_FIELD
              AND  CreatedById  = :me
              AND  CreatedDate >= :runStart
            ORDER BY CreatedDate ASC
        ]) {
            if (!beforeByEnrollment.containsKey(h.ParentId)) {
                beforeByEnrollment.put(h.ParentId, toLabel(h.OldValue));
            }
        }
        return beforeByEnrollment;
    }

    private Set<Id> sessionsOnSyncedDay(Set<Id> changedIds) {
        Set<Id> sessionIds = new Set<Id>();
        for (Session_Enrollment__c se : [
            SELECT Session__c
            FROM   Session_Enrollment__c
            WHERE  Id         IN :changedIds
              AND  Session__c != NULL
              AND  Session__r.Start_Time__c >= :dayStart
              AND  Session__r.Start_Time__c <  :dayEnd
        ]) {
            sessionIds.add(se.Session__c);
        }
        return sessionIds;
    }

    private List<DaySyncSessionResult> tallySessions(
        Set<Id> sessionIds, Map<Id, String> beforeByEnrollment
    ) {
        Map<Id, DaySyncSessionResult> rowsBySession =
            new Map<Id, DaySyncSessionResult>();

        for (Session_Enrollment__c se : [
            SELECT Id, Attendance__c, Session__c,
                   Session__r.Name, Session__r.Start_Time__c, Session__r.End_Time__c
            FROM   Session_Enrollment__c
            WHERE  Session__c IN :sessionIds
            ORDER BY Session__r.Start_Time__c ASC
        ]) {
            DaySyncSessionResult row = rowsBySession.get(se.Session__c);
            if (row == null) {
                row = new DaySyncSessionResult(se.Session__c, se.Session__r);
                rowsBySession.put(se.Session__c, row);
            }
            String afterVal  = toLabel(se.Attendance__c);
            String beforeVal = beforeByEnrollment.containsKey(se.Id)
                ? beforeByEnrollment.get(se.Id)
                : afterVal;
            row.add(beforeVal, afterVal);
        }
        return rowsBySession.values();
    }

    private void rollUpTotals() {
        this.totalSessions = rows.size();
        for (DaySyncSessionResult row : rows) {
            this.totalStudents   += row.total;
            this.totalChanged    += row.changed;
            this.totalNewPresent += row.newPresent;
            this.totalNewAbsent  += row.newAbsent;
        }
    }

    private static String toLabel(Object raw) {
        String s = raw == null ? null : String.valueOf(raw);
        return String.isBlank(s) ? VAL_NOT_MARKED : s;
    }
}
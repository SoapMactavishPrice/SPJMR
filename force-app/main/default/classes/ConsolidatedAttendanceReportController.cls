/**
 * @description
 * Controller supporting the "Consolidated Attendance Report" LWC.
 *
 * Given a Programme → Batch → Batch Group → Term → Division → Course selection
 * and a date range, this class:
 *   1. Resolves the set of completed Session__c records that match the filters
 *      (a session is "completed" when Schedule_Type__c = 'Complete' OR the
 *      Is_Completed__c formula has evaluated to true).
 *   2. Builds one SessionColumn per matching session (date, time range, course,
 *      faculty, division names) to drive the report's column headers.
 *   3. Builds one StudentRow per enrolled student, pulling their attendance
 *      status/remark for each session they are enrolled in via
 *      Session_Enrollment__c.
 *   4. Aggregates each student's Present / Absent / Late / Sanctioned Leave
 *      counts and Absent % — all computed per student against that student's
 *      own applicable session count (not the report's total session count),
 *      since not every student is necessarily enrolled in every session.
 *
 * Division handling: when a division (or "All Divisions") is selected, results
 * are restricted using the Session_Division__c junction object. This ensures
 * that a combined session spanning multiple divisions only returns students
 * belonging to the selected division(s), rather than every student enrolled
 * in that session regardless of division.
 */
public without sharing class ConsolidatedAttendanceReportController {
/**
 * @description Represents one report column — i.e. one completed session,
 * with the display metadata (date, time, course, faculty, division) needed
 * to render its header cells.
 */
    public class SessionColumn {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String sessionName;
        @AuraEnabled public String courseName;
        @AuraEnabled public String facultyNames;
        @AuraEnabled public String divisionNames;
        @AuraEnabled public String sessionDateStr;
        @AuraEnabled public String timeRangeStr;
        @AuraEnabled public Integer sessionNumber;
    }
    
    public class AttendanceCell {
        @AuraEnabled public String attendance;
        @AuraEnabled public String remark;
    }
    
    public class StudentRow {
        @AuraEnabled public String rollNumber;
        @AuraEnabled public String studentName;
        @AuraEnabled public Map<String, AttendanceCell> cellsBySessionId;
        @AuraEnabled public Integer totalSessionsCovered;
        @AuraEnabled public Integer presentCount;
        @AuraEnabled public Integer absentCount;
        @AuraEnabled public Integer lateCount;
        @AuraEnabled public Integer sanctionedLeaveCount;
        @AuraEnabled public Decimal absentPercent;
    }
    /**
 * @description Top-level payload returned to the LWC: the ordered list of
 * session columns and the list of student rows that make up the report grid.
 */
    public class ReportResult {
        @AuraEnabled public List<SessionColumn> sessions = new List<SessionColumn>();
        @AuraEnabled public List<StudentRow> students = new List<StudentRow>();
    }
    
    @AuraEnabled
    public static ReportResult generateAttendanceReport(
        String programId,
        String batchId,
        String batchGroupId,
        String termId,
        String divisionId,
        List<String> divisionIds,
        String courseId,
        String startDateStr,
        String endDateStr
    ) {
        ReportResult result = new ReportResult();
        
        // ---------- Resolve Course Id ----------
        Id courseLookupId = null;
        if (String.isNotBlank(courseId)) {
            if (courseId.contains('|')) {
                String[] parts = courseId.split('\\|');
                if (parts.size() > 1 && String.isNotBlank(parts[1])) {
                    try { courseLookupId = Id.valueOf(parts[1]); } catch (Exception e) {}
                }
            } else {
                try { courseLookupId = Id.valueOf(courseId); } catch (Exception e) {}
            }
        }
        
        // ---------- Resolve Division Ids ----------
        Set<Id> divisionIdSet = new Set<Id>();
        if (String.isNotBlank(divisionId) && divisionId != 'ALL') {
            try { divisionIdSet.add(Id.valueOf(divisionId)); } catch (Exception e) {}
        } else if (divisionIds != null && !divisionIds.isEmpty()) {
            for (String d : divisionIds) {
                if (String.isBlank(d) || d == 'ALL') continue;
                try { divisionIdSet.add(Id.valueOf(d)); } catch (Exception e) {}
            }
        }
        
        // ---------- Resolve Session Ids AND Session_Division__c junction Ids that
        // match the selected division(s). The junction Ids are what let us later
        // restrict Session_Enrollment__c to only the selected division's students,
        // even when a session is a combined session spanning multiple divisions. ----------
        Set<Id> sessionIdsByDivision = new Set<Id>();
        Set<Id> sessionDivisionIdsForFilter = new Set<Id>();
        Map<Id, Set<String>> sessionIdToDivisionNames = new Map<Id, Set<String>>();
        if (!divisionIdSet.isEmpty()) {
            for (Session_Division__c sd : [
                SELECT Id, Session__c, Division__c, Division__r.Division_Name__c
                FROM Session_Division__c
                WHERE Division__c IN :divisionIdSet
            ]) {
                sessionIdsByDivision.add(sd.Session__c);
                sessionDivisionIdsForFilter.add(sd.Id);
                String dName = sd.Division__r != null ? sd.Division__r.Division_Name__c : null;
                if (String.isNotBlank(dName)) {
                    Set<String> names = sessionIdToDivisionNames.get(sd.Session__c);
                    if (names == null) {
                        names = new Set<String>();
                        sessionIdToDivisionNames.put(sd.Session__c, names);
                    }
                    names.add(dName);
                }
            }
            if (sessionIdsByDivision.isEmpty()) {
                return result;
            }
        }
        
        // ---------- Parse dates ----------
        Date startDate = String.isNotBlank(startDateStr) ? Date.valueOf(startDateStr) : null;
        Date endDate = String.isNotBlank(endDateStr) ? Date.valueOf(endDateStr) : null;
        
        // ---------- Build session query ----------
        // FIX: only completed sessions are shown — attendance is only final once a
        // session has actually finished. A session counts as completed when either
        // its Schedule_Type__c is explicitly 'Completed', or the Is_Completed__c
        // formula (true once End_Time__c has passed) is true.
        String query = 'SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, ' +
            'Course__c, Course__r.Name, Program__c, Batch__c, Academic_Year__c, Term__c ' +
            'FROM Session__c ' +
            'WHERE Schedule_Type__c != \'Cancelled\' ' +
            'AND (Schedule_Type__c = \'Complete\' OR Is_Completed__c = true) ';
        
        List<String> conditions = new List<String>();
        if (!sessionIdsByDivision.isEmpty()) conditions.add('Id IN :sessionIdsByDivision');
        if (courseLookupId != null)          conditions.add('Course__c = :courseLookupId');
        if (startDate != null)               conditions.add('Session_Date__c >= :startDate');
        if (endDate != null)                 conditions.add('Session_Date__c <= :endDate');
        if (String.isNotBlank(programId))    conditions.add('Program__c = :programId');
        if (String.isNotBlank(batchId))      conditions.add('Batch__c = :batchId');
        if (String.isNotBlank(batchGroupId)) conditions.add('Academic_Year__c = :batchGroupId');
        if (String.isNotBlank(termId))       conditions.add('Term__c = :termId');
        
        if (!conditions.isEmpty()) {
            query += ' AND ' + String.join(conditions, ' AND ');
        }
        query += ' ORDER BY Session_Date__c, Start_Time__c';
        
        List<Session__c> sessions = Database.query(query);
        if (sessions.isEmpty()) {
            return result;
        }
        Map<Id, Session__c> sessionsById = new Map<Id, Session__c>(sessions);
        
        // ---------- If no explicit division filter was applied, still fetch
        // division names per session for display purposes (no restriction needed
        // here since the user didn't scope by division at all). ----------
        if (divisionIdSet.isEmpty()) {
            for (Session_Division__c sd : [
                SELECT Session__c, Division__r.Division_Name__c
                FROM Session_Division__c
                WHERE Session__c IN :sessionsById.keySet()
            ]) {
                String dName = sd.Division__r != null ? sd.Division__r.Division_Name__c : null;
                if (String.isNotBlank(dName)) {
                    Set<String> names = sessionIdToDivisionNames.get(sd.Session__c);
                    if (names == null) {
                        names = new Set<String>();
                        sessionIdToDivisionNames.put(sd.Session__c, names);
                    }
                    names.add(dName);
                }
            }
        }
        
        // ---------- Faculty names per session ----------
        List<Session_Faculty__c> sessionFaculties = [
            SELECT Session__c, Session_Faculty__c
            FROM Session_Faculty__c
            WHERE Session__c IN :sessionsById.keySet()
            AND Session_Faculty__c != null
        ];
        Set<Id> facultyAccountIds = new Set<Id>();
        for (Session_Faculty__c sf : sessionFaculties) {
            facultyAccountIds.add(sf.Session_Faculty__c);
        }
        Map<Id, String> facultyNameById = new Map<Id, String>();
        if (!facultyAccountIds.isEmpty()) {
            for (Account a : [SELECT Id, Name FROM Account WHERE Id IN :facultyAccountIds]) {
                facultyNameById.put(a.Id, a.Name);
            }
        }
        Map<Id, List<String>> facultyNamesBySession = new Map<Id, List<String>>();
        for (Session_Faculty__c sf : sessionFaculties) {
            String fname = facultyNameById.get(sf.Session_Faculty__c);
            if (String.isBlank(fname)) continue;
            List<String> names = facultyNamesBySession.get(sf.Session__c);
            if (names == null) {
                names = new List<String>();
                facultyNamesBySession.put(sf.Session__c, names);
            }
            names.add(fname);
        }
        
        // ---------- Build ordered SessionColumn list ----------
        Integer sessionCounter = 0;
        for (Session__c s : sessions) {
            sessionCounter++;
            SessionColumn col = new SessionColumn();
            col.sessionId = s.Id;
            col.sessionName = s.Name;
            col.courseName = s.Course__r != null ? s.Course__r.Name : '';
            List<String> fNames = facultyNamesBySession.get(s.Id);
            col.facultyNames = (fNames != null && !fNames.isEmpty()) ? String.join(fNames, ', ') : '';
            Set<String> divNames = sessionIdToDivisionNames.get(s.Id);
            col.divisionNames = (divNames != null && !divNames.isEmpty())
                ? String.join(new List<String>(divNames), ', ')
                : '';
            col.sessionDateStr = s.Session_Date__c != null ? formatDateShort(s.Session_Date__c) : '';
            col.timeRangeStr = formatTimeRange(s.Start_Time__c, s.End_Time__c);
            col.sessionNumber = sessionCounter;
            result.sessions.add(col);
        }
        
        // ---------- Attendance data ----------
        // FIX: when a division filter is in play (either one specific division, or
        // "All Divisions" resolved to an explicit list), restrict enrollments to
        // only the Session_Division__c junction rows that belong to that filter.
        // Without this, a combined session spanning Division A + B would return
        // EVERY enrolled student from both divisions regardless of which division
        // the user actually selected.
        List<Session_Enrollment__c> enrollments;
        if (!sessionDivisionIdsForFilter.isEmpty()) {
            enrollments = [
                SELECT Session__c, Roll_Number__c, Student_Name__c, Attendance__c, Remark__c, Session_Division__c
                FROM Session_Enrollment__c
                WHERE Session__c IN :sessionsById.keySet()
                AND Session_Division__c IN :sessionDivisionIdsForFilter
            ];
        } else {
            enrollments = [
                SELECT Session__c, Roll_Number__c, Student_Name__c, Attendance__c, Remark__c, Session_Division__c
                FROM Session_Enrollment__c
                WHERE Session__c IN :sessionsById.keySet()
            ];
        }
        
        Map<String, StudentRow> rowsByStudentKey = new Map<String, StudentRow>();
        List<String> studentKeyOrder = new List<String>();
        
        for (Session_Enrollment__c se : enrollments) {
            String rollNumber = se.Roll_Number__c;
            String studentName = se.Student_Name__c;
            String key = String.isNotBlank(rollNumber) ? rollNumber : studentName;
            if (String.isBlank(key)) continue;
            
            StudentRow row = rowsByStudentKey.get(key);
            if (row == null) {
                row = new StudentRow();
                row.rollNumber = rollNumber;
                row.studentName = studentName;
                row.cellsBySessionId = new Map<String, AttendanceCell>();
                rowsByStudentKey.put(key, row);
                studentKeyOrder.add(key);
            }
            
            AttendanceCell cell = new AttendanceCell();
            cell.attendance = se.Attendance__c;
            cell.remark = se.Remark__c;
            row.cellsBySessionId.put(String.valueOf(se.Session__c), cell);
        }
        
        // NEW
        // NEW
        studentKeyOrder.sort();
        
        for (String key : studentKeyOrder) {
            StudentRow row = rowsByStudentKey.get(key);
            
            // Per-student total: number of sessions THIS student has an enrollment
            // record for, not the global session count for the whole report.
            Integer studentTotalSessions = row.cellsBySessionId.size();
            
            Integer presentCount = 0;
            Integer absentCount = 0;
            Integer lateCount = 0;
            Integer sanctionedCount = 0;
            
            for (AttendanceCell cell : row.cellsBySessionId.values()) {
                String val = String.isNotBlank(cell.attendance) ? cell.attendance.toLowerCase() : '';
                if (val.startsWith('present')) {
                    presentCount++;
                } else if (val.startsWith('absent')) {
                    absentCount++;
                } else if (val.startsWith('late')) {
                    lateCount++;
                } else if (val.contains('sanction')) {
                    sanctionedCount++;
                }
            }
            
            row.totalSessionsCovered = studentTotalSessions;
            row.presentCount = presentCount;
            row.absentCount = absentCount;
            row.lateCount = lateCount;
            row.sanctionedLeaveCount = sanctionedCount;
            row.absentPercent = studentTotalSessions > 0
                ? (Decimal.valueOf(absentCount) * 100 / studentTotalSessions).setScale(2): 0;
            
            result.students.add(row);
        }
        
        return result;
    }
    /**
 * @description Formats a Date as "dd-MMM-yy" (e.g. 24-Dec-25) for display
 * in report column headers.
 * @param d The date to format.
 * @return  The formatted date string, or an empty string handling is left to the caller for null dates.
 */
    private static String formatDateShort(Date d) {
        List<String> months = new List<String>{
            'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
                };
                    String day = (d.day() < 10 ? '0' : '') + String.valueOf(d.day());
        String month = months[d.month() - 1];
        String year = String.valueOf(d.year()).substring(2);
        return day + '-' + month + '-' + year;
    }
    /**
 * @description Formats a session's start/end Datetime as an "HH:mm-HH:mm"
 * range string for display in report column headers.
 * @param startT Session start time.
 * @param endT   Session end time.
 * @return       Formatted time range, or an empty string if either input is null.
 */
    private static String formatTimeRange(Datetime startT, Datetime endT) {
        if (startT == null || endT == null) return '';
        return startT.format('HH:mm') + '-' + endT.format('HH:mm');
    }
}
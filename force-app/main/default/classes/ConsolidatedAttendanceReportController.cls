/**
 * @description
 * Controller supporting the "Consolidated Attendance Report" LWC.
 *
 * Given a Programme → Batch → Batch Group → Term → Division(s) → Course
 * selection and a date range, this class:
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
 * Division handling: `divisionIds` carries EITHER a single division (one-item
 * list) OR multiple divisions ("All Divisions" resolved by the LWC). Results
 * are restricted using the Session_Division__c junction object, ensuring a
 * combined session spanning multiple divisions only returns students
 * belonging to the selected division(s), rather than every student enrolled
 * in that session regardless of division.
 *
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
        List<String> divisionIds,
        // ^ REVIEW FIX: `divisionId` (singular) removed. A single division
        // selection is now just a one-item list — no need for a second
        // parameter to represent the same information two different ways.
        String courseId,
        String startDateStr,
        String endDateStr
    ) {
        ReportResult result = new ReportResult();

        // ---------- Resolve Course Id ----------
        Id courseLookupId = null;
        if (String.isNotBlank(courseId)) {
            if (courseId.contains('|')) {
                // WHY '|' HERE: the Course combobox in the LWC sends one of two
                // shapes. When courses are merged across "All Divisions"
                // (loadCoursesForAllDivisions in the LWC), each option's value
                // is built as a composite "courseName|learningCourseId" string
                // specifically to dedupe the same course offered under
                // multiple divisions. When a single division is selected
                // instead, the value is just a plain Course Id with no pipe.
                // This block detects and unpacks the composite format; the
                // `else` branch below handles the plain-Id format.
                String[] parts = courseId.split('\\|');
                // split() takes a REGEX and '|' is a regex special character
                // (alternation), so it's escaped as '\\|' to split on a
                // literal pipe character.
                if (parts.size() > 1 && String.isNotBlank(parts[1])) {
                    try { courseLookupId = Id.valueOf(parts[1]); } catch (Exception e) {}
                }
            } else {
                try { courseLookupId = Id.valueOf(courseId); } catch (Exception e) {}
            }
        }

        // ---------- Resolve Division Ids ----------
        // NOTE: Apex does NOT support building a Set<Id> directly from a
        // List<String> — Id and String are only interchangeable at the
        // single-variable level (Id x = someString;), not at the generic
        // collection level. Set<Id>/List<Id> and Set<String>/List<String>
        // are distinct, incompatible types to the compiler, so this still
        // needs a per-element loop + Id.valueOf(). This is bulk-safe
        // regardless — it's plain in-memory iteration, not a SOQL query, so
        // no governor limits apply here.
        Set<Id> divisionIdSet = new Set<Id>();
        if (divisionIds != null && !divisionIds.isEmpty()) {
            for (String d : divisionIds) {
                if (String.isBlank(d)) continue;
                try {
                    divisionIdSet.add(Id.valueOf(d));
                } catch (Exception e) {
                    // Skip this one invalid entry rather than failing the
                    // whole report because of a single bad value.
                }
            }
        }

        // ---------- Resolve Session_Division__c junction data for the
        // selected division(s) ----------
        // REVIEW FIX: removed the separate `sessionIdsByDivision` Set — it was
        // redundant with sessionIdToDivisionNames.keySet() below. Only TWO
        // things are actually needed out of this query:
        //   1. sessionDivisionIdsForFilter — the JUNCTION RECORD Ids (not
        //      session Ids). This is what lets us later restrict
        //      Session_Enrollment__c to just the selected division(s), even
        //      when a session is a "combined session" spanning multiple
        //      divisions. This CANNOT be derived from the map below, since
        //      that map is keyed by Session Id, not by the junction record's
        //      own Id — that's why it still needs its own Set.
        //   2. sessionIdToDivisionNames — per session, the division name(s)
        //      to display in the report header. Its .keySet() doubles as
        //      "every session Id touched by the selected division(s)", so a
        //      separate session-Id Set is no longer needed at all.
        Set<Id> sessionDivisionIdsForFilter = new Set<Id>();
        Map<Id, Set<String>> sessionIdToDivisionNames = new Map<Id, Set<String>>();
        Set<Id> sessionIdsForQuery = new Set<Id>();

        if (!divisionIdSet.isEmpty()) {
            for (Session_Division__c sd : [
                SELECT Id, Session__c, Division__c, Division__r.Division_Name__c
                FROM Session_Division__c
                WHERE Division__c IN :divisionIdSet
                AND Division__r.IsActive__c = true
                // Only active divisions are considered when a division
                // filter is explicitly applied.
            ]) {
                sessionDivisionIdsForFilter.add(sd.Id);

                if (!sessionIdToDivisionNames.containsKey(sd.Session__c)) {
                    sessionIdToDivisionNames.put(sd.Session__c, new Set<String>());
                }
                if (String.isNotBlank(sd.Division__r?.Division_Name__c)) {
                    sessionIdToDivisionNames.get(sd.Session__c).add(sd.Division__r.Division_Name__c);
                }
            }

            sessionIdsForQuery = sessionIdToDivisionNames.keySet();
            if (sessionIdsForQuery.isEmpty()) {
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
        if (!sessionIdsForQuery.isEmpty())   conditions.add('Id IN :sessionIdsForQuery');
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
                if (!sessionIdToDivisionNames.containsKey(sd.Session__c)) {
                    sessionIdToDivisionNames.put(sd.Session__c, new Set<String>());
                }
                if (String.isNotBlank(sd.Division__r?.Division_Name__c)) {
                    sessionIdToDivisionNames.get(sd.Session__c).add(sd.Division__r.Division_Name__c);
                }
            }
        }

        // ---------- Faculty names per session ----------
        // REVIEW FIX: simplified to a single query using a relationship
        // traversal (Session_Faculty__r.Name) directly in the SOQL, and a
        // single loop building the final map — mirroring the same pattern
        // used above for division names. This removes the previous two-step
        // approach (collecting Account Ids, then querying Account
        // separately) since the faculty's Name can be pulled straight
        // through the relationship in one query.
        List<Session_Faculty__c> sessionFaculties = [
            SELECT Session__c, Session_Faculty__r.Name
            FROM Session_Faculty__c
            WHERE Session__c IN :sessionsById.keySet()
            AND Session_Faculty__c != null
        ];

        Map<Id, List<String>> facultyNamesBySession = new Map<Id, List<String>>();
        for (Session_Faculty__c sf : sessionFaculties) {
            String fname = sf.Session_Faculty__r?.Name;
            if (String.isBlank(fname)) continue;

            if (!facultyNamesBySession.containsKey(sf.Session__c)) {
                facultyNamesBySession.put(sf.Session__c, new List<String>());
            }
            facultyNamesBySession.get(sf.Session__c).add(fname);
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
        // FIX: when a division filter is in play (a single division, or
        // multiple divisions resolved from "All Divisions"), restrict
        // enrollments to only the Session_Division__c junction rows that
        // belong to that filter. Without this, a combined session spanning
        // Division A + B would return EVERY enrolled student from both
        // divisions regardless of which division the user actually selected.
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

        // Sort so students appear in a predictable, deterministic order.
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
                ? (Decimal.valueOf(absentCount) * 100 / studentTotalSessions).setScale(2)
                : 0;

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
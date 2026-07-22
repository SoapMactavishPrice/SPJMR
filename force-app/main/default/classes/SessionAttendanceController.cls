public without sharing class SessionAttendanceController {

    public class AttendanceRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String attendance;
        @AuraEnabled public String rollNumber;
        /** Account.Registration_Number__c via Academic Term Enrollment learner account */
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String remark;
        /** Session_Enrollment__c.Invite_Response__c — student's Google Calendar RSVP for the session. */
        @AuraEnabled public String inviteResponse;
        @AuraEnabled public String studentName;
        @AuraEnabled public String termCode;
        @AuraEnabled public String leaveType;
        @AuraEnabled public Id divisionEnrollmentId;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class SessionOption {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
        public SessionOption(Id value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    public class SessionSummary {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String sessionTitle;
        /** Learning course name from Session.Course__c */
        @AuraEnabled public String courseName;
        /** Picklist label for Session.Course_Activity__c (read-only UI). */
        @AuraEnabled public String courseActivityLabel;
        /** Comma-separated lead faculty (fallback: all faculty on session) */
        @AuraEnabled public String facultyNames;
        @AuraEnabled public Date sessionDate;
        @AuraEnabled public Id programId;
        @AuraEnabled public String programName;
        @AuraEnabled public Id batchId;
        @AuraEnabled public String batchName;
        @AuraEnabled public Id batchGroupId;
        @AuraEnabled public String batchGroupName;
        @AuraEnabled public Id termId;
        @AuraEnabled public String termName;
        @AuraEnabled public Id divisionId;
        @AuraEnabled public String divisionName;
        /** e.g. "10:00 AM – 11:00 AM" from Session Start_Time__c / End_Time__c */
        @AuraEnabled public String sessionTimeRange;
    }

    private static final String PROGRAM_ENROLLMENT_STATUS_WITHDRAWN = 'Withdrawn';

    /** Formats session wall-clock window for labels (uses running user timezone). */
    private static String buildSessionTimeRangeLabel(Datetime startDt, Datetime endDt) {
        if (startDt == null && endDt == null) {
            return null;
        }
        String startStr = startDt != null ? startDt.format('h:mm a') : '—';
        String endStr = endDt != null ? endDt.format('h:mm a') : '—';
        return startStr + ' – ' + endStr;
    }

    /** e.g. 20-Apr-2026 */
    private static String buildSessionDateLabel(Date d) {
        if (d == null) {
            return '—';
        }
        Datetime dt = Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
        return dt.format('dd-MMM-yyyy');
    }

    /** Picklist display label for Session.Course_Activity__c; falls back to API value if not found. */
    private static String sessionCourseActivityLabel(Session__c sess) {
        if (sess == null) {
            return null;
        }
        Object raw = sess.get('Course_Activity__c');
        if (raw == null) {
            return null;
        }
        String api = String.valueOf(raw);
        if (String.isBlank(api)) {
            return null;
        }
        Schema.DescribeFieldResult dfr = Session__c.Course_Activity__c.getDescribe();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.getValue() == api) {
                return pe.getLabel();
            }
        }
        return api;
    }

    /** Program / batch / term / division context for one session enrollment row (from Division_Enrollment or Session_Division). */
    private class DivisionRefIds {
        Id programId;
        Id batchId;
        Id batchGroupId;
        Id termId;
        Id divisionId;
    }

    /**
     * Resolves program/batch/batch group/term/division from Division_Enrollment__r first, else Session_Division__r.
     */
    private static DivisionRefIds getDivisionRefIds(Session_Enrollment__c se) {
        Division__c div = null;
        if (se.Division_Enrollment__r != null && se.Division_Enrollment__r.Division__r != null) {
            div = se.Division_Enrollment__r.Division__r;
        } else if (se.Session_Division__r != null && se.Session_Division__r.Division__r != null) {
            div = se.Session_Division__r.Division__r;
        }
        if (div == null) {
            return null;
        }
        DivisionRefIds outRef = new DivisionRefIds();
        outRef.divisionId = div.Id;
        outRef.termId = div.Term__c;
        if (div.Term__r != null) {
            outRef.batchGroupId = div.Term__r.AcademicYearId;
            if (div.Term__r.AcademicYear != null) {
                outRef.batchId = div.Term__r.AcademicYear.Batch__c;
                if (div.Term__r.AcademicYear.Batch__r != null) {
                    outRef.programId = div.Term__r.AcademicYear.Batch__r.ProgramId;
                }
            }
        }
        return outRef;
    }

    private static Boolean matchesEnrollmentFilters(
        Session_Enrollment__c se,
        Id programId,
        Id batchId,
        Id batchGroupId,
        Id termId,
        Id divisionId
    ) {
        Boolean anyFilter =
            programId != null ||
            batchId != null ||
            batchGroupId != null ||
            termId != null ||
            divisionId != null;
        DivisionRefIds refIds = getDivisionRefIds(se);
        if (refIds == null) {
            return !anyFilter;
        }
        if (programId != null && refIds.programId != programId) {
            return false;
        }
        if (batchId != null && refIds.batchId != batchId) {
            return false;
        }
        if (batchGroupId != null && refIds.batchGroupId != batchGroupId) {
            return false;
        }
        if (termId != null && refIds.termId != termId) {
            return false;
        }
        if (divisionId != null && refIds.divisionId != divisionId) {
            return false;
        }
        return true;
    }

    private static Boolean isWithdrawnProgramEnrollment(Session_Enrollment__c se) {
        if (se.Academic_Term_Enrollment__r == null || se.Academic_Term_Enrollment__r.Program_Enrolled__r == null) {
            return false;
        }
        return se.Academic_Term_Enrollment__r.Program_Enrolled__r.Status == PROGRAM_ENROLLMENT_STATUS_WITHDRAWN;
    }

    /**
     * Session attendance rows for a session, optionally narrowed by program/batch/batch group/term/division
     * (same hierarchy as session picker filters). Withdrawn program enrollments are excluded.
     */
    @AuraEnabled
    public static List<AttendanceRow> getSessionEnrollments(
        Id sessionId,
        Long refreshToken,
        Id programId,
        Id batchId,
        Id batchGroupId,
        Id termId,
        Id divisionId
    ) {
        if (sessionId == null) {
            throw new AuraHandledException('Session Id is required.');
        }

        List<Session_Enrollment__c> candidates = [
            SELECT Id,
                   Attendance__c,
                   Roll_Number__c,
                   Remark__c,
                   Invite_Response__c,
                   Student_Name__c,
                   Term_Code__c,
                   Division_Enrollment__c,
                   Leave_Type__c,
                   Academic_Term_Enrollment__r.LearnerAccount.Registration_Number__c,
                   Academic_Term_Enrollment__r.Program_Enrolled__r.Status,
                   Division_Enrollment__r.Division__c,
                   Division_Enrollment__r.Division__r.Term__c,
                   Division_Enrollment__r.Division__r.Term__r.AcademicYearId,
                   Division_Enrollment__r.Division__r.Term__r.AcademicYear.Batch__c,
                   Division_Enrollment__r.Division__r.Term__r.AcademicYear.Batch__r.ProgramId,
                   Session_Division__c,
                   Session_Division__r.Division__c,
                   Session_Division__r.Division__r.Term__c,
                   Session_Division__r.Division__r.Term__r.AcademicYearId,
                   Session_Division__r.Division__r.Term__r.AcademicYear.Batch__c,
                   Session_Division__r.Division__r.Term__r.AcademicYear.Batch__r.ProgramId
            FROM Session_Enrollment__c
            WHERE Session__c = :sessionId
            ORDER BY Roll_Number__c NULLS LAST, Student_Name__c NULLS LAST
        ];

        List<AttendanceRow> rows = new List<AttendanceRow>();
        for (Session_Enrollment__c se : candidates) {
            if (isWithdrawnProgramEnrollment(se)) {
                continue;
            }
            if (!matchesEnrollmentFilters(se, programId, batchId, batchGroupId, termId, divisionId)) {
                continue;
            }
            AttendanceRow r = new AttendanceRow();
            r.id = se.Id;
            r.attendance = se.Attendance__c;
            r.rollNumber = se.Roll_Number__c;
            r.registrationNumber = (se.Academic_Term_Enrollment__r != null
                && se.Academic_Term_Enrollment__r.LearnerAccount != null)
                ? se.Academic_Term_Enrollment__r.LearnerAccount.Registration_Number__c
                : null;
            r.remark = se.Remark__c;
            r.inviteResponse = se.Invite_Response__c;
            r.studentName = se.Student_Name__c;
            r.termCode = se.Term_Code__c;
            r.leaveType = se.Leave_Type__c;
            r.divisionEnrollmentId = se.Division_Enrollment__c;
            rows.add(r);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getAttendanceOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        Schema.DescribeFieldResult dfr = Session_Enrollment__c.Attendance__c.getDescribe();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            options.add(new PicklistOption(pe.getLabel(), pe.getValue()));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<SessionOption> getSessionOptions(
        Id programId,
        Id batchId,
        Id batchGroupId,
        Id termId,
        Id divisionId,
        String sessionDate
    ) {
        List<SessionOption> options = new List<SessionOption>();
        Map<Id, String> labelById = new Map<Id, String>();
        Date filterSessionDate = null;
        if (!String.isBlank(sessionDate)) {
            try {
                filterSessionDate = Date.valueOf(sessionDate);
            } catch (Exception e) {
                throw new AuraHandledException('Invalid session date filter.');
            }
        }

        List<Session_Division__c> links = [
            SELECT Session__c,
                   Session__r.Name,
                   Session__r.Session_Date__c,
                   Session__r.Start_Time__c,
                   Session__r.End_Time__c,
                   Session__r.Course__r.Name,
                   Division__c,
                   Division__r.Division_Name__c,
                   Division__r.Term__c,
                   Division__r.Term__r.Name,
                   Division__r.Term__r.AcademicYearId,
                   Division__r.Term__r.AcademicYear.Name,
                   Division__r.Term__r.AcademicYear.Batch__c,
                   Division__r.Term__r.AcademicYear.Batch__r.Name,
                   Division__r.Term__r.AcademicYear.Batch__r.ProgramId,
                   Division__r.Term__r.AcademicYear.Batch__r.Program.Name
            FROM Session_Division__c
            WHERE Session__c != null
            ORDER BY Session__r.Session_Date__c DESC, Session__r.Start_Time__c DESC
        ];

        for (Session_Division__c sd : links) {
            if (programId != null && sd.Division__r.Term__r.AcademicYear.Batch__r.ProgramId != programId) continue;
            if (batchId != null && sd.Division__r.Term__r.AcademicYear.Batch__c != batchId) continue;
            if (batchGroupId != null && sd.Division__r.Term__r.AcademicYearId != batchGroupId) continue;
            if (termId != null && sd.Division__r.Term__c != termId) continue;
            if (divisionId != null && sd.Division__c != divisionId) continue;
            if (filterSessionDate != null && sd.Session__r.Session_Date__c != filterSessionDate) continue;
            if (labelById.containsKey(sd.Session__c)) continue;

            // Dropdown label: Session Name / Course Name / Date / Time Range
            String courseName = '—';
            if (sd.Session__r != null && sd.Session__r.Course__r != null && String.isNotBlank(sd.Session__r.Course__r.Name)) {
                courseName = sd.Session__r.Course__r.Name.trim();
            }
            String sessionName = (sd.Session__r != null && String.isNotBlank(sd.Session__r.Name)) ? sd.Session__r.Name.trim() : 'Session';
            String datePart = (sd.Session__r != null)
                ? buildSessionDateLabel(sd.Session__r.Session_Date__c)
                : '—';
            String title = sessionName + ' / ' + courseName + ' / ' + datePart;
            if (sd.Session__r != null) {
                String timeRange = buildSessionTimeRangeLabel(
                    sd.Session__r.Start_Time__c,
                    sd.Session__r.End_Time__c
                );
                if (String.isNotBlank(timeRange)) {
                    title = title + ' / ' + timeRange;
                }
            }
            labelById.put(sd.Session__c, title);
        }

        for (Id sid : labelById.keySet()) {
            options.add(new SessionOption(sid, labelById.get(sid)));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static SessionSummary getSessionSummary(Id sessionId, Id divisionId) {
        if (sessionId == null) return null;

        List<Session_Division__c> links;
        if (divisionId != null) {
            links = [
                SELECT Session__c,
                       Session__r.Name,
                       Session__r.Session_Date__c,
                       Session__r.Start_Time__c,
                       Session__r.End_Time__c,
                       Session__r.Course_Activity__c,
                       Session__r.Course__r.Name,
                       Division__c,
                       Division__r.Division_Name__c,
                       Division__r.Term__c,
                       Division__r.Term__r.Name,
                       Division__r.Term__r.AcademicYearId,
                       Division__r.Term__r.AcademicYear.Name,
                       Division__r.Term__r.AcademicYear.Batch__c,
                       Division__r.Term__r.AcademicYear.Batch__r.Name,
                       Division__r.Term__r.AcademicYear.Batch__r.ProgramId,
                       Division__r.Term__r.AcademicYear.Batch__r.Program.Name
                FROM Session_Division__c
                WHERE Session__c = :sessionId
                AND Division__c = :divisionId
                LIMIT 1
            ];
        } else {
            links = [
                SELECT Session__c,
                       Session__r.Name,
                       Session__r.Session_Date__c,
                       Session__r.Start_Time__c,
                       Session__r.End_Time__c,
                       Session__r.Course_Activity__c,
                       Session__r.Course__r.Name,
                       Division__c,
                       Division__r.Division_Name__c,
                       Division__r.Term__c,
                       Division__r.Term__r.Name,
                       Division__r.Term__r.AcademicYearId,
                       Division__r.Term__r.AcademicYear.Name,
                       Division__r.Term__r.AcademicYear.Batch__c,
                       Division__r.Term__r.AcademicYear.Batch__r.Name,
                       Division__r.Term__r.AcademicYear.Batch__r.ProgramId,
                       Division__r.Term__r.AcademicYear.Batch__r.Program.Name
                FROM Session_Division__c
                WHERE Session__c = :sessionId
                LIMIT 1
            ];
        }
        if (links.isEmpty()) return null;

        Session_Division__c sd = links[0];
        SessionSummary s = new SessionSummary();
        s.sessionId = sessionId;
        s.sessionTitle = sd.Session__r != null ? sd.Session__r.Name : null;
        s.courseName = (sd.Session__r != null && sd.Session__r.Course__r != null) ? sd.Session__r.Course__r.Name : null;
        s.courseActivityLabel = sessionCourseActivityLabel(sd.Session__r);
        s.sessionDate = sd.Session__r != null ? sd.Session__r.Session_Date__c : null;
        if (sd.Session__r != null) {
            s.sessionTimeRange = buildSessionTimeRangeLabel(
                sd.Session__r.Start_Time__c,
                sd.Session__r.End_Time__c
            );
        }
        s.programId = sd.Division__r.Term__r.AcademicYear.Batch__r.ProgramId;
        s.programName = sd.Division__r.Term__r.AcademicYear.Batch__r.Program.Name;
        s.batchId = sd.Division__r.Term__r.AcademicYear.Batch__c;
        s.batchName = sd.Division__r.Term__r.AcademicYear.Batch__r.Name;
        s.batchGroupId = sd.Division__r.Term__r.AcademicYearId;
        s.batchGroupName = sd.Division__r.Term__r.AcademicYear.Name;
        s.termId = sd.Division__r.Term__c;
        s.termName = sd.Division__r.Term__r.Name;
        s.divisionId = sd.Division__c;
        s.divisionName = sd.Division__r.Division_Name__c;
        s.facultyNames = buildFacultyNamesForSession(sessionId);
        return s;
    }

    /**
     * Lead faculty names first (comma-separated); if none, all faculty on the session.
     * Resolves Session_Faculty__c against Account then User (same pattern as TimetableSessionController).
     */
    private static String buildFacultyNamesForSession(Id sessionId) {
        if (sessionId == null) {
            return null;
        }
        List<Session_Faculty__c> sfs = [
            SELECT Session_Faculty__c, Faculty_Type__c
            FROM Session_Faculty__c
            WHERE Session__c = :sessionId
            AND Session_Faculty__c != NULL
        ];
        if (sfs.isEmpty()) {
            return null;
        }
        Set<Id> facultyIds = new Set<Id>();
        List<Session_Faculty__c> leads = new List<Session_Faculty__c>();
        List<Session_Faculty__c> others = new List<Session_Faculty__c>();
        for (Session_Faculty__c sf : sfs) {
            facultyIds.add(sf.Session_Faculty__c);
            if (sf.Faculty_Type__c == 'Lead') {
                leads.add(sf);
            } else {
                others.add(sf);
            }
        }
        Map<Id, String> idToName = new Map<Id, String>();
        if (!facultyIds.isEmpty()) {
            for (Account a : [SELECT Id, Name FROM Account WHERE Id IN :facultyIds]) {
                idToName.put(a.Id, a.Name);
            }
            Set<Id> missing = new Set<Id>();
            for (Id fid : facultyIds) {
                if (!idToName.containsKey(fid)) {
                    missing.add(fid);
                }
            }
            if (!missing.isEmpty()) {
                for (User u : [SELECT Id, Name FROM User WHERE Id IN :missing]) {
                    idToName.put(u.Id, u.Name);
                }
            }
        }
        List<String> orderedNames = new List<String>();
        for (Session_Faculty__c sf : leads) {
            String nm = idToName.get(sf.Session_Faculty__c);
            if (String.isNotBlank(nm)) {
                orderedNames.add(nm.trim());
            }
        }
        for (Session_Faculty__c sf : others) {
            String nm = idToName.get(sf.Session_Faculty__c);
            if (String.isNotBlank(nm)) {
                orderedNames.add(nm.trim());
            }
        }
        if (orderedNames.isEmpty()) {
            return null;
        }
        return String.join(orderedNames, ', ');
    }

    @AuraEnabled
    public static void updateSessionEnrollments(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('No attendance updates were provided.');
        }

        List<AttendanceRow> updates = (List<AttendanceRow>) JSON.deserialize(payloadJson, List<AttendanceRow>.class);
        if (updates == null || updates.isEmpty()) {
            throw new AuraHandledException('No attendance updates were provided.');
        }

        Map<Id, AttendanceRow> rowById = new Map<Id, AttendanceRow>();
        for (AttendanceRow row : updates) {
            if (row != null && row.id != null) {
                rowById.put(row.id, row);
            }
        }
        if (rowById.isEmpty()) {
            throw new AuraHandledException('No valid attendance records to update.');
        }

        List<Session_Enrollment__c> records = [
            SELECT Id, Attendance__c, Remark__c, Leave_Type__c, Session__r.Session_Date__c
            FROM Session_Enrollment__c
            WHERE Id IN :rowById.keySet()
            FOR UPDATE
        ];

        Date today = Date.today();
        for (Session_Enrollment__c rec : records) {
            if (rec.Session__r != null && rec.Session__r.Session_Date__c != null && rec.Session__r.Session_Date__c > today) {
                throw new AuraHandledException('Attendance cannot be updated for future sessions.');
            }
        }

        String sanctionedLeave = 'Sanctioned Leave';

        List<Session_Enrollment__c> toUpdate = new List<Session_Enrollment__c>();
        for (Session_Enrollment__c rec : records) {
            AttendanceRow input = rowById.get(rec.Id);
            if (input == null) continue;

            String newAttendance = input.attendance;
            String newRemark = input.remark;

            rec.Attendance__c = newAttendance;
            rec.Remark__c = newRemark;
            if (newAttendance == sanctionedLeave) {
                rec.Leave_Type__c = String.isBlank(input.leaveType) ? null : input.leaveType;
            } else {
                rec.Leave_Type__c = null;
            }
            toUpdate.add(rec);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
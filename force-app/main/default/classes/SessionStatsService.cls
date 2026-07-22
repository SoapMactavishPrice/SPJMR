/**
 * Computes session status counts (published, completed, republished, cancelled) for record pages:
 * course, batch, instructor, course offering, academic term, and course instructor (faculty + course).
 */
public with sharing class SessionStatsService {

    // -------------------------
    // DTO
    // -------------------------
    public class SessionStats {
        @AuraEnabled public Integer published = 0;
        @AuraEnabled public Integer completed = 0;
        @AuraEnabled public Integer republished = 0;
        @AuraEnabled public Integer cancelled = 0;
        /** When context is AcademicTerm and term is not complete, show this message instead of stats. */
        @AuraEnabled public Boolean isTermComplete;
        @AuraEnabled public String termCompletionMessage;
    }

    public class SessionDetailRow {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String sessionName;
        @AuraEnabled public String courseName;
        @AuraEnabled public Date sessionDate;
        @AuraEnabled public Datetime sessionTime;
        /** End_Time__c; paired with sessionTime for display as start – end. */
        @AuraEnabled public Datetime sessionEndTime;
        @AuraEnabled public String room;
        @AuraEnabled public String remarks;
        @AuraEnabled public String url;
    }

    // -------------------------
    // Entry point
    // -------------------------
    @AuraEnabled(cacheable=true)
    public static SessionStats getSessionStats(Id recordId) {

        String objectName = recordId.getSObjectType().getDescribe().getName();
        List<Session__c> sessions = new List<Session__c>();
        SessionStats result;

        if (objectName == 'LearningCourse') {
            sessions = getByCourse(recordId);
            result = buildStats(sessions);

        } else if (objectName == 'ProgramCohort') {
            sessions = getByBatch(recordId);
            result = buildStats(sessions);

        } else if (objectName == 'Instructor__c') {
            sessions = getByInstructor(recordId);
            result = buildStats(sessions);

        } else if (objectName == 'CourseOffering') {
            sessions = getByCourseOffering(recordId);
            result = buildStats(sessions);

        } else if (objectName == 'AcademicTerm') {
            result = getStatsForAcademicTerm(recordId);

        } else if (objectName == 'Course_Instructor__c') {
            sessions = getByCourseInstructor(recordId);
            result = buildStats(sessions);

        } else {
            throw new AuraHandledException('Unsupported record type');
        }

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<SessionDetailRow> getSessionsByStatus(Id recordId, String statusKey) {
        List<Session__c> sessions = getSessionsForScope(recordId);
        return buildDetailsByStatus(sessions, statusKey);
    }

    // -------------------------
    // Query helpers
    // -------------------------

    /**
     * Sessions for a Course Instructor row: same LearningCourse and the faculty (Account) assigned on Session Faculty.
     *
     * @param courseInstructorId Course_Instructor__c Id (Faculty__c = Account, Course__c = LearningCourse).
     * @return Matching sessions; empty if lookups are null or record not found.
     */
    private static List<Session__c> getByCourseInstructor(Id courseInstructorId) {
        List<Course_Instructor__c> rows = [
            SELECT Faculty__c, Course__c
            FROM Course_Instructor__c
            WHERE Id = :courseInstructorId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return new List<Session__c>();
        }
        Id facultyAccountId = rows[0].Faculty__c;
        Id courseId = rows[0].Course__c;
        if (facultyAccountId == null || courseId == null) {
            return new List<Session__c>();
        }
        return [
            SELECT Id, Schedule_Type__c, Is_Completed__c
            FROM Session__c
            WHERE Course__c = :courseId
            AND Id IN (
                SELECT Session__c
                FROM Session_Faculty__c
                WHERE Session_Faculty__c = :facultyAccountId
            )
        ];
    }

    private static List<Session__c> getByCourse(Id courseId) {
        return [
            SELECT Id, Schedule_Type__c,Is_Completed__c
            FROM Session__c
            WHERE Course__c = :courseId
        ];
    }

    private static List<Session__c> getByBatch(Id cohortId) {
        List<Session__c> sessions = new List<Session__c>();

        for (Session_Division__c sd : [
            SELECT Session__r.Id, Session__r.Schedule_Type__c,Session__r.Is_Completed__c
            FROM Session_Division__c
            WHERE Division__r.Term__r.AcademicYear.Batch__c = :cohortId
        ]) {
            sessions.add(sd.Session__r);
        }

        return sessions;
    }

    private static List<Session__c> sessionsForFacultyAccount(Id facultyAccountId) {
        List<Session__c> sessions = new List<Session__c>();
        if (facultyAccountId == null) {
            return sessions;
        }
        for (Session_Faculty__c sf : [
            SELECT Session__r.Id, Session__r.Schedule_Type__c, Session__r.Is_Completed__c
            FROM Session_Faculty__c
            WHERE Session_Faculty__c = :facultyAccountId
        ]) {
            sessions.add(sf.Session__r);
        }
        return sessions;
    }

    private static List<Session__c> getByInstructor(Id instructorId) {
        Instructor__c instructor = [SELECT Account__c FROM Instructor__c WHERE Id = :instructorId LIMIT 1];
        return sessionsForFacultyAccount(instructor.Account__c);
    }

    /** Sessions for a CourseOffering: by LearningCourseId and optionally scoped to the offering's Academic Term divisions. */
    private static List<Session__c> getByCourseOffering(Id courseOfferingId) {
        List<CourseOffering> offerings = [
            SELECT LearningCourseId, Academic_Term__c
            FROM CourseOffering
            WHERE Id = :courseOfferingId
            AND LearningCourseId != null
            LIMIT 1
        ];
        if (offerings.isEmpty()) {
            return new List<Session__c>();
        }
        Id learningCourseId = offerings[0].LearningCourseId;
        Id academicTermId = offerings[0].Academic_Term__c;

        if (academicTermId == null) {
            return getByCourse(learningCourseId);
        }

        Set<Id> divisionIds = new Set<Id>();
        for (Division__c div : [
            SELECT Id
            FROM Division__c
            WHERE Term__c = :academicTermId
        ]) {
            divisionIds.add(div.Id);
        }
        if (divisionIds.isEmpty()) {
            return new List<Session__c>();
        }

        return [
            SELECT Id, Schedule_Type__c, Is_Completed__c
            FROM Session__c
            WHERE Course__c = :learningCourseId
            AND Id IN (SELECT Session__c FROM Session_Division__c WHERE Division__c IN :divisionIds)
        ];
    }

    /** Sessions for an AcademicTerm: all sessions linked to divisions that belong to this term. */
    private static List<Session__c> getByAcademicTerm(Id academicTermId) {
        Set<Id> divisionIds = new Set<Id>();
        for (Division__c div : [
            SELECT Id
            FROM Division__c
            WHERE Term__c = :academicTermId
        ]) {
            divisionIds.add(div.Id);
        }
        if (divisionIds.isEmpty()) {
            return new List<Session__c>();
        }
        List<Session__c> sessions = new List<Session__c>();
        for (Session_Division__c sd : [
            SELECT Session__r.Id, Session__r.Schedule_Type__c, Session__r.Is_Completed__c
            FROM Session_Division__c
            WHERE Division__c IN :divisionIds
        ]) {
            sessions.add(sd.Session__r);
        }
        return sessions;
    }

    /** Returns SessionStats for AcademicTerm; when term is not complete, returns message only (zeroed stats). */
    private static SessionStats getStatsForAcademicTerm(Id academicTermId) {
        Boolean isComplete = false;
        try {
            AcademicTerm term = [SELECT Is_Complete__c FROM AcademicTerm WHERE Id = :academicTermId LIMIT 1];
            isComplete = term.Is_Complete__c == true;
        } catch (Exception e) {
            // If field missing or not accessible, treat as not complete
        }
        if (!isComplete) {
            SessionStats stats = new SessionStats();
            stats.isTermComplete = false;
            stats.termCompletionMessage = 'The session metrics are available once the term is completed.';
            return stats;
        }
        List<Session__c> sessions = getByAcademicTerm(academicTermId);
        SessionStats stats = buildStats(sessions);
        stats.isTermComplete = true;
        stats.termCompletionMessage = null;
        return stats;
    }

    private static List<Session__c> getSessionsForScope(Id recordId) {
        String objectName = recordId.getSObjectType().getDescribe().getName();
        if (objectName == 'LearningCourse') {
            return getByCourseDetails(recordId);
        } else if (objectName == 'ProgramCohort') {
            return getByBatchDetails(recordId);
        } else if (objectName == 'Instructor__c') {
            return getByInstructorDetails(recordId);
        } else if (objectName == 'CourseOffering') {
            return getByCourseOfferingDetails(recordId);
        } else if (objectName == 'AcademicTerm') {
            return getByAcademicTermDetails(recordId);
        } else if (objectName == 'Course_Instructor__c') {
            return getByCourseInstructorDetails(recordId);
        }
        throw new AuraHandledException('Unsupported record type');
    }

    private static List<Session__c> getSessionsByIds(Set<Id> sessionIds) {
        if (sessionIds == null || sessionIds.isEmpty()) {
            return new List<Session__c>();
        }
        return [
            SELECT Id, Name, Schedule_Type__c, Is_Completed__c, Course__c,
                   Session_Date__c, Start_Time__c, End_Time__c, Class_Room__c, Remark__c, URL__c
            FROM Session__c
            WHERE Id IN :sessionIds
            ORDER BY Session_Date__c DESC, Start_Time__c DESC
        ];
    }

    private static List<Session__c> getByCourseDetails(Id courseId) {
        Set<Id> ids = new Set<Id>();
        for (Session__c s : getByCourse(courseId)) {
            ids.add(s.Id);
        }
        return getSessionsByIds(ids);
    }

    private static List<Session__c> getByBatchDetails(Id cohortId) {
        Set<Id> ids = new Set<Id>();
        for (Session__c s : getByBatch(cohortId)) {
            ids.add(s.Id);
        }
        return getSessionsByIds(ids);
    }

    private static List<Session__c> getByInstructorDetails(Id instructorId) {
        Set<Id> ids = new Set<Id>();
        for (Session__c s : getByInstructor(instructorId)) {
            ids.add(s.Id);
        }
        return getSessionsByIds(ids);
    }

    private static List<Session__c> getByCourseInstructorDetails(Id courseInstructorId) {
        Set<Id> ids = new Set<Id>();
        for (Session__c s : getByCourseInstructor(courseInstructorId)) {
            ids.add(s.Id);
        }
        return getSessionsByIds(ids);
    }

    private static List<Session__c> getByCourseOfferingDetails(Id courseOfferingId) {
        Set<Id> ids = new Set<Id>();
        for (Session__c s : getByCourseOffering(courseOfferingId)) {
            ids.add(s.Id);
        }
        return getSessionsByIds(ids);
    }

    private static List<Session__c> getByAcademicTermDetails(Id academicTermId) {
        Set<Id> ids = new Set<Id>();
        for (Session__c s : getByAcademicTerm(academicTermId)) {
            ids.add(s.Id);
        }
        return getSessionsByIds(ids);
    }

    private static List<SessionDetailRow> buildDetailsByStatus(List<Session__c> sessions, String statusKey) {
        List<SessionDetailRow> rows = new List<SessionDetailRow>();
        if (sessions == null || sessions.isEmpty()) {
            return rows;
        }

        Set<Id> courseIds = new Set<Id>();
        for (Session__c s : sessions) {
            if (s.Course__c != null) {
                courseIds.add(s.Course__c);
            }
        }

        Map<Id, String> courseNames = new Map<Id, String>();
        for (LearningCourse c : [SELECT Id, Name FROM LearningCourse WHERE Id IN :courseIds]) {
            courseNames.put(c.Id, c.Name);
        }

        for (Session__c s : sessions) {
            if (!matchesStatus(s, statusKey)) {
                continue;
            }
            SessionDetailRow row = new SessionDetailRow();
            row.sessionId = s.Id;
            row.sessionName = s.Name;
            row.courseName = courseNames.get(s.Course__c);
            row.sessionDate = s.Session_Date__c;
            row.sessionTime = s.Start_Time__c;
            row.sessionEndTime = s.End_Time__c;
            row.room = s.Class_Room__c;
            row.remarks = s.Remark__c;
            row.url = s.URL__c;
            rows.add(row);
        }
        return rows;
    }

    private static Boolean matchesStatus(Session__c s, String statusKey) {
        if (s == null || String.isBlank(statusKey)) {
            return false;
        }
        String key = statusKey.trim().toLowerCase();
        if (key == 'published') {
            return s.Schedule_Type__c == 'Published' && s.Is_Completed__c == false;
        }
        if (key == 'republished' || key == 'rescheduled') {
            return s.Schedule_Type__c == 'Republished' && s.Is_Completed__c == false;
        }
        if (key == 'cancelled' || key == 'canceled') {
            return s.Schedule_Type__c == 'Cancelled' && s.Is_Completed__c == false;
        }
        if (key == 'completed') {
            return s.Is_Completed__c == true;
        }
        return false;
    }

    // -------------------------
    // Aggregation
    // -------------------------
    private static SessionStats buildStats(List<Session__c> sessions) {

        SessionStats stats = new SessionStats();
        Set<Id> seenSessionIds = new Set<Id>();

        for (Session__c s : sessions) {
            if (s == null || s.Id == null || seenSessionIds.contains(s.Id)) {
                continue;
            }
            seenSessionIds.add(s.Id);
            if (s.Schedule_Type__c == 'Published' && s.Is_Completed__c == false) {
                stats.published++;
            } else if (s.Schedule_Type__c == 'Republished' && s.Is_Completed__c == false) {
                stats.republished++;
            } else if (s.Schedule_Type__c == 'Cancelled' && s.Is_Completed__c == false) {
                stats.cancelled++;
            } else if (s.Is_Completed__c == true) {
                stats.completed++;
            }
        }

        return stats;
    }
}
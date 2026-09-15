public without sharing class SessionAssignmentQueueable implements Queueable {

    @TestVisible
    private static final Integer MAX_ATTEMPTS = 3;
    @TestVisible
    private static Integer DML_CHUNK_SIZE = 7000;
    private static final String STATUS_WITHDRAWN = 'Withdrawn';
    private static final String STATUS_CANCELLED = 'Cancelled';
    private static final Integer NAME_MAX_LENGTH = 80;

    @TestVisible
    private static Boolean lastSuppressValueDuringInsert;
    @TestVisible
    private static Boolean calendarPushInvoked;
    @TestVisible
    private static Set<Id> lastCalendarSessionIds;

    private final Set<Id> enrollmentIds;
    private final Integer attempt;

    public SessionAssignmentQueueable(Set<Id> enrollmentIds) {
        this(enrollmentIds, 1);
    }

    public SessionAssignmentQueueable(Set<Id> enrollmentIds, Integer attempt) {
        this.enrollmentIds = (enrollmentIds == null) ? new Set<Id>() : enrollmentIds;
        this.attempt = (attempt == null) ? 1 : attempt;
    }

    public void execute(QueueableContext context) {
        if (enrollmentIds.isEmpty()) {
            return;
        }
        List<Session_Enrollment__c> toInsert = buildAssignments(enrollmentIds);
        if (toInsert.isEmpty()) {
            return;
        }

        Integer chunkSize = (DML_CHUNK_SIZE == null || DML_CHUNK_SIZE < 1) ? 7000 : DML_CHUNK_SIZE;
        Boolean hasMore = toInsert.size() > chunkSize;
        List<Session_Enrollment__c> chunk = hasMore
            ? sliceAssignments(toInsert, chunkSize)
            : toInsert;

        Boolean priorSuppress = SessionCalendarInviteHandler.suppressInvites;
        SessionCalendarInviteHandler.suppressInvites = true;
        lastSuppressValueDuringInsert = SessionCalendarInviteHandler.suppressInvites;
        try {
            insert chunk;
        } catch (Exception e) {
            SessionCalendarInviteHandler.suppressInvites = priorSuppress;
            if (shouldRetry(e, attempt)
                    && !Test.isRunningTest()
                    && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new SessionAssignmentQueueable(enrollmentIds, attempt + 1));
                return;
            }
            throw e;
        } finally {
            SessionCalendarInviteHandler.suppressInvites = priorSuppress;
        }

        if (hasMore) {
            if (!Test.isRunningTest()) {
                enqueueContinuation();
            }
        } else {
            pushCalendarForAssignedSessions();
        }
    }

    private void enqueueContinuation() {
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            throw new SessionAssignmentException(
                'Session assignment partially completed but could not enqueue continuation '
                + '(queueable limit). EnrollmentIds=' + enrollmentIds.size()
            );
        }
        System.enqueueJob(new SessionAssignmentQueueable(enrollmentIds, 1));
    }

    @TestVisible
    private void pushCalendarForAssignedSessions() {
        if (enrollmentIds == null || enrollmentIds.isEmpty()) {
            return;
        }
        Set<Id> sessionIds = new Set<Id>();
        for (Session_Enrollment__c se : [
            SELECT Session__c
            FROM Session_Enrollment__c
            WHERE Division_Enrollment__c IN :enrollmentIds
              AND Session__c != null
              AND (
                    Session__r.Google_Event_Id__c != null
                 OR Session__r.Faculty_Google_Event_Id__c != null
              )
              AND Session__r.Schedule_Type__c IN ('Published', 'Republished', 'Rescheduled', 'Draft')
        ]) {
            sessionIds.add(se.Session__c);
        }
        calendarPushInvoked = true;
        lastCalendarSessionIds = sessionIds;
        if (sessionIds.isEmpty()) {
            return;
        }
        SessionCalendarInviteHandler.handleRelatedRecordChange(sessionIds);
    }

    @TestVisible
    private static List<Session_Enrollment__c> sliceAssignments(
        List<Session_Enrollment__c> source,
        Integer chunkSize
    ) {
        List<Session_Enrollment__c> chunk = new List<Session_Enrollment__c>();
        Integer limitSize = Math.min(chunkSize, source.size());
        for (Integer i = 0; i < limitSize; i++) {
            chunk.add(source[i]);
        }
        return chunk;
    }

    public class SessionAssignmentException extends Exception {}

    @TestVisible
    private static List<Session_Enrollment__c> buildAssignments(Set<Id> enrollmentIds) {
        List<Session_Enrollment__c> result = new List<Session_Enrollment__c>();
        if (enrollmentIds == null || enrollmentIds.isEmpty()) {
            return result;
        }
        List<Division_Enrollment__c> details = loadEnrollmentDetails(enrollmentIds);
        Set<Id> divisionIds = new Set<Id>();
        Set<Id> termEnrollmentIds = new Set<Id>();
        collectDivisionAndTermIds(details, divisionIds, termEnrollmentIds);
        if (divisionIds.isEmpty()) {
            return result;
        }
        Map<Id, List<Session_Division__c>> sdByDivision = loadSessionDivisions(divisionIds);
        if (sdByDivision.isEmpty()) {
            return result;
        }
        Set<Id> sessionIds = collectSessionIds(sdByDivision);
        Set<String> existingKeys = loadExistingKeys(sessionIds, termEnrollmentIds);
        return buildEnrollments(details, sdByDivision, existingKeys);
    }

    @TestVisible
    private static Boolean shouldRetry(Exception e, Integer attempt) {
        return attempt < MAX_ATTEMPTS && isRetryable(e);
    }

    private static Boolean isRetryable(Exception e) {
        String msg = (e != null && e.getMessage() != null) ? e.getMessage() : '';
        return msg.contains('UNABLE_TO_LOCK_ROW')
            || msg.containsIgnoreCase('unable to obtain exclusive access');
    }

    private static List<Division_Enrollment__c> loadEnrollmentDetails(Set<Id> enrollmentIds) {
        return [
            SELECT Id, Division__c, Academic_Term_Enrollment__c,
                   Academic_Term_Enrollment__r.Program_Enrolled__c,
                   Academic_Term_Enrollment__r.Program_Enrolled__r.Status,
                   Academic_Term_Enrollment__r.LearnerAccount.FirstName,
                   Academic_Term_Enrollment__r.LearnerAccount.LastName
            FROM Division_Enrollment__c
            WHERE Id IN :enrollmentIds
        ];
    }

    private static void collectDivisionAndTermIds(
        List<Division_Enrollment__c> details,
        Set<Id> divisionIds,
        Set<Id> termEnrollmentIds
    ) {
        for (Division_Enrollment__c de : details) {
            if (de.Division__c != null && de.Academic_Term_Enrollment__c != null) {
                divisionIds.add(de.Division__c);
                termEnrollmentIds.add(de.Academic_Term_Enrollment__c);
            }
        }
    }

    private static Map<Id, List<Session_Division__c>> loadSessionDivisions(Set<Id> divisionIds) {
        Date today = Date.today();
        Map<Id, List<Session_Division__c>> result = new Map<Id, List<Session_Division__c>>();
        for (Session_Division__c sd : [
            SELECT Id, Division__c, Session__c, Session__r.Name
            FROM Session_Division__c
            WHERE Division__c IN :divisionIds
            AND Session__r.Session_Date__c >= :today
            AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != :STATUS_CANCELLED)
        ]) {
            if (!result.containsKey(sd.Division__c)) {
                result.put(sd.Division__c, new List<Session_Division__c>());
            }
            result.get(sd.Division__c).add(sd);
        }
        return result;
    }

    private static Set<Id> collectSessionIds(
        Map<Id, List<Session_Division__c>> sessionDivisionsByDivision
    ) {
        Set<Id> sessionIds = new Set<Id>();
        for (List<Session_Division__c> rows : sessionDivisionsByDivision.values()) {
            for (Session_Division__c sd : rows) {
                if (sd.Session__c != null) {
                    sessionIds.add(sd.Session__c);
                }
            }
        }
        return sessionIds;
    }

    private static Set<String> loadExistingKeys(Set<Id> sessionIds, Set<Id> termEnrollmentIds) {
        Set<String> existingKeys = new Set<String>();
        if (sessionIds.isEmpty() || termEnrollmentIds.isEmpty()) {
            return existingKeys;
        }
        for (Session_Enrollment__c se : [
            SELECT Session__c, Academic_Term_Enrollment__c
            FROM Session_Enrollment__c
            WHERE Session__c IN :sessionIds
            AND Academic_Term_Enrollment__c IN :termEnrollmentIds
        ]) {
            existingKeys.add(buildKey(se.Session__c, se.Academic_Term_Enrollment__c));
        }
        return existingKeys;
    }

    private static List<Session_Enrollment__c> buildEnrollments(
        List<Division_Enrollment__c> details,
        Map<Id, List<Session_Division__c>> sessionDivisionsByDivision,
        Set<String> existingKeys
    ) {
        List<Session_Enrollment__c> toInsert = new List<Session_Enrollment__c>();
        for (Division_Enrollment__c de : details) {
            if (de.Academic_Term_Enrollment__c == null || isWithdrawn(de)) {
                continue;
            }
            List<Session_Division__c> rows = sessionDivisionsByDivision.get(de.Division__c);
            if (rows == null) {
                continue;
            }
            for (Session_Division__c sd : rows) {
                String key = buildKey(sd.Session__c, de.Academic_Term_Enrollment__c);
                if (existingKeys.contains(key)) {
                    continue;
                }
                existingKeys.add(key);
                toInsert.add(buildEnrollment(de, sd));
            }
        }
        return toInsert;
    }

    private static Session_Enrollment__c buildEnrollment(
        Division_Enrollment__c de,
        Session_Division__c sd
    ) {
        String sessionName = (sd.Session__r != null) ? sd.Session__r.Name : null;
        Session_Enrollment__c se = new Session_Enrollment__c(
            Session__c = sd.Session__c,
            Academic_Term_Enrollment__c = de.Academic_Term_Enrollment__c,
            Division_Enrollment__c = de.Id,
            Session_Division__c = sd.Id
        );
        se.Name = buildSessionStudentName(sessionName, learnerFirstName(de), learnerLastName(de));
        return se;
    }

    private static Boolean isWithdrawn(Division_Enrollment__c de) {
        return de.Academic_Term_Enrollment__r != null
            && de.Academic_Term_Enrollment__r.Program_Enrolled__c != null
            && STATUS_WITHDRAWN.equalsIgnoreCase(de.Academic_Term_Enrollment__r.Program_Enrolled__r.Status);
    }

    private static String learnerFirstName(Division_Enrollment__c de) {
        return (de.Academic_Term_Enrollment__r != null && de.Academic_Term_Enrollment__r.LearnerAccount != null)
            ? de.Academic_Term_Enrollment__r.LearnerAccount.FirstName
            : null;
    }

    private static String learnerLastName(Division_Enrollment__c de) {
        return (de.Academic_Term_Enrollment__r != null && de.Academic_Term_Enrollment__r.LearnerAccount != null)
            ? de.Academic_Term_Enrollment__r.LearnerAccount.LastName
            : null;
    }

    private static String buildKey(Id sessionId, Id termEnrollmentId) {
        return String.valueOf(sessionId) + '-' + String.valueOf(termEnrollmentId);
    }

    private static String buildSessionStudentName(String sessionTitle, String firstName, String lastName) {
        String title = String.isNotBlank(sessionTitle) ? sessionTitle.trim() : '';
        String first = (firstName != null) ? firstName.trim() : '';
        String last = (lastName != null) ? lastName.trim() : '';
        String studentName = (String.isNotBlank(first) || String.isNotBlank(last))
            ? (first + (String.isNotBlank(first) && String.isNotBlank(last) ? '-' : '') + last)
            : '';
        if (String.isBlank(title) && String.isBlank(studentName)) {
            return null;
        }
        if (String.isBlank(studentName)) {
            return title;
        }
        if (String.isBlank(title)) {
            return studentName;
        }
        String finalName = title + '_' + studentName;
        return (finalName.length() > NAME_MAX_LENGTH)
            ? finalName.substring(0, NAME_MAX_LENGTH)
            : finalName;
    }
}
/**
 * Asynchronously assigns newly enrolled division students to the sessions already scheduled
 * for their division, by creating Session_Enrollment__c records.
 *
 * Runs in its own transaction (enqueued from divisionEnrollmentTrigger after insert), so it is
 * decoupled from the enrollment + session-publish automation and is not exposed to the lock
 * contention that can occur when those run together synchronously.
 *
 * Eligible sessions = future (Session_Date__c on/after today) and NOT Cancelled — Draft sessions
 * are included, so a student enrolled before a session is published is already assigned when it
 * is published. Withdrawn students and already-existing assignments are skipped.
 *
 * Failure handling is never silent: a transient row-lock error is retried (bounded), and any
 * other / final failure is re-thrown so it surfaces on the AsyncApexJob in Setup > Apex Jobs.
 */
public without sharing class SessionAssignmentQueueable implements Queueable {

    @TestVisible
    private static final Integer MAX_ATTEMPTS = 3;
    private static final String STATUS_WITHDRAWN = 'Withdrawn';
    private static final String STATUS_CANCELLED = 'Cancelled';
    private static final Integer NAME_MAX_LENGTH = 80;

    private final Set<Id> enrollmentIds;
    private final Integer attempt;

    /**
     * @param enrollmentIds Ids of the newly inserted Division_Enrollment__c records.
     */
    public SessionAssignmentQueueable(Set<Id> enrollmentIds) {
        this(enrollmentIds, 1);
    }

    /**
     * @param enrollmentIds Ids of the newly inserted Division_Enrollment__c records.
     * @param attempt 1-based attempt number (incremented on retry).
     */
    public SessionAssignmentQueueable(Set<Id> enrollmentIds, Integer attempt) {
        this.enrollmentIds = (enrollmentIds == null) ? new Set<Id>() : enrollmentIds;
        this.attempt = (attempt == null) ? 1 : attempt;
    }

    /**
     * Builds and inserts the session assignments; retries transient lock errors and re-throws
     * any final failure so it is visible on the AsyncApexJob.
     *
     * @param context Queueable context (unused).
     */
    public void execute(QueueableContext context) {
        if (enrollmentIds.isEmpty()) {
            return;
        }
        List<Session_Enrollment__c> toInsert = buildAssignments(enrollmentIds);
        if (toInsert.isEmpty()) {
            return;
        }
        try {
            insert toInsert;
        } catch (Exception e) {
            if (shouldRetry(e, attempt)
                    && !Test.isRunningTest()
                    && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new SessionAssignmentQueueable(enrollmentIds, attempt + 1));
                return;
            }
            throw e;
        }
    }

    /**
     * Builds the Session_Enrollment__c records that should exist for the given enrollments.
     *
     * @param enrollmentIds Division_Enrollment__c ids to process.
     * @return Session_Enrollment__c records to insert (deduped against existing assignments).
     */
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

    /**
     * @param e The exception thrown by the insert.
     * @param attempt The current attempt number.
     * @return True when the failure is a transient lock error and attempts remain.
     */
    @TestVisible
    private static Boolean shouldRetry(Exception e, Integer attempt) {
        return attempt < MAX_ATTEMPTS && isRetryable(e);
    }

    private static Boolean isRetryable(Exception e) {
        String msg = (e != null && e.getMessage() != null) ? e.getMessage() : '';
        return msg.contains('UNABLE_TO_LOCK_ROW')
            || msg.containsIgnoreCase('unable to obtain exclusive access');
    }

    /**
     * Re-queries the inserted enrollments with the learner and program-status fields needed for
     * naming and the withdrawn filter (Trigger.new does not carry related fields).
     *
     * @param enrollmentIds Division_Enrollment__c ids.
     * @return Division_Enrollment__c records with related fields populated.
     */
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

    /**
     * @param details Enrollment records with related fields.
     * @param divisionIds Output set of division ids.
     * @param termEnrollmentIds Output set of academic term enrollment ids.
     */
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

    /**
     * Loads the Session_Division rows for the given divisions whose session is future and not
     * cancelled (Draft included), grouped by division id.
     *
     * @param divisionIds Division ids the new students were enrolled into.
     * @return Map of division id to its applicable Session_Division__c rows.
     */
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

    /**
     * @param sessionDivisionsByDivision Grouped Session_Division rows.
     * @return Distinct session ids referenced by those rows.
     */
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

    /**
     * @param sessionIds Candidate session ids.
     * @param termEnrollmentIds Academic term enrollment ids of the new students.
     * @return Set of 'sessionId-termEnrollmentId' keys that already have an assignment.
     */
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

    /**
     * @param details New enrollments with related fields.
     * @param sessionDivisionsByDivision Applicable Session_Division rows grouped by division.
     * @param existingKeys Keys that must not be recreated (mutated to dedupe within this run).
     * @return Session_Enrollment__c records to insert.
     */
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

    /**
     * @param de The student's division enrollment.
     * @param sd The Session_Division row linking the session to the division.
     * @return A populated, unsaved Session_Enrollment__c.
     */
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

    /**
     * @param de Division enrollment with the related program-enrollment status.
     * @return True if the student's program enrollment is withdrawn.
     */
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

    /**
     * Builds the Session_Enrollment Name as SessionTitle_FirstName-LastName, capped at 80 chars.
     * Mirrors TimetableSessionController.buildSessionStudentName so both creation paths match.
     *
     * @param sessionTitle The session name.
     * @param firstName Learner first name.
     * @param lastName Learner last name.
     * @return The composed name, or null when nothing is available.
     */
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
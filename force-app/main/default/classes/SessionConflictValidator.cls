public with sharing class SessionConflictValidator {

    public static void validateStudentSessionConflicts(
        Set<Id> divisionIds,
        Id courseId,
        Date sessionDate,
        Datetime startTime,
        Datetime endTime,
        Id currentSessionId
    ) {
        if (divisionIds.isEmpty() || sessionDate == null) {
            return;
        }

        /* 1. Get learners from Division Enrollment (same source as session creation) */
        List<Division_Enrollment__c> divEnrollments = [
            SELECT Id, Academic_Term_Enrollment__r.LearnerAccountId
            FROM Division_Enrollment__c
            WHERE Division__c IN :divisionIds
              AND Academic_Term_Enrollment__r.LearnerAccountId != null
        ];
        if (divEnrollments.isEmpty()) return;

        Set<Id> learnerIds = new Set<Id>();
        for (Division_Enrollment__c de : divEnrollments) {
            if (de.Academic_Term_Enrollment__r != null && de.Academic_Term_Enrollment__r.LearnerAccountId != null) {
                learnerIds.add(de.Academic_Term_Enrollment__r.LearnerAccountId);
            }
        }
        if (learnerIds.isEmpty()) return;

        /* 2. Find conflicting session enrollments: session not completed and schedule type not Cancelled, same time, any course */
        List<Session_Enrollment__c> conflicts;

        if (currentSessionId == null) {
            conflicts = [
                SELECT Id,
                       Academic_Term_Enrollment__r.LearnerAccountId,
                       Session__r.Id,
                       Session__r.Session_Date__c,
                       Session__r.Start_Time__c,
                       Session__r.End_Time__c
                FROM Session_Enrollment__c
                WHERE Academic_Term_Enrollment__r.LearnerAccountId IN :learnerIds
                  AND Session__r.Session_Date__c = :sessionDate
                  AND Session__r.Start_Time__c < :endTime
                  AND Session__r.End_Time__c > :startTime
                  AND (Session__r.Is_Completed__c = false)
                  AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
            ];
        } else {
            conflicts = [
                SELECT Id,
                       Academic_Term_Enrollment__r.LearnerAccountId,
                       Session__r.Id,
                       Session__r.Session_Date__c,
                       Session__r.Start_Time__c,
                       Session__r.End_Time__c
                FROM Session_Enrollment__c
                WHERE Academic_Term_Enrollment__r.LearnerAccountId IN :learnerIds
                  AND Session__r.Session_Date__c = :sessionDate
                  AND Session__r.Start_Time__c < :endTime
                  AND Session__r.End_Time__c > :startTime
                  AND Session__r.Id != :currentSessionId
                  AND (Session__r.Is_Completed__c = false)
                  AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
            ];
        }

        if (conflicts.isEmpty()) return;

        /* 3. One conflict per learner */
        Map<Id, Session_Enrollment__c> learnerConflictMap = new Map<Id, Session_Enrollment__c>();
        for (Session_Enrollment__c se : conflicts) {
            Id learnerId = se.Academic_Term_Enrollment__r.LearnerAccountId;
            if (!learnerConflictMap.containsKey(learnerId)) {
                learnerConflictMap.put(learnerId, se);
            }
        }

        /* 4. Learner names (Account) */
        // Fetch learner names
        Map<Id, Account> learnerMap = new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :learnerConflictMap.keySet()
        ]);

        List<String> names = new List<String>();
        for (Id learnerId : learnerConflictMap.keySet()) {
            names.add(learnerMap.get(learnerId).Name);
        }

        // All conflicts share same date/time
        Session__c s = learnerConflictMap.values().iterator().next().Session__r;

        // Build DateTime safely
        DateTime sessionDateTime = DateTime.newInstance(
            s.Session_Date__c.year(),
            s.Session_Date__c.month(),
            s.Session_Date__c.day(),
            s.Start_Time__c.hour(),
            s.Start_Time__c.minute(),
            0
        );

        String dateTimeStr = sessionDateTime.format('d MMM yyyy, h:mm a');

        // Grammar handling
        String prefix = names.size() == 1 ? 'Student ' : 'Students ';
        String verb   = names.size() == 1 ? 'has' : 'have';

        String errorMessage =
            prefix + String.join(names, ', ') + ' ' + verb +
            ' an overlapping session at ' + dateTimeStr + '.';

        throw new AuraHandledException(errorMessage);
    }

    /**
     * Returns student overlap conflict details (same learner in another session at same date/time).
     * Checks any course – not limited to same course. Does not throw; returns list of DTOs for UI.
     */
    public static List<StudentSessionConflictDetail> getStudentSessionConflictDetails(
        Set<Id> divisionIds,
        Date sessionDate,
        Datetime startTime,
        Datetime endTime,
        Id currentSessionId,
        String proposedSessionName
    ) {
        List<StudentSessionConflictDetail> result = new List<StudentSessionConflictDetail>();
        if (divisionIds == null || divisionIds.isEmpty() || sessionDate == null || startTime == null || endTime == null) {
            return result;
        }
        try {
            /* Get learners from Division Enrollment (same source as session creation) */
            List<Division_Enrollment__c> divEnrollments = [
                SELECT Id, Academic_Term_Enrollment__r.LearnerAccountId
                FROM Division_Enrollment__c
                WHERE Division__c IN :divisionIds
                  AND Academic_Term_Enrollment__r.LearnerAccountId != null
            ];
            if (divEnrollments.isEmpty()) return result;

            Set<Id> learnerIds = new Set<Id>();
            for (Division_Enrollment__c de : divEnrollments) {
                if (de.Academic_Term_Enrollment__r != null && de.Academic_Term_Enrollment__r.LearnerAccountId != null) {
                    learnerIds.add(de.Academic_Term_Enrollment__r.LearnerAccountId);
                }
            }
            if (learnerIds.isEmpty()) return result;

            String proposedDateStr = sessionDate != null ? sessionDate.format() : '';
            String proposedTimeStr = formatTimeRange(startTime, endTime);

            /* Consider sessions not completed and schedule type not Cancelled as conflicts */
            List<Session_Enrollment__c> conflicts;
            if (currentSessionId == null) {
                conflicts = [
                    SELECT Id, Academic_Term_Enrollment__r.LearnerAccountId, Academic_Term_Enrollment__r.LearnerAccount.Name,
                           Session__r.Id, Session__r.Name, Session__r.Course__r.Name,
                           Session__r.Session_Date__c, Session__r.Start_Time__c, Session__r.End_Time__c
                    FROM Session_Enrollment__c
                    WHERE Academic_Term_Enrollment__r.LearnerAccountId IN :learnerIds
                      AND Session__r.Session_Date__c = :sessionDate
                      AND Session__r.Start_Time__c < :endTime
                      AND Session__r.End_Time__c > :startTime
                      AND (Session__r.Is_Completed__c = false)
                      AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
                ];
            } else {
                conflicts = [
                    SELECT Id, Academic_Term_Enrollment__r.LearnerAccountId, Academic_Term_Enrollment__r.LearnerAccount.Name,
                           Session__r.Id, Session__r.Name, Session__r.Course__r.Name,
                           Session__r.Session_Date__c, Session__r.Start_Time__c, Session__r.End_Time__c
                    FROM Session_Enrollment__c
                    WHERE Academic_Term_Enrollment__r.LearnerAccountId IN :learnerIds
                      AND Session__r.Session_Date__c = :sessionDate
                      AND Session__r.Start_Time__c < :endTime
                      AND Session__r.End_Time__c > :startTime
                      AND Session__r.Id != :currentSessionId
                      AND (Session__r.Is_Completed__c = false)
                      AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
                ];
            }
            if (conflicts.isEmpty()) return result;

            Map<Id, List<String>> sessionIdToStudentNames = new Map<Id, List<String>>();
            Map<Id, Session__c> sessionMap = new Map<Id, Session__c>();
            Map<Id, String> sessionIdToCourseName = new Map<Id, String>();
            for (Session_Enrollment__c se : conflicts) {
                Id sessId = se.Session__r.Id;
                String studentName = se.Academic_Term_Enrollment__r.LearnerAccount.Name != null
                    ? se.Academic_Term_Enrollment__r.LearnerAccount.Name
                    : 'Unknown';
                if (!sessionIdToStudentNames.containsKey(sessId)) {
                    sessionIdToStudentNames.put(sessId, new List<String>());
                    sessionMap.put(sessId, new Session__c(
                        Id = se.Session__r.Id,
                        Name = se.Session__r.Name,
                        Session_Date__c = se.Session__r.Session_Date__c,
                        Start_Time__c = se.Session__r.Start_Time__c,
                        End_Time__c = se.Session__r.End_Time__c
                    ));
                    if (se.Session__r.Course__r != null && String.isNotBlank(se.Session__r.Course__r.Name)) {
                        sessionIdToCourseName.put(sessId, se.Session__r.Course__r.Name);
                    }
                }
                List<String> names = sessionIdToStudentNames.get(sessId);
                if (!names.contains(studentName)) {
                    names.add(studentName);
                }
            }

            for (Id sessId : sessionIdToStudentNames.keySet()) {
                Session__c s = sessionMap.get(sessId);
                String conflictingTimeStr = formatTimeRange(s.Start_Time__c, s.End_Time__c);
                String conflictingCourseName = sessionIdToCourseName.get(sessId);
                StudentSessionConflictDetail dto = new StudentSessionConflictDetail();
                dto.proposedSessionName = proposedSessionName;
                dto.proposedDateStr = proposedDateStr;
                dto.proposedTimeStr = proposedTimeStr;
                dto.studentNames = sessionIdToStudentNames.get(sessId);
                dto.conflictingSessionName = s.Name != null ? s.Name : '';
                dto.conflictingDateStr = s.Session_Date__c != null ? s.Session_Date__c.format() : '';
                dto.conflictingTimeStr = conflictingTimeStr;
                dto.conflictingCourseName = conflictingCourseName;
                result.add(dto);
            }
        } catch (Exception e) {
            System.debug('getStudentSessionConflictDetails: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        }
        return result;
    }

    public static void validateDivisionSessionConflicts(
        Set<Id> divisionIds,
        Date sessionDate,
        Datetime startTime,
        Datetime endTime,
        Id currentSessionId
    ) {
        if (divisionIds.isEmpty() || sessionDate == null) {
            return;
        }

        List<Session_Division__c> conflicts;

        // Note: ignore sessions that have been cancelled – they should not block rescheduling.
        if (currentSessionId == null) {
            // CREATE
            conflicts = [
                SELECT Id
                FROM Session_Division__c
                WHERE Division__c IN :divisionIds
                AND Session__r.Session_Date__c = :sessionDate
                AND Session__r.Start_Time__c < :endTime
                AND Session__r.End_Time__c > :startTime
                AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
            ];
        } else {
            // UPDATE
            conflicts = [
                SELECT Id
                FROM Session_Division__c
                WHERE Division__c IN :divisionIds
                AND Session__r.Session_Date__c = :sessionDate
                AND Session__r.Start_Time__c < :endTime
                AND Session__r.End_Time__c > :startTime
                AND Session__r.Id != :currentSessionId
                AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
            ];
        }

        if (!conflicts.isEmpty()) {
            throw new AuraHandledException('Conflicting session for this division.');
        }
    }

    /**
     * Returns division session conflict details (same division, overlapping time).
     * Does not throw; returns a list of conflict detail DTOs for UI display (View details).
     */
    public static List<DivisionSessionConflictDetail> getDivisionSessionConflictDetails(
        Set<Id> divisionIds,
        Date sessionDate,
        Datetime startTime,
        Datetime endTime,
        Id currentSessionId,
        String proposedSessionName,
        String proposedContextJson
    ) {
        List<DivisionSessionConflictDetail> result = new List<DivisionSessionConflictDetail>();
        if (divisionIds == null || divisionIds.isEmpty() || sessionDate == null || startTime == null || endTime == null) {
            return result;
        }
        try {
            List<Session_Division__c> conflicts;
            if (currentSessionId == null) {
                conflicts = [
                    SELECT Id, Division__c, Division__r.Division_Name__c,
                           Session__c, Session__r.Name, Session__r.Session_Date__c,
                           Session__r.Start_Time__c, Session__r.End_Time__c,
                           Session__r.Course__r.Name
                    FROM Session_Division__c
                    WHERE Division__c IN :divisionIds
                    AND Session__r.Session_Date__c = :sessionDate
                    AND Session__r.Start_Time__c < :endTime
                    AND Session__r.End_Time__c > :startTime
                    AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
                ];
            } else {
                conflicts = [
                    SELECT Id, Division__c, Division__r.Division_Name__c,
                           Session__c, Session__r.Name, Session__r.Session_Date__c,
                           Session__r.Start_Time__c, Session__r.End_Time__c,
                           Session__r.Course__r.Name
                    FROM Session_Division__c
                    WHERE Division__c IN :divisionIds
                    AND Session__r.Session_Date__c = :sessionDate
                    AND Session__r.Start_Time__c < :endTime
                    AND Session__r.End_Time__c > :startTime
                    AND Session__r.Id != :currentSessionId
                    AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
                ];
            }
            if (conflicts.isEmpty()) return result;

            Map<Id, Session__c> conflictingSessionsById = new Map<Id, Session__c>();
            Map<Id, List<String>> divisionNamesBySessionId = new Map<Id, List<String>>();
            for (Session_Division__c sd : conflicts) {
                if (sd.Session__r != null && sd.Session__c != null) {
                    conflictingSessionsById.put(sd.Session__c, sd.Session__r);
                    if (!divisionNamesBySessionId.containsKey(sd.Session__c)) {
                        divisionNamesBySessionId.put(sd.Session__c, new List<String>());
                    }
                    if (sd.Division__r != null && String.isNotBlank(sd.Division__r.Division_Name__c)) {
                        divisionNamesBySessionId.get(sd.Session__c).add(sd.Division__r.Division_Name__c);
                    }
                }
            }
            if (conflictingSessionsById.isEmpty()) return result;

            String proposedDateStr = sessionDate != null ? sessionDate.format() : '';
            String proposedTimeStr = formatTimeRange(startTime, endTime);
            String proposedName = String.isNotBlank(proposedSessionName) ? proposedSessionName : 'Session';

            ProposedConflictLabels proposedLabels = parseProposedConflictContextJson(proposedContextJson);

            for (Id sessionId : conflictingSessionsById.keySet()) {
                Session__c sess = conflictingSessionsById.get(sessionId);
                String conflictingTimeStr = '';
                if (sess.Start_Time__c != null && sess.End_Time__c != null) {
                    conflictingTimeStr = formatTimeRange(sess.Start_Time__c, sess.End_Time__c);
                }
                List<String> divNames = divisionNamesBySessionId.get(sessionId);
                String conflictingDivisionNames = (divNames != null && !divNames.isEmpty()) ? String.join(divNames, ', ') : '';
                String conflictingProgramName = '';
                String conflictingBatchName = '';
                String conflictingBatchGroupName = '';
                String conflictingTermName = '';
                String conflictingCourseName = '';
                if (sess.Course__r != null && String.isNotBlank(sess.Course__r.Name)) {
                    conflictingCourseName = sess.Course__r.Name.trim();
                }
                try {
                    List<Session_Division__c> sessionDivisions = [
                        SELECT Division__c
                        FROM Session_Division__c
                        WHERE Session__c = :sessionId
                        AND Division__c != null
                    ];
                    Set<Id> divIds = new Set<Id>();
                    for (Session_Division__c sd : sessionDivisions) {
                        divIds.add(sd.Division__c);
                    }
                    if (!divIds.isEmpty()) {
                        List<Division__c> divisions = [
                            SELECT Division_Name__c, Term__c
                            FROM Division__c
                            WHERE Id IN :divIds
                        ];
                        Set<Id> termIds = new Set<Id>();
                        for (Division__c div : divisions) {
                            if (div.Term__c != null) termIds.add(div.Term__c);
                        }
                        if (!termIds.isEmpty()) {
                            List<AcademicTerm> terms = [
                                SELECT Id, Name, AcademicYearId,
                                       AcademicYear.Name, AcademicYear.Batch__c,
                                       AcademicYear.Batch__r.Name, AcademicYear.Batch__r.ProgramId,
                                       AcademicYear.Batch__r.Program.Name
                                FROM AcademicTerm
                                WHERE Id IN :termIds
                                AND AcademicYearId != null
                            ];
                            List<String> programNames = new List<String>();
                            List<String> batchNames = new List<String>();
                            List<String> batchGroupNames = new List<String>();
                            List<String> termNames = new List<String>();
                            for (AcademicTerm t : terms) {
                                if (String.isNotBlank(t.Name)) termNames.add(t.Name);
                                if (t.AcademicYear != null) {
                                    if (String.isNotBlank(t.AcademicYear.Name)) batchGroupNames.add(t.AcademicYear.Name);
                                    if (t.AcademicYear.Batch__r != null) {
                                        if (String.isNotBlank(t.AcademicYear.Batch__r.Name)) batchNames.add(t.AcademicYear.Batch__r.Name);
                                        if (t.AcademicYear.Batch__r.Program != null && String.isNotBlank(t.AcademicYear.Batch__r.Program.Name)) {
                                            programNames.add(t.AcademicYear.Batch__r.Program.Name);
                                        }
                                    }
                                }
                            }
                            if (!programNames.isEmpty()) conflictingProgramName = String.join(programNames, ', ');
                            if (!batchNames.isEmpty()) conflictingBatchName = String.join(batchNames, ', ');
                            if (!batchGroupNames.isEmpty()) conflictingBatchGroupName = String.join(batchGroupNames, ', ');
                            if (!termNames.isEmpty()) conflictingTermName = String.join(termNames, ', ');
                        }
                    }
                } catch (Exception innerEx) {
                    System.debug('Division conflict context for session ' + sessionId + ': ' + innerEx.getMessage());
                }

                DivisionSessionConflictDetail dto = new DivisionSessionConflictDetail();
                dto.proposedSessionName = proposedName;
                dto.proposedDateStr = proposedDateStr;
                dto.proposedTimeStr = proposedTimeStr;
                dto.proposedCourseName = proposedLabels.courseName;
                dto.proposedDivisionNames = proposedLabels.divisionNames;
                dto.proposedProgramName = proposedLabels.programName;
                dto.proposedBatchName = proposedLabels.batchName;
                dto.proposedBatchGroupName = proposedLabels.batchGroupName;
                dto.proposedTermName = proposedLabels.termName;
                dto.conflictingSessionName = sess.Name != null ? sess.Name : '';
                dto.conflictingDateStr = sess.Session_Date__c != null ? sess.Session_Date__c.format() : '';
                dto.conflictingTimeStr = conflictingTimeStr;
                dto.conflictingCourseName = conflictingCourseName;
                dto.conflictingDivisionNames = conflictingDivisionNames;
                dto.conflictingProgramName = conflictingProgramName;
                dto.conflictingBatchName = conflictingBatchName;
                dto.conflictingBatchGroupName = conflictingBatchGroupName;
                dto.conflictingTermName = conflictingTermName;
                result.add(dto);
            }
        } catch (Exception e) {
            System.debug('getDivisionSessionConflictDetails: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        }
        return result;
    }

    public static void validateFacultySessionConflicts(
        Set<Id> facultyIds,
        Date sessionDate,
        Datetime startTime,
        Datetime endTime,
        Id currentSessionId
    ) {
        if (facultyIds == null || facultyIds.isEmpty() || sessionDate == null) {
            return;
        }

        List<Session_Faculty__c> conflicts;

        if (currentSessionId == null) {
            // CREATE
            conflicts = [
                SELECT Id
                FROM Session_Faculty__c
                WHERE Session_Faculty__c IN :facultyIds
                AND Session__r.Session_Date__c = :sessionDate
                AND Session__r.Start_Time__c < :endTime
                AND Session__r.End_Time__c > :startTime
                AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
            ];
        } else {
            // UPDATE
            conflicts = [
                SELECT Id
                FROM Session_Faculty__c
                WHERE Session_Faculty__c IN :facultyIds
                AND Session__r.Session_Date__c = :sessionDate
                AND Session__r.Start_Time__c < :endTime
                AND Session__r.End_Time__c > :startTime
                AND Session__r.Id != :currentSessionId
                AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
            ];
        }

        if (!conflicts.isEmpty()) {
            throw new AuraHandledException('Conflicting session for faculty.');
        }
    }

    /**
     * Returns faculty conflict details (date/time and faculty names) for a proposed session.
     * Does not throw; returns a list of conflict detail DTOs for UI display.
     *
     * @param proposedContextJson Optional JSON string (same keys as division conflict) for "Your session" labels on the client-built session.
     */
    public static List<FacultyConflictDetail> getFacultySessionConflictDetails(
        Set<Id> facultyIds,
        Date sessionDate,
        Datetime startTime,
        Datetime endTime,
        Id currentSessionId,
        String proposedSessionName,
        String proposedContextJson
    ) {
        List<FacultyConflictDetail> result = new List<FacultyConflictDetail>();
        if (facultyIds == null || facultyIds.isEmpty() || sessionDate == null || startTime == null || endTime == null) {
            return result;
        }
        try {
            List<Session_Faculty__c> conflicts;
            if (currentSessionId == null) {
                conflicts = [
                    SELECT Id, Session_Faculty__c,
                           Session__r.Name, Session__r.Session_Date__c,
                           Session__r.Start_Time__c, Session__r.End_Time__c,
                           Session__r.Course__r.Name
                    FROM Session_Faculty__c
                    WHERE Session_Faculty__c IN :facultyIds
                    AND Session__r.Session_Date__c = :sessionDate
                    AND Session__r.Start_Time__c < :endTime
                    AND Session__r.End_Time__c > :startTime
                    AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
                ];
            } else {
                conflicts = [
                    SELECT Id, Session_Faculty__c,
                           Session__r.Name, Session__r.Session_Date__c,
                           Session__r.Start_Time__c, Session__r.End_Time__c,
                           Session__r.Course__r.Name
                    FROM Session_Faculty__c
                    WHERE Session_Faculty__c IN :facultyIds
                    AND Session__r.Session_Date__c = :sessionDate
                    AND Session__r.Start_Time__c < :endTime
                    AND Session__r.End_Time__c > :startTime
                    AND Session__r.Id != :currentSessionId
                    AND (Session__r.Schedule_Type__c = null OR Session__r.Schedule_Type__c != 'Cancelled')
                ];
            }

            if (conflicts.isEmpty()) return result;

            Map<Id, Session__c> conflictingSessionsById = new Map<Id, Session__c>();
            Map<Id, Set<Id>> sessionIdToFacultyIds = new Map<Id, Set<Id>>();
            for (Session_Faculty__c sf : conflicts) {
                if (sf.Session__r == null || sf.Session__c == null) {
                    continue;
                }
                conflictingSessionsById.put(sf.Session__c, sf.Session__r);
                if (!sessionIdToFacultyIds.containsKey(sf.Session__c)) {
                    sessionIdToFacultyIds.put(sf.Session__c, new Set<Id>());
                }
                if (sf.Session_Faculty__c != null) {
                    sessionIdToFacultyIds.get(sf.Session__c).add(sf.Session_Faculty__c);
                }
            }
            if (conflictingSessionsById.isEmpty()) return result;

            Set<Id> allFacultyIds = new Set<Id>();
            for (Set<Id> fids : sessionIdToFacultyIds.values()) {
                allFacultyIds.addAll(fids);
            }
            Map<Id, Account> facultyMap = new Map<Id, Account>([
                SELECT Id, Name FROM Account WHERE Id IN :allFacultyIds
            ]);

            String proposedDateStr = sessionDate != null ? sessionDate.format() : '';
            String proposedTimeStr = formatTimeRange(startTime, endTime);
            String proposedName = String.isNotBlank(proposedSessionName) ? proposedSessionName : 'Session';

            ProposedConflictLabels proposedLabels = parseProposedConflictContextJson(proposedContextJson);

            for (Id sessionId : conflictingSessionsById.keySet()) {
                Session__c sess = conflictingSessionsById.get(sessionId);
                String conflictingTimeStr = '';
                if (sess.Start_Time__c != null && sess.End_Time__c != null) {
                    conflictingTimeStr = formatTimeRange(sess.Start_Time__c, sess.End_Time__c);
                }
                String conflictingDivisionNames = '';
                String conflictingProgramName = '';
                String conflictingBatchName = '';
                String conflictingBatchGroupName = '';
                String conflictingTermName = '';
                String conflictingCourseNameFaculty = '';
                if (sess.Course__r != null && String.isNotBlank(sess.Course__r.Name)) {
                    conflictingCourseNameFaculty = sess.Course__r.Name.trim();
                }
                try {
                    List<Session_Division__c> sessionDivisions = [
                        SELECT Division__c
                        FROM Session_Division__c
                        WHERE Session__c = :sessionId
                        AND Division__c != null
                    ];
                    Set<Id> divisionIdsCtx = new Set<Id>();
                    for (Session_Division__c sd : sessionDivisions) {
                        divisionIdsCtx.add(sd.Division__c);
                    }
                    if (!divisionIdsCtx.isEmpty()) {
                        List<Division__c> divisions = [
                            SELECT Division_Name__c, Term__c
                            FROM Division__c
                            WHERE Id IN :divisionIdsCtx
                        ];
                        List<String> divNames = new List<String>();
                        Set<Id> termIds = new Set<Id>();
                        for (Division__c div : divisions) {
                            if (String.isNotBlank(div.Division_Name__c)) {
                                divNames.add(div.Division_Name__c);
                            }
                            if (div.Term__c != null) {
                                termIds.add(div.Term__c);
                            }
                        }
                        if (!divNames.isEmpty()) {
                            conflictingDivisionNames = String.join(divNames, ', ');
                        }
                        if (!termIds.isEmpty()) {
                            List<AcademicTerm> terms = [
                                SELECT Id, Name, AcademicYearId,
                                       AcademicYear.Name, AcademicYear.Batch__c,
                                       AcademicYear.Batch__r.Name, AcademicYear.Batch__r.ProgramId,
                                       AcademicYear.Batch__r.Program.Name
                                FROM AcademicTerm
                                WHERE Id IN :termIds
                                AND AcademicYearId != null
                            ];
                            List<String> programNames = new List<String>();
                            List<String> batchNames = new List<String>();
                            List<String> batchGroupNames = new List<String>();
                            List<String> termNames = new List<String>();
                            for (AcademicTerm t : terms) {
                                if (String.isNotBlank(t.Name)) termNames.add(t.Name);
                                if (t.AcademicYear != null) {
                                    if (String.isNotBlank(t.AcademicYear.Name)) batchGroupNames.add(t.AcademicYear.Name);
                                    if (t.AcademicYear.Batch__r != null) {
                                        if (String.isNotBlank(t.AcademicYear.Batch__r.Name)) batchNames.add(t.AcademicYear.Batch__r.Name);
                                        if (t.AcademicYear.Batch__r.Program != null && String.isNotBlank(t.AcademicYear.Batch__r.Program.Name)) {
                                            programNames.add(t.AcademicYear.Batch__r.Program.Name);
                                        }
                                    }
                                }
                            }
                            if (!programNames.isEmpty()) conflictingProgramName = String.join(programNames, ', ');
                            if (!batchNames.isEmpty()) conflictingBatchName = String.join(batchNames, ', ');
                            if (!batchGroupNames.isEmpty()) conflictingBatchGroupName = String.join(batchGroupNames, ', ');
                            if (!termNames.isEmpty()) conflictingTermName = String.join(termNames, ', ');
                        }
                    }
                } catch (Exception innerEx) {
                    System.debug('Conflict context for session ' + sessionId + ': ' + innerEx.getMessage());
                }

                List<String> facultyNamesForSession = new List<String>();
                Set<Id> fidsForSession = sessionIdToFacultyIds.get(sessionId);
                if (fidsForSession != null) {
                    for (Id fid : fidsForSession) {
                        Account a = facultyMap.get(fid);
                        if (a != null) {
                            facultyNamesForSession.add(a.Name);
                        }
                    }
                }

                FacultyConflictDetail dto = new FacultyConflictDetail();
                dto.proposedSessionName = proposedName;
                dto.proposedDateStr = proposedDateStr;
                dto.proposedTimeStr = proposedTimeStr;
                dto.proposedCourseName = proposedLabels.courseName;
                dto.proposedDivisionNames = proposedLabels.divisionNames;
                dto.proposedProgramName = proposedLabels.programName;
                dto.proposedBatchName = proposedLabels.batchName;
                dto.proposedBatchGroupName = proposedLabels.batchGroupName;
                dto.proposedTermName = proposedLabels.termName;
                dto.facultyNames = facultyNamesForSession;
                dto.conflictingSessionName = sess.Name != null ? sess.Name : '';
                dto.conflictingDateStr = sess.Session_Date__c != null ? sess.Session_Date__c.format() : '';
                dto.conflictingTimeStr = conflictingTimeStr;
                dto.conflictingCourseName = conflictingCourseNameFaculty;
                dto.conflictingDivisionNames = conflictingDivisionNames;
                dto.conflictingProgramName = conflictingProgramName;
                dto.conflictingBatchName = conflictingBatchName;
                dto.conflictingBatchGroupName = conflictingBatchGroupName;
                dto.conflictingTermName = conflictingTermName;
                result.add(dto);
            }
        } catch (Exception e) {
            System.debug('getFacultySessionConflictDetails: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        }
        return result;
    }

    /**
     * Counts learners that are present in more than one of the supplied divisions.
     * Used to surface non-blocking warnings when merging programs/divisions into a single session.
     *
     * @param divisionIds Division IDs selected for session creation.
     * @return Number of learners that appear in multiple supplied divisions.
     */
    public static Integer countOverlappingLearnersAcrossDivisions(Set<Id> divisionIds) {
        Integer overlapCount = 0;
        if (divisionIds == null || divisionIds.isEmpty() || divisionIds.size() < 2) {
            return overlapCount;
        }
        try {
            List<AggregateResult> duplicateLearners = [
                SELECT Academic_Term_Enrollment__r.LearnerAccountId learnerId,
                       COUNT_DISTINCT(Division__c) divCount
                FROM Division_Enrollment__c
                WHERE Division__c IN :divisionIds
                AND Academic_Term_Enrollment__r.LearnerAccountId != null
                GROUP BY Academic_Term_Enrollment__r.LearnerAccountId
                HAVING COUNT_DISTINCT(Division__c) > 1
            ];
            overlapCount = duplicateLearners.size();
        } catch (Exception e) {
            System.debug('countOverlappingLearnersAcrossDivisions: ' + e.getMessage());
        }
        return overlapCount;
    }

    private static String formatTimeRange(Datetime startDt, Datetime endDt) {
        if (startDt == null || endDt == null) return '';
        return startDt.format('h:mm a') + ' – ' + endDt.format('h:mm a');
    }

    private class ProposedConflictLabels {
        String courseName = '';
        String divisionNames = '';
        String programName = '';
        String batchName = '';
        String batchGroupName = '';
        String termName = '';
    }

    private static String textFromJsonValue(Object o) {
        if (o == null) {
            return '';
        }
        String s = String.valueOf(o).trim();
        return s;
    }

    /**
     * Parses optional LWC JSON for the "Your session" conflict column (display only; no SOQL).
     *
     * @param proposedContextJson JSON object string with optional keys courseName, divisionNames, programName, batchName, batchGroupName, termName.
     * @return Parsed labels; empty strings when missing or invalid JSON.
     */
    private static ProposedConflictLabels parseProposedConflictContextJson(String proposedContextJson) {
        ProposedConflictLabels p = new ProposedConflictLabels();
        if (String.isBlank(proposedContextJson)) {
            return p;
        }
        try {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(proposedContextJson);
            if (m == null) {
                return p;
            }
            p.courseName = textFromJsonValue(m.get('courseName'));
            p.divisionNames = textFromJsonValue(m.get('divisionNames'));
            p.programName = textFromJsonValue(m.get('programName'));
            p.batchName = textFromJsonValue(m.get('batchName'));
            p.batchGroupName = textFromJsonValue(m.get('batchGroupName'));
            p.termName = textFromJsonValue(m.get('termName'));
        } catch (Exception ex) {
            System.debug('parseProposedConflictContextJson: ' + ex.getMessage());
        }
        return p;
    }

    public class FacultyConflictDetail {
        @AuraEnabled public String proposedSessionName { get; set; }
        @AuraEnabled public String proposedDateStr { get; set; }
        @AuraEnabled public String proposedTimeStr { get; set; }
        /** Display-only labels for "Your session" from LWC JSON (same shape as division conflict). */
        @AuraEnabled public String proposedCourseName { get; set; }
        @AuraEnabled public String proposedDivisionNames { get; set; }
        @AuraEnabled public String proposedProgramName { get; set; }
        @AuraEnabled public String proposedBatchName { get; set; }
        @AuraEnabled public String proposedBatchGroupName { get; set; }
        @AuraEnabled public String proposedTermName { get; set; }
        @AuraEnabled public List<String> facultyNames { get; set; }
        @AuraEnabled public String conflictingSessionName { get; set; }
        @AuraEnabled public String conflictingDateStr { get; set; }
        @AuraEnabled public String conflictingTimeStr { get; set; }
        /** Learning course name from Session.Course__c */
        @AuraEnabled public String conflictingCourseName { get; set; }
        @AuraEnabled public String conflictingDivisionNames { get; set; }
        @AuraEnabled public String conflictingProgramName { get; set; }
        @AuraEnabled public String conflictingBatchName { get; set; }
        @AuraEnabled public String conflictingBatchGroupName { get; set; }
        @AuraEnabled public String conflictingTermName { get; set; }
    }

    public class DivisionSessionConflictDetail {
        @AuraEnabled public String proposedSessionName { get; set; }
        @AuraEnabled public String proposedDateStr { get; set; }
        @AuraEnabled public String proposedTimeStr { get; set; }
        @AuraEnabled public String proposedCourseName { get; set; }
        @AuraEnabled public String proposedDivisionNames { get; set; }
        @AuraEnabled public String proposedProgramName { get; set; }
        @AuraEnabled public String proposedBatchName { get; set; }
        @AuraEnabled public String proposedBatchGroupName { get; set; }
        @AuraEnabled public String proposedTermName { get; set; }
        @AuraEnabled public String conflictingSessionName { get; set; }
        @AuraEnabled public String conflictingDateStr { get; set; }
        @AuraEnabled public String conflictingTimeStr { get; set; }
        /** Learning course name from Session.Course__c */
        @AuraEnabled public String conflictingCourseName { get; set; }
        @AuraEnabled public String conflictingDivisionNames { get; set; }
        @AuraEnabled public String conflictingProgramName { get; set; }
        @AuraEnabled public String conflictingBatchName { get; set; }
        @AuraEnabled public String conflictingBatchGroupName { get; set; }
        @AuraEnabled public String conflictingTermName { get; set; }
    }

    public class StudentSessionConflictDetail {
        @AuraEnabled public String proposedSessionName { get; set; }
        @AuraEnabled public String proposedDateStr { get; set; }
        @AuraEnabled public String proposedTimeStr { get; set; }
        @AuraEnabled public List<String> studentNames { get; set; }
        @AuraEnabled public String conflictingSessionName { get; set; }
        @AuraEnabled public String conflictingDateStr { get; set; }
        @AuraEnabled public String conflictingTimeStr { get; set; }
        @AuraEnabled public String conflictingCourseName { get; set; }
    }

}
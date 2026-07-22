/**
 * @description Controller for Division Enrollment LWC Component
 * Fetches Academic Term Enrollments not already in Division Enrollments
 * and creates Division Enrollment records
 * @author SPJIMR
 * @date 2025
 */
public with sharing class DivisionEnrollmentController {

    /**
     * @description Wrapper class for student enrollment data
     */
    public class StudentEnrollmentWrapper {
        @AuraEnabled public String enrollmentId;
        @AuraEnabled public String studentName;
        @AuraEnabled public String rollNumber;
        /**
         * Display labels from Specialisation_Master__r.Name (multiple joined with "; ").
         * Prefer Student_Specialisation__c linked via AcademicTermEnrollment.Batch_Enrollment__c (Program Cohort Member);
         * fallback to Student_Specialisation__c linked via Program_Enrolled__c (Program Enrollment).
         */
        @AuraEnabled public String specialisation;
        @AuraEnabled public Boolean selected;
        @AuraEnabled public String uniqueKey;
    }

    /**
     * @description Fetches Academic Term Enrollments for a Division's Term
     * that are not already part of any Division Enrollment with the same Division Group
     * Students can be in multiple divisions only if they have different Division Groups
     * @param divisionId The Division ID
     * @return List of StudentEnrollmentWrapper objects
     */
    @AuraEnabled(cacheable=false)
    public static List<StudentEnrollmentWrapper> getAvailableEnrollments(Id divisionId) {
        List<StudentEnrollmentWrapper> enrollments = new List<StudentEnrollmentWrapper>();
        
        try {
            // Get Division with Term and Division Group
            Division__c division = [
                SELECT Id, Term__c, Division_Group__c,SPJIMR_Specialisation__c,
       SPJIMR_Specialisation__r.Name,
       Division_Group__r.Is_Specialiation__c,
       Division_Group__r.isMutuallyExclusive__c
                FROM Division__c
                WHERE Id = :divisionId
                LIMIT 1
            ];
            
            if (division.Term__c == null) {
                throw new AuraHandledException('Division does not have a Term associated');
            }
            
            Id termId = division.Term__c;
            Id divisionGroupId = division.Division_Group__c;
            Boolean isMajorSpecDivision =
    division.Division_Group__r != null &&
    division.Division_Group__r.Is_Specialiation__c &&
    division.Division_Group__r.isMutuallyExclusive__c;

String divisionSpecName =
    division.SPJIMR_Specialisation__r != null
    ? division.SPJIMR_Specialisation__r.Name
    : '';

            
            
            // Get all Academic Term Enrollments for this Term
            List<AcademicTermEnrollment> termEnrollments = [
                SELECT Id,
                       LearnerAccountId,
                       LearnerAccount.Name,
                       Program_Enrolled__c,
                       Program_Enrolled__r.Student_Name__c,
                       Roll_Number__c,
                       Batch_Enrollment__c
                FROM AcademicTermEnrollment
                WHERE AcademicTermId = :termId
                AND LearnerAccountId != null
                ORDER BY LearnerAccount.Name, Roll_Number__c
            ];
            
            if (termEnrollments.isEmpty()) {
                return enrollments;
            }

            // Program Cohort Member Ids (Batch_Enrollment__c) → specialisation names
            Set<Id> cohortMemberIds = new Set<Id>();
            Set<Id> programEnrollmentIds = new Set<Id>();
            for (AcademicTermEnrollment ate : termEnrollments) {
                if (ate.Batch_Enrollment__c != null) {
                    cohortMemberIds.add(ate.Batch_Enrollment__c);
                }
                if (ate.Program_Enrolled__c != null) {
                    programEnrollmentIds.add(ate.Program_Enrolled__c);
                }
            }
            Map<Id, Set<String>> specialisationNamesByCohortMember = new Map<Id, Set<String>>();
            if (!cohortMemberIds.isEmpty()) {
                for (Student_Specialisation__c ss : [
                    SELECT Program_Cohort_Member__c, Specialisation_Master__r.Name
                    FROM Student_Specialisation__c
                    WHERE Program_Cohort_Member__c IN :cohortMemberIds
                ]) {
                    if (ss.Program_Cohort_Member__c == null
                        || ss.Specialisation_Master__r == null
                        || String.isBlank(ss.Specialisation_Master__r.Name)) {
                        continue;
                    }
                    if (!specialisationNamesByCohortMember.containsKey(ss.Program_Cohort_Member__c)) {
                        specialisationNamesByCohortMember.put(
                            ss.Program_Cohort_Member__c,
                            new Set<String>()
                        );
                    }
                    specialisationNamesByCohortMember.get(ss.Program_Cohort_Member__c)
                        .add(ss.Specialisation_Master__r.Name.trim());
                }
            }
            // Fallback: Program Enrollment → specialisation (when PCM link or PCM-linked SS rows are missing)
            Map<Id, Set<String>> specialisationNamesByProgramEnrollment = new Map<Id, Set<String>>();
            if (!programEnrollmentIds.isEmpty()) {
                for (Student_Specialisation__c ss : [
                    SELECT Program_Enrollment__c, Specialisation_Master__r.Name
                    FROM Student_Specialisation__c
                    WHERE Program_Enrollment__c IN :programEnrollmentIds
                ]) {
                    if (ss.Program_Enrollment__c == null
                        || ss.Specialisation_Master__r == null
                        || String.isBlank(ss.Specialisation_Master__r.Name)) {
                        continue;
                    }
                    if (!specialisationNamesByProgramEnrollment.containsKey(ss.Program_Enrollment__c)) {
                        specialisationNamesByProgramEnrollment.put(
                            ss.Program_Enrollment__c,
                            new Set<String>()
                        );
                    }
                    specialisationNamesByProgramEnrollment.get(ss.Program_Enrollment__c)
                        .add(ss.Specialisation_Master__r.Name.trim());
                }
            }
            
            // Get all existing Division Enrollments for these Academic Term Enrollments
            // Only consider those in Divisions with the same Division Group and same Term
            Set<Id> termEnrollmentIds = new Set<Id>();
            for (AcademicTermEnrollment ate : termEnrollments) {
                termEnrollmentIds.add(ate.Id);
            }
            
            // Query Division Enrollments with Division information to check Division Group
            Set<Id> existingEnrollmentIds = new Set<Id>();
            List<Division_Enrollment__c> existingDivisionEnrollments = [
                SELECT Academic_Term_Enrollment__c, 
                       Division__r.Division_Group__c,
                       Division__r.Term__c
                FROM Division_Enrollment__c
                WHERE Academic_Term_Enrollment__c IN :termEnrollmentIds
                AND Division__r.Term__c = :termId
            ];
            
            // Filter: Only exclude enrollments that are in a Division with the same Division Group
            // If current Division has no Division Group (null), exclude enrollments in Divisions with no Division Group
            // If current Division has a Division Group, exclude enrollments in Divisions with the same Division Group
            for (Division_Enrollment__c de : existingDivisionEnrollments) {
                // Check if the existing Division has the same Division Group as current Division
                if (divisionGroupId == null) {
                    // Current Division has no Division Group - exclude enrollments in Divisions with no Division Group
                    if (de.Division__r.Division_Group__c == null) {
                        existingEnrollmentIds.add(de.Academic_Term_Enrollment__c);
                    }
                } else {
                    // Current Division has a Division Group - exclude enrollments in Divisions with the same Division Group
                    if (de.Division__r.Division_Group__c == divisionGroupId) {
                        existingEnrollmentIds.add(de.Academic_Term_Enrollment__c);
                    }
                }
            }
            
            // Filter out enrollments that already have Division Enrollment records with same Division Group
            Integer rowNumber = 1;
            for (AcademicTermEnrollment ate : termEnrollments) {
                if (!existingEnrollmentIds.contains(ate.Id)) {
                    StudentEnrollmentWrapper wrapper = new StudentEnrollmentWrapper();
                    wrapper.enrollmentId = ate.Id;
                    wrapper.uniqueKey = ate.Id;
                    wrapper.studentName = (ate.Program_Enrolled__r != null && String.isNotBlank(ate.Program_Enrolled__r.Student_Name__c)) 
                        ? ate.Program_Enrolled__r.Student_Name__c 
                        : (ate.LearnerAccount != null && String.isNotBlank(ate.LearnerAccount.Name) ? ate.LearnerAccount.Name : '');
                    wrapper.rollNumber = (ate.Program_Enrolled__r != null && String.isNotBlank(ate.Roll_Number__c )) 
                        ? ate.Roll_Number__c 
                        : '';
                    wrapper.specialisation = resolveSpecialisationLabel(
                        ate,
                        specialisationNamesByCohortMember,
                        specialisationNamesByProgramEnrollment
                    );
                    wrapper.selected = false;
                    enrollments.add(wrapper);
                    rowNumber++;
                }
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching enrollments: ' + e.getMessage());
        }
        
        return enrollments;
    }

    /**
     * @description Creates Division Enrollment records for selected Academic Term Enrollments
     * Validates that students are not already in a Division with the same Division Group
     * @param divisionId The Division ID
     * @param enrollmentIds List of Academic Term Enrollment IDs to create Division Enrollments for
     * @return Number of records created
     */
    @AuraEnabled
    public static Integer createDivisionEnrollments(Id divisionId, List<Id> enrollmentIds) {
        if (enrollmentIds == null || enrollmentIds.isEmpty()) {
            throw new AuraHandledException('No enrollments selected');
        }
        
        try {
            // Get Division with Term and Division Group
            Division__c division = [
                SELECT Id, Term__c, Division_Group__c
                FROM Division__c
                WHERE Id = :divisionId
                LIMIT 1
            ];
            
            if (division.Term__c == null) {
                throw new AuraHandledException('Division does not have a Term associated');
            }
            
            Id termId = division.Term__c;
            Id divisionGroupId = division.Division_Group__c;
            
            // Validate: Check if any selected enrollments are already in a Division with the same Division Group
            List<Division_Enrollment__c> existingDivisionEnrollments = [
                SELECT Academic_Term_Enrollment__c, 
                       Division__r.Division_Group__c,
                       Division__r.Term__c
                FROM Division_Enrollment__c
                WHERE Academic_Term_Enrollment__c IN :enrollmentIds
                AND Division__r.Term__c = :termId
            ];
            
            // Get student names for conflicting enrollments
            Set<Id> conflictingEnrollmentIds = new Set<Id>();
            for (Division_Enrollment__c de : existingDivisionEnrollments) {
                Boolean isConflict = false;
                
                if (divisionGroupId == null) {
                    // Current Division has no Division Group - conflict if existing Division also has no Division Group
                    if (de.Division__r.Division_Group__c == null) {
                        isConflict = true;
                    }
                } else {
                    // Current Division has a Division Group - conflict if existing Division has the same Division Group
                    if (de.Division__r.Division_Group__c == divisionGroupId) {
                        isConflict = true;
                    }
                }
                
                if (isConflict) {
                    conflictingEnrollmentIds.add(de.Academic_Term_Enrollment__c);
                }
            }
            
            // If there are conflicts, get student names and throw error
            if (!conflictingEnrollmentIds.isEmpty()) {
                List<AcademicTermEnrollment> conflictingEnrollments = [
                    SELECT Id,
                           Program_Enrolled__r.Student_Name__c,
                           LearnerAccount.Name
                    FROM AcademicTermEnrollment
                    WHERE Id IN :conflictingEnrollmentIds
                ];
                
                List<String> conflictingStudentNames = new List<String>();
                for (AcademicTermEnrollment ate : conflictingEnrollments) {
                    String studentName = (ate.Program_Enrolled__r != null && 
                                       String.isNotBlank(ate.Program_Enrolled__r.Student_Name__c))
                        ? ate.Program_Enrolled__r.Student_Name__c
                        : (ate.LearnerAccount != null && String.isNotBlank(ate.LearnerAccount.Name) 
                           ? ate.LearnerAccount.Name : 'Unknown');
                    conflictingStudentNames.add(studentName);
                }
                
                String errorMessage = 'The following student(s) are already enrolled in a Division with the same Division Group in this Term: ' + 
                                     String.join(conflictingStudentNames, ', ');
                throw new AuraHandledException(errorMessage);
            }
            
            // Create Division Enrollment records
            List<Division_Enrollment__c> divisionEnrollments = new List<Division_Enrollment__c>();
            for (Id enrollmentId : enrollmentIds) {
                Division_Enrollment__c de = new Division_Enrollment__c();
                de.Division__c = divisionId;
                de.Academic_Term_Enrollment__c = enrollmentId;
                divisionEnrollments.add(de);
            }
            
            if (!divisionEnrollments.isEmpty()) {
                insert divisionEnrollments;
                return divisionEnrollments.size();
            }
            
            return 0;
            
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledException as-is
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating division enrollments: ' + e.getMessage());
        }
    }

    /**
     * Prefer specialisation from Student_Specialisation__c rows tied to Program Cohort Member (ATE.Batch_Enrollment__c);
     * if blank, use rows tied to Program Enrollment (ATE.Program_Enrolled__c).
     */
    private static String resolveSpecialisationLabel(
        AcademicTermEnrollment ate,
        Map<Id, Set<String>> namesByCohortMember,
        Map<Id, Set<String>> namesByProgramEnrollment
    ) {
        if (ate.Batch_Enrollment__c != null
            && namesByCohortMember.containsKey(ate.Batch_Enrollment__c)) {
            String fromPcm = joinSortedSpecNames(namesByCohortMember.get(ate.Batch_Enrollment__c));
            if (String.isNotBlank(fromPcm)) {
                return fromPcm;
            }
        }
        if (ate.Program_Enrolled__c != null
            && namesByProgramEnrollment.containsKey(ate.Program_Enrolled__c)) {
            return joinSortedSpecNames(namesByProgramEnrollment.get(ate.Program_Enrolled__c));
        }
        return '';
    }

    private static String joinSortedSpecNames(Set<String> names) {
        if (names == null || names.isEmpty()) {
            return '';
        }
        List<String> sorted = new List<String>(names);
        sorted.sort();
        return String.join(sorted, '; ');
    }
    /**
 * @description Creates Session Enrollment records for future sessions associated
 * with newly created Division Enrollment records. Prevents duplicate Session
 * Enrollments and links each record to the corresponding Session, Academic Term
 * Enrollment, and Division Enrollment.
 *
 * @param divisionEnrollments List of Division Enrollment records to process.
 */
    public static void createSessionEnrollments(
        List<Division_Enrollment__c> divisionEnrollments
    ) {
        
        System.debug('===== createSessionEnrollments START =====');
        
        Set<Id> divisionIds = new Set<Id>();
        Set<Id> academicTermEnrollmentIds = new Set<Id>();
        
        for (Division_Enrollment__c de : divisionEnrollments) {
            
            if (de.Division__c != null &&
                de.Academic_Term_Enrollment__c != null) {
                    
                    divisionIds.add(de.Division__c);
                    academicTermEnrollmentIds.add(de.Academic_Term_Enrollment__c);
                }
        }
        
        if (divisionIds.isEmpty()) {
            return;
        }
        
        // Get future sessions through Session_Division__c
        List<Session_Division__c> sessionDivisions = [
            SELECT Id,
            Division__c,
            Session__c,
            Session__r.Start_Time__c
            FROM Session_Division__c
            WHERE Division__c IN :divisionIds
            AND Session__r.Start_Time__c > :System.now()
        ];
        
        System.debug('Session Divisions Found = ' + sessionDivisions.size());
        
        if (sessionDivisions.isEmpty()) {
            return;
        }
        
        // Division -> Session mapping
        Map<Id, Set<Id>> divisionToSessions = new Map<Id, Set<Id>>();
        Set<Id> sessionIds = new Set<Id>();
        
        for (Session_Division__c sd : sessionDivisions) {
            
            sessionIds.add(sd.Session__c);
            
            if (!divisionToSessions.containsKey(sd.Division__c)) {
                divisionToSessions.put(
                    sd.Division__c,
                    new Set<Id>()
                );
            }
            
            divisionToSessions.get(sd.Division__c)
                .add(sd.Session__c);
        }
        Map<Id, Session__c> sessionMap = new Map<Id, Session__c>(
            [
                SELECT Id, Name
                FROM Session__c
                WHERE Id IN :sessionIds
            ]
        );
        Map<Id, AcademicTermEnrollment> ateMap =
            new Map<Id, AcademicTermEnrollment>(
                [
                    SELECT Id,
                    LearnerAccount.Name
                    FROM AcademicTermEnrollment
                    WHERE Id IN :academicTermEnrollmentIds
                ]
            );
        
        // Existing Session Enrollments
        Set<String> existingKeys = new Set<String>();
        
        for (Session_Enrollment__c se : [
            SELECT Id,
            Session__c,
            Academic_Term_Enrollment__c
            FROM Session_Enrollment__c
            WHERE Session__c IN :sessionIds
            AND Academic_Term_Enrollment__c IN :academicTermEnrollmentIds
        ]) {
            
            existingKeys.add(
                se.Academic_Term_Enrollment__c +
                '-' +
                se.Session__c
            );
        }
        
        List<Session_Enrollment__c> enrollmentsToInsert =
            new List<Session_Enrollment__c>();
        
        for (Division_Enrollment__c de : divisionEnrollments) {
            
            Set<Id> divisionSessionIds =
                divisionToSessions.get(de.Division__c);
            
            if (divisionSessionIds == null) {
                continue;
            }
            
            for (Id sessionId : divisionSessionIds) {
                
                String key =
                    de.Academic_Term_Enrollment__c +
                    '-' +
                    sessionId;
                
                if (!existingKeys.contains(key)) {
                    
                    Session__c sessionRec = sessionMap.get(sessionId);
                    
                    AcademicTermEnrollment ate =
                        ateMap.get(de.Academic_Term_Enrollment__c);
                    
                    String enrollmentName =
                        sessionRec.Name + '_' +
                        ate.LearnerAccount.Name;
                    
                    enrollmentsToInsert.add(
                        new Session_Enrollment__c(
                            Name = enrollmentName,
                            Session__c = sessionId,
                            Academic_Term_Enrollment__c =
                            de.Academic_Term_Enrollment__c,
                            Division_Enrollment__c = de.Id
                        )
                    );
                    
                    existingKeys.add(key);
                }
            }
        }
        
        System.debug(
            'Enrollments To Insert = ' +
            enrollmentsToInsert.size()
        );
        
        if (!enrollmentsToInsert.isEmpty()) {
            
            Database.SaveResult[] results =
                Database.insert(enrollmentsToInsert, false);
            
            for (Database.SaveResult sr : results) {
                
                if (!sr.isSuccess()) {
                    
                    for (Database.Error err : sr.getErrors()) {
                        
                        System.debug(
                            'SESSION ENROLLMENT ERROR => ' +
                            err.getMessage()
                        );
                    }
                }
            }
        }
    }
}
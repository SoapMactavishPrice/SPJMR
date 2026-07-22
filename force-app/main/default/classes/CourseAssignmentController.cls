public with sharing class CourseAssignmentController {

    @AuraEnabled
    public static List<CourseWrapper> getTermDetails(Id termId) {
        
        List<CourseWrapper> courseList = new List<CourseWrapper>();
        
            // Fetch Term + Program
            // AcademicTerm term = [
            //     SELECT AcademicYear.Batch__c
            //     FROM AcademicTerm 
            //     WHERE Id = :termId 
            //     LIMIT 1
            // ];
        
            // // 1️⃣ Courses already assigned to this Term
            // List<CourseOffering> existingOfferings = [SELECT ProgramCourse__c FROM CourseOffering WHERE Academic_Term__c = :termId];

            AcademicTerm term = [SELECT AcademicYearId, AcademicYear.Batch__c, Term_Start_Date__c, 	Term_End_Date__c FROM AcademicTerm WHERE Id = :termId LIMIT 1];
            Id academicYearId = term.AcademicYearId;
            Id batchId = term.AcademicYear.Batch__c;

            // Get Course Offerings for the CURRENT term only
            List<CourseOffering> currentTermOfferings = [
                SELECT ProgramCourse__c
                FROM CourseOffering
                WHERE Academic_Term__c = :termId
                AND ProgramCourse__c != NULL
            ];
        
            Set<Id> assignedToCurrentTerm = new Set<Id>();
            for (CourseOffering co : currentTermOfferings) {
                assignedToCurrentTerm.add(co.ProgramCourse__c);
            }

            // For single-term courses: Get ALL AcademicYears (Batch Groups) for the same Batch
            // Then get ALL terms across ALL Batch Groups to check if course is assigned anywhere
            Set<Id> allAcademicYearIds = new Set<Id>();
            for (AcademicYear ay : [SELECT Id FROM AcademicYear WHERE Batch__c = :batchId]) {
                allAcademicYearIds.add(ay.Id);
            }
            
            // Get ALL terms across ALL Batch Groups in the same Batch
            Set<Id> allTermIdsInBatch = new Set<Id>();
            for (AcademicTerm t : [SELECT Id FROM AcademicTerm WHERE AcademicYearId IN :allAcademicYearIds]) {
                allTermIdsInBatch.add(t.Id);
            }
            
            // Exclude current term from the set
            Set<Id> otherTermIdsInBatch = new Set<Id>(allTermIdsInBatch);
            otherTermIdsInBatch.remove(termId);
            
            // Get Course Offerings for ALL other terms in the same Batch (across all Batch Groups)
            List<CourseOffering> otherTermsOfferings = new List<CourseOffering>();
            if (!otherTermIdsInBatch.isEmpty()) {
                otherTermsOfferings = [
                    SELECT ProgramCourse__c
                    FROM CourseOffering
                    WHERE Academic_Term__c IN :otherTermIdsInBatch
                    AND ProgramCourse__c != NULL
                ];
            }
        
            Set<Id> assignedToOtherTerms = new Set<Id>();
            for (CourseOffering co : otherTermsOfferings) {
                assignedToOtherTerms.add(co.ProgramCourse__c);
            }
        
            // Get All Program Courses with Is_Multi_Term__c field
            List<Program_Courses__c> coursesList = [
                SELECT Id,
                       Learning_Course__c,
                       Learning_Course__r.Name,
                       Learning_Course__r.CourseNumber,
                       Program_Master__r.Name,
                       Batch__r.Batch_Code__c,
                       Is_Multi_Term__c,
                       Course_Type__c,
                       SPJIMR_Specialisation__r.Name,
                       SPJIMR_Specialisation__r.Specialisation_Name__r.Name
                FROM Program_Courses__c
                WHERE Batch__c = :term.AcademicYear.Batch__c
                AND Is_Active__c = true
            ];
            
            // For multi-term courses, check if End_Term__c is already set for any term in the batch
            // Get all CourseOfferings for this batch that have End_Term__c populated
            Set<Id> programCourseIds = new Set<Id>();
            for (Program_Courses__c pc : coursesList) {
                programCourseIds.add(pc.Id);
            }
            
            Map<Id, Id> courseToExistingEndTermMap = new Map<Id, Id>();
            if (!programCourseIds.isEmpty() && !allTermIdsInBatch.isEmpty()) {
                List<CourseOffering> existingOfferingsWithEndTerm = [
                    SELECT Id, ProgramCourse__c, End_Term__c
                    FROM CourseOffering
                    WHERE ProgramCourse__c IN :programCourseIds
                    AND End_Term__c != NULL
                    AND Academic_Term__c IN :allTermIdsInBatch
                ];
                
                // Map each course to its existing End_Term__c (if any)
                for (CourseOffering co : existingOfferingsWithEndTerm) {
                    if (!courseToExistingEndTermMap.containsKey(co.ProgramCourse__c)) {
                        courseToExistingEndTermMap.put(co.ProgramCourse__c, co.End_Term__c);
                    }
                }
            }
        
            // Filter courses based on Multi-Term logic
            for (Program_Courses__c pc : coursesList) {
                Boolean shouldInclude = false;
                Boolean isMultiTerm = pc.Is_Multi_Term__c == true;
                
                if (isMultiTerm) {
                    // Multi-term courses: Only exclude if already assigned to CURRENT term
                    // Can be added to other terms even if assigned to other terms
                    if (!assignedToCurrentTerm.contains(pc.Id)) {
                        shouldInclude = true;
                    }
                } else {
                    // Single-term courses: Exclude if assigned to ANY term (current or other)
                    if (!assignedToCurrentTerm.contains(pc.Id) && !assignedToOtherTerms.contains(pc.Id)) {
                        shouldInclude = true;
                    }
                }
                
                if (shouldInclude) {
                    CourseWrapper cw = new CourseWrapper();
                    cw.termId = termId;
                    cw.programName = pc.Program_Master__r.Name;
                    cw.courseId = pc.Id; // Program Course Id
                    cw.learningCourse = pc.Learning_Course__c;
                    cw.courseName = pc.Learning_Course__r.Name;
                    cw.courseCode = pc.Learning_Course__r.CourseNumber;
                    cw.courseType = pc.Course_Type__c != null ? pc.Course_Type__c : '';
                    cw.specialisation = resolveSpecialisationDisplayName(pc);
                    cw.isMultiTerm = isMultiTerm;
                    cw.termStartDate = term.Term_Start_Date__c != null 
                    ? term.Term_Start_Date__c 
                    : null;
                
                cw.termEndDate = term.Term_End_Date__c != null 
                    ? term.Term_End_Date__c 
                    : null;
                
                    
                    // For multi-term courses, check if End_Term__c already exists
                    if (isMultiTerm && courseToExistingEndTermMap.containsKey(pc.Id)) {
                        cw.existingEvaluationTermId = courseToExistingEndTermMap.get(pc.Id);
                        cw.isEvaluationTermReadOnly = true;
                    } else {
                        cw.existingEvaluationTermId = null;
                        cw.isEvaluationTermReadOnly = false;
                    }
                    
                    courseList.add(cw);
                }
            }
        
            return courseList;
        
    }

    /** Prefer Specialisation Master name; fall back to Batch Specialisation record Name. */
    private static String resolveSpecialisationDisplayName(Program_Courses__c pc) {
        if (pc == null || pc.SPJIMR_Specialisation__r == null) {
            return '';
        }
        if (pc.SPJIMR_Specialisation__r.Specialisation_Name__r != null
            && String.isNotBlank(pc.SPJIMR_Specialisation__r.Specialisation_Name__r.Name)) {
            return pc.SPJIMR_Specialisation__r.Specialisation_Name__r.Name;
        }
        return pc.SPJIMR_Specialisation__r.Name != null ? pc.SPJIMR_Specialisation__r.Name : '';
    }

    @AuraEnabled
    public static void saveEditableCourses(Id termId, List<CourseAssignmentWrapper> assignments, List<Id> courseIdsToDelete) {
        List<CourseOffering> toInsert = new List<CourseOffering>();
        List<CourseOffering> toUpdate = new List<CourseOffering>();
        List<CourseOffering> toDelete = new List<CourseOffering>();

        // Delete old records if provided
        if (courseIdsToDelete != null && !courseIdsToDelete.isEmpty()) {
            toDelete = [SELECT Id FROM CourseOffering WHERE Id IN :courseIdsToDelete];
        }

        for (CourseAssignmentWrapper a : assignments) {
            if (a.isMultiTerm == true && a.evaluationTermId != null) {
                // Multi-term course: Create/Update records
                
                // If evaluation term is read-only (already exists for batch), only create Record 1 for current term
                // Don't update/delete existing records
                if (a.isEvaluationTermReadOnly == true) {
                    // Only create Record 1 (current term with existing evaluation term) if it doesn't exist
                    List<CourseOffering> existingTerm1Record = [
                        SELECT Id, End_Term__c
                        FROM CourseOffering
                        WHERE Academic_Term__c = :termId
                        AND ProgramCourse__c = :a.courseId
                        AND End_Term__c = :a.evaluationTermId
                        LIMIT 1
                    ];
                    
                    if (existingTerm1Record.isEmpty()) {
                        // Create Record 1 only
                        CourseOffering co1 = new CourseOffering(
                            Academic_Term__c = termId,
                            End_Term__c = a.evaluationTermId,
                            ProgramCourse__c = a.courseId,
                            Name = a.courseName,
                            Instructor_Role__c = 'Instructor',
                            LearningCourseId = a.learningCourse,
                            StartDate = a.startDate,
                            EndDate = a.endDate
                        );
                        toInsert.add(co1);
                    } else {
                        // Update dates only for existing Record 1
                        CourseOffering existingRecord1 = existingTerm1Record[0];
                        existingRecord1.StartDate = a.startDate;
                        existingRecord1.EndDate = a.endDate;
                        toUpdate.add(existingRecord1);
                    }
                    // Skip Record 2 creation/update - don't touch existing records
                    continue;
                }
                
                // Special case: If termId == evaluationTermId, only create ONE record
                if (termId == a.evaluationTermId) {
                    // Check if record already exists
                    List<CourseOffering> existingRecord = [
                        SELECT Id, End_Term__c
                        FROM CourseOffering
                        WHERE Academic_Term__c = :termId
                        AND ProgramCourse__c = :a.courseId
                        AND End_Term__c = :a.evaluationTermId
                        LIMIT 1
                    ];
                    
                    if (!existingRecord.isEmpty()) {
                        // Update existing record
                        CourseOffering existing = existingRecord[0];
                        existing.StartDate = a.startDate;
                        existing.EndDate = a.endDate;
                        toUpdate.add(existing);
                    } else {
                        // Create new record
                        CourseOffering co = new CourseOffering(
                            Academic_Term__c = termId,
                            End_Term__c = a.evaluationTermId,
                            ProgramCourse__c = a.courseId,
                            Name = a.courseName,
                            Instructor_Role__c = 'Instructor',
                            LearningCourseId = a.learningCourse,
                            StartDate = a.startDate,
                            EndDate = a.endDate
                        );
                        toInsert.add(co);
                    }
                } else {
                    // termId != evaluationTermId: Create/Update TWO records
                    
                    // Check if Record 2 (Term2 with EndTerm = Term2) already exists and needs update
                    if (a.existingCourseOfferingId != null) {
                        // Update existing CourseOffering (Record 2) - update End_Term__c if it changed
                        CourseOffering existingCo = new CourseOffering(
                            Id = a.existingCourseOfferingId,
                            StartDate = a.startDate,
                            EndDate = a.endDate,
                            End_Term__c = a.evaluationTermId // Update End_Term__c to new evaluation term
                        );
                        toUpdate.add(existingCo);
                    }
                    
                    // Check if Record 1 (Term1 with EndTerm = Term2) exists
                    List<CourseOffering> existingTerm1Record = [
                        SELECT Id, End_Term__c
                        FROM CourseOffering
                        WHERE Academic_Term__c = :termId
                        AND ProgramCourse__c = :a.courseId
                        AND End_Term__c != NULL
                        LIMIT 1
                    ];
                    
                    if (!existingTerm1Record.isEmpty()) {
                        // Record 1 exists - check if End_Term__c needs to be updated
                        CourseOffering existingRecord1 = existingTerm1Record[0];
                        if (existingRecord1.End_Term__c != a.evaluationTermId) {
                            // End term changed - update it
                            existingRecord1.End_Term__c = a.evaluationTermId;
                            existingRecord1.StartDate = a.startDate;
                            existingRecord1.EndDate = a.endDate;
                            toUpdate.add(existingRecord1);
                        } else {
                            // Same end term - just update dates if needed
                            existingRecord1.StartDate = a.startDate;
                            existingRecord1.EndDate = a.endDate;
                            toUpdate.add(existingRecord1);
                        }
                    } else {
                        // Record 1 doesn't exist - create it
                        CourseOffering co1 = new CourseOffering(
                            Academic_Term__c = termId,
                            End_Term__c = a.evaluationTermId,
                            ProgramCourse__c = a.courseId,
                            Name = a.courseName,
                            Instructor_Role__c = 'Instructor',
                            LearningCourseId = a.learningCourse,
                            StartDate = a.startDate,
                            EndDate = a.endDate
                        );
                        toInsert.add(co1);
                    }
                    
                    // Check if Record 2 (Term2 with EndTerm = Term2) exists (if not updating)
                    if (a.existingCourseOfferingId == null) {
                        List<CourseOffering> existingTerm2Record = [
                            SELECT Id, End_Term__c
                            FROM CourseOffering
                            WHERE Academic_Term__c = :a.evaluationTermId
                            AND ProgramCourse__c = :a.courseId
                            AND End_Term__c = :a.evaluationTermId
                            LIMIT 1
                        ];
                        
                        if (existingTerm2Record.isEmpty()) {
                            // Record 2 doesn't exist - create it
                            CourseOffering co2 = new CourseOffering(
                                Academic_Term__c = a.evaluationTermId,
                                End_Term__c = a.evaluationTermId,
                                ProgramCourse__c = a.courseId,
                                Name = a.courseName,
                                Instructor_Role__c = 'Instructor',
                                LearningCourseId = a.learningCourse,
                                StartDate = a.startDate,
                                EndDate = a.endDate
                            );
                            toInsert.add(co2);
                        } else {
                            // Record 2 exists - update dates
                            CourseOffering existingRecord2 = existingTerm2Record[0];
                            existingRecord2.StartDate = a.startDate;
                            existingRecord2.EndDate = a.endDate;
                            toUpdate.add(existingRecord2);
                        }
                    }
                }
            } else {
                // Single-term course: Create 1 record
                toInsert.add(new CourseOffering(
                    Academic_Term__c = termId,
                    ProgramCourse__c = a.courseId,
                    Name = a.courseName,
                    Instructor_Role__c = 'Instructor',
                    LearningCourseId = a.learningCourse,
                    StartDate = a.startDate,
                    EndDate = a.endDate
                ));
            }
        }
        
        // Perform DML operations
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    public class CourseAssignmentWrapper {
        @AuraEnabled public Id courseId {get; set;}
        @AuraEnabled public Id learningCourse {get; set;}
        @AuraEnabled public Date startDate {get; set;}
        @AuraEnabled public Date endDate {get; set;}
        @AuraEnabled public String courseName {get; set;}
        @AuraEnabled public Boolean isMultiTerm {get; set;}
        @AuraEnabled public Id evaluationTermId {get; set;}
        @AuraEnabled public Id existingCourseOfferingId {get; set;} // For updating existing records
        @AuraEnabled public Boolean isEvaluationTermReadOnly {get; set;} // If true, don't update/delete existing records
    }



    public class CourseWrapper {
        @AuraEnabled public Id termId {get; set;}
        @AuraEnabled public Id learningCourse {get; set;}
        @AuraEnabled public String programName {get; set;}
        @AuraEnabled public Id courseId {get; set;}
        @AuraEnabled public String courseName {get; set;}
        @AuraEnabled public String courseCode {get; set;}
        @AuraEnabled public String courseType {get; set;}
        @AuraEnabled public String specialisation {get; set;}
        @AuraEnabled public Boolean isMultiTerm {get; set;}
        @AuraEnabled public Id existingEvaluationTermId {get; set;} // Existing End_Term__c for this course in the batch
        @AuraEnabled public Boolean isEvaluationTermReadOnly {get; set;} // Whether evaluation term should be read-only
        @AuraEnabled public Date termStartDate {get; set;} // Term's start date
        @AuraEnabled public Date termEndDate {get; set;} // Term's end date
    }
    
    @AuraEnabled(cacheable=true)
    public static List<EvaluationTermWrapper> getEvaluationTermsForBatch(Id termId) {
        List<EvaluationTermWrapper> termList = new List<EvaluationTermWrapper>();
        
        if (termId == null) {
            return termList;
        }
        
        try {
            // Get the AcademicTerm and its Batch
            AcademicTerm term = [
                SELECT Id, AcademicYearId, AcademicYear.Batch__c
                FROM AcademicTerm
                WHERE Id = :termId
                LIMIT 1
            ];
            
            if (term.AcademicYear == null || term.AcademicYear.Batch__c == null) {
                return termList;
            }
            
            // Get ALL AcademicYears (Batch Groups) for the same Batch
            Set<Id> allAcademicYearIds = new Set<Id>();
            for (AcademicYear ay : [SELECT Id FROM AcademicYear WHERE Batch__c = :term.AcademicYear.Batch__c]) {
                allAcademicYearIds.add(ay.Id);
            }
            
            // Get ALL AcademicTerms across ALL Batch Groups in the same Batch
            List<AcademicTerm> academicTerms = [
                SELECT Id, Name, Term_Code__c
                FROM AcademicTerm
                WHERE AcademicYearId IN :allAcademicYearIds
                ORDER BY Name
            ];
            
            Integer termNumber = 1;
            for (AcademicTerm at : academicTerms) {
                EvaluationTermWrapper wrapper = new EvaluationTermWrapper();
                wrapper.id = at.Id;
                wrapper.name = at.Name != null ? at.Name : 'Term ' + termNumber;
                wrapper.termCode = at.Term_Code__c;
                wrapper.termNumber = termNumber++;
                termList.add(wrapper);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching evaluation terms: ' + e.getMessage());
        }
        
        return termList;
    }
    
    @AuraEnabled
    public static List<ExistingCourseOfferingWrapper> getExistingCourseOfferingsForEvaluationTerm(Id programCourseId, Id evaluationTermId) {
        List<ExistingCourseOfferingWrapper> offerings = new List<ExistingCourseOfferingWrapper>();
        
        if (programCourseId == null || evaluationTermId == null) {
            return offerings;
        }
        
        try {
            // Get CourseOfferings where End_Term__c matches the evaluation term
            List<CourseOffering> existingOfferings = [
                SELECT Id, Academic_Term__c, End_Term__c, StartDate, EndDate,
                       Academic_Term__r.Name
                FROM CourseOffering
                WHERE ProgramCourse__c = :programCourseId
                AND End_Term__c = :evaluationTermId
            ];
            
            for (CourseOffering co : existingOfferings) {
                ExistingCourseOfferingWrapper wrapper = new ExistingCourseOfferingWrapper();
                wrapper.courseOfferingId = co.Id;
                wrapper.academicTermId = co.Academic_Term__c;
                wrapper.academicTermName = co.Academic_Term__r != null ? co.Academic_Term__r.Name : '';
                wrapper.endTermId = co.End_Term__c;
                wrapper.startDate = co.StartDate;
                wrapper.endDate = co.EndDate;
                offerings.add(wrapper);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching existing course offerings: ' + e.getMessage());
        }
        
        return offerings;
    }
    
    @AuraEnabled
    public static BatchCourseOfferingsResponse getBatchCourseOfferings(Id termId, Id evaluationTermId) {
        BatchCourseOfferingsResponse response = new BatchCourseOfferingsResponse();
        response.readOnlyOfferings = new List<BatchCourseOfferingWrapper>();
        response.editableOfferings = new List<BatchCourseOfferingWrapper>();
        
        if (termId == null) {
            return response;
        }
        
        try {
            // Get the batch from the term
            AcademicTerm term = [SELECT AcademicYearId, AcademicYear.Batch__c FROM AcademicTerm WHERE Id = :termId LIMIT 1];
            Id batchId = term.AcademicYear.Batch__c;
            
            if (batchId == null) {
                return response;
            }
            
            // Get all Program Courses for this batch
            List<Program_Courses__c> programCourses = [
                SELECT Id, Learning_Course__r.Name, Learning_Course__r.CourseNumber
                FROM Program_Courses__c
                WHERE Batch__c = :batchId
                AND Is_Active__c = true
            ];
            
            Set<Id> programCourseIds = new Set<Id>();
            Map<Id, String> programCourseNameMap = new Map<Id, String>();
            Map<Id, String> programCourseCodeMap = new Map<Id, String>();
            
            for (Program_Courses__c pc : programCourses) {
                programCourseIds.add(pc.Id);
                programCourseNameMap.put(pc.Id, pc.Learning_Course__r != null ? pc.Learning_Course__r.Name : '');
                programCourseCodeMap.put(pc.Id, pc.Learning_Course__r != null ? pc.Learning_Course__r.CourseNumber : '');
            }
            
            // Get ALL CourseOfferings for this batch where End_Term__c is populated (read-only)
            List<CourseOffering> allOfferingsWithEndTerm = [
                SELECT Id, Academic_Term__c, End_Term__c, StartDate, EndDate, ProgramCourse__c,
                       Academic_Term__r.Name, End_Term__r.Name,
                       ProgramCourse__r.Learning_Course__r.Name,
                       ProgramCourse__r.Learning_Course__r.CourseNumber
                FROM CourseOffering
                WHERE ProgramCourse__c IN :programCourseIds
                AND End_Term__c != NULL
                ORDER BY ProgramCourse__r.Learning_Course__r.Name, Academic_Term__r.Name
            ];
            
            // Separate read-only and editable offerings
            for (CourseOffering co : allOfferingsWithEndTerm) {
                BatchCourseOfferingWrapper wrapper = new BatchCourseOfferingWrapper();
                wrapper.courseOfferingId = co.Id;
                wrapper.programCourseId = co.ProgramCourse__c;
                wrapper.courseName = co.ProgramCourse__r != null && co.ProgramCourse__r.Learning_Course__r != null 
                    ? co.ProgramCourse__r.Learning_Course__r.Name 
                    : programCourseNameMap.get(co.ProgramCourse__c);
                wrapper.courseCode = co.ProgramCourse__r != null && co.ProgramCourse__r.Learning_Course__r != null 
                    ? co.ProgramCourse__r.Learning_Course__r.CourseNumber 
                    : programCourseCodeMap.get(co.ProgramCourse__c);
                wrapper.academicTermId = co.Academic_Term__c;
                wrapper.academicTermName = co.Academic_Term__r != null ? co.Academic_Term__r.Name : '';
                wrapper.endTermId = co.End_Term__c;
                wrapper.endTermName = co.End_Term__r != null ? co.End_Term__r.Name : '';
                wrapper.startDate = co.StartDate;
                wrapper.endDate = co.EndDate;
                
                // If evaluation term is selected and this offering matches it, make it editable
                if (evaluationTermId != null && co.End_Term__c == evaluationTermId) {
                    response.editableOfferings.add(wrapper);
                } else {
                    // Otherwise, it's read-only
                    response.readOnlyOfferings.add(wrapper);
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching batch course offerings: ' + e.getMessage());
        }
        
        return response;
    }
    
    public class EvaluationTermWrapper {
        @AuraEnabled public Id id {get; set;}
        @AuraEnabled public String name {get; set;}
        @AuraEnabled public String termCode {get; set;}
        @AuraEnabled public Integer termNumber {get; set;}
    }
    
    public class ExistingCourseOfferingWrapper {
        @AuraEnabled public Id courseOfferingId {get; set;}
        @AuraEnabled public Id academicTermId {get; set;}
        @AuraEnabled public String academicTermName {get; set;}
        @AuraEnabled public Id endTermId {get; set;}
        @AuraEnabled public Datetime startDate {get; set;}
        @AuraEnabled public Datetime endDate {get; set;}
    }
    
    public class BatchCourseOfferingWrapper {
        @AuraEnabled public Id courseOfferingId {get; set;}
        @AuraEnabled public Id programCourseId {get; set;}
        @AuraEnabled public String courseName {get; set;}
        @AuraEnabled public String courseCode {get; set;}
        @AuraEnabled public Id academicTermId {get; set;}
        @AuraEnabled public String academicTermName {get; set;}
        @AuraEnabled public Id endTermId {get; set;}
        @AuraEnabled public String endTermName {get; set;}
        @AuraEnabled public Datetime startDate {get; set;}
        @AuraEnabled public Datetime endDate {get; set;}
    }
    
    public class BatchCourseOfferingsResponse {
        @AuraEnabled public List<BatchCourseOfferingWrapper> readOnlyOfferings {get; set;}
        @AuraEnabled public List<BatchCourseOfferingWrapper> editableOfferings {get; set;}
    } 
}
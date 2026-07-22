/**
* Aura-backed data for batch course assignment UIs and related pickers (courses, specialisations).
*/
public with sharing class BatchCourseAssignmentController {
    
    /**
* Resolves the Program Cohort (batch) stored on an academic term.
*
* @param termId Academic term Id (Division__c.Term__c).
* @return ProgramCohort Id from AcademicTerm.Batch_Name__c, or null when missing.
*/
    private static Id resolveProgramCohortIdForTerm(Id termId) {
        Id result = null;
        if (termId != null) {
            List<AcademicTerm> terms = [
                SELECT Batch_Name__c
                FROM AcademicTerm
                WHERE Id = :termId
                LIMIT 1
            ];
            if (!terms.isEmpty()) {
                result = terms[0].Batch_Name__c;
            }
        }
        return result;
    }
    
    /**
* Active specialisations for the batch linked to the given term (Term → Batch_Name__c → ProgramCohort).
*
* @param termId Academic term Id used as Division__c.Term__c.
* @return Wrapper rows for Aura picklists; empty when term or batch is unknown.
*/
    @AuraEnabled(cacheable=true)
    public static List<SpecialisationWrapper> getSpecialisationsForDivisionTerm(Id termId) {
        return getBatchSpecialisations(resolveProgramCohortIdForTerm(termId));
    }
    
    @AuraEnabled(cacheable=true)
    public static List<CourseWrapper> getAllCourses() {
        List<CourseWrapper> courseList = new List<CourseWrapper>();
        
        try {
            // Query only active LearningCourse records
            List<LearningCourse> courses = [
                SELECT Id, Name, CourseNumber
                FROM LearningCourse
                WHERE Is_Active__c  = true
                ORDER BY Name
            ];
            
            for (LearningCourse course : courses) {
                CourseWrapper cw = new CourseWrapper();
                cw.courseId = course.Id;
                cw.courseName = course.Name;
                cw.courseNumber = course.CourseNumber;
                courseList.add(cw);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching courses: ' + e.getMessage());
        }
        
        return courseList;
    }
    
    @AuraEnabled(cacheable=false)
    public static List<ExistingProgramCourseWrapper> getExistingProgramCourses(Id batchId) {
        List<ExistingProgramCourseWrapper> existingCourses = new List<ExistingProgramCourseWrapper>();
        
        if (batchId == null) {
            return existingCourses;
        }
        
        try {
            List<Program_Courses__c> programCourses = [
                SELECT
                Id,
                Learning_Course__c,
                Is_Multi_Term__c,
                Course_Type__c,
                SPJIMR_Specialisation__c,
                Is_Host_Course__c
                FROM Program_Courses__c
                WHERE Batch__c = :batchId
            ];
            
             // Collect Program Course IDs
            Set<Id> programCourseIds = new Set<Id>();
            for (Program_Courses__c pc : programCourses) {
                     programCourseIds.add(pc.Id);
            }
            
             // Find Program Courses already used in Course Offerings
        	Set<Id> lockedProgramCourseIds = new Set<Id>();

       		if (!programCourseIds.isEmpty()) {
            for (CourseOffering co : [
                SELECT ProgramCourse__c
                FROM CourseOffering
                WHERE ProgramCourse__c IN :programCourseIds
            ]) {
                lockedProgramCourseIds.add(co.ProgramCourse__c);
               }
            }
            
            for (Program_Courses__c pc : programCourses) {
                ExistingProgramCourseWrapper wrapper = new ExistingProgramCourseWrapper();
                wrapper.programCourseId = pc.Id;
                wrapper.learningCourseId = pc.Learning_Course__c;
                wrapper.isMultiTerm = pc.Is_Multi_Term__c;
                wrapper.courseType = pc.Course_Type__c;
                wrapper.specialisationId = pc.SPJIMR_Specialisation__c;
                wrapper.isHostCourse = pc.Is_Host_Course__c;
                wrapper.isLocked = lockedProgramCourseIds.contains(pc.Id);
                existingCourses.add(wrapper);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching existing program courses: ' + e.getMessage());
        }
        
        return existingCourses;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<SpecialisationWrapper> getBatchSpecialisations(Id batchId) {
        List<SpecialisationWrapper> specialisationList = new List<SpecialisationWrapper>();
        
        if (batchId == null) {
            return specialisationList;
        }
        
        try {
            List<Specialisation__c> specialisations = [
                SELECT Id, Name, Specialisation_Name__c, Specialisation_Name__r.Name, Is_Active__c
                FROM Specialisation__c
                WHERE Batch__c = :batchId
                AND Is_Active__c = true
                ORDER BY Specialisation_Name__r.Name NULLS LAST, Name
            ];
            
            System.debug('Found ' + specialisations.size() + ' specialisations for batch: ' + batchId);
            
            for (Specialisation__c spec : specialisations) {
                SpecialisationWrapper sw = new SpecialisationWrapper();
                sw.specialisationId = spec.Id;
                // Use Specialisation_Name__r.Name if available, otherwise use Name (auto-number)
                if (spec.Specialisation_Name__r != null && String.isNotBlank(spec.Specialisation_Name__r.Name)) {
                    sw.specialisationName = spec.Specialisation_Name__r.Name;
                } else if (String.isNotBlank(spec.Name)) {
                    sw.specialisationName = spec.Name;
                } else {
                    sw.specialisationName = 'Specialisation ' + spec.Id;
                }
                specialisationList.add(sw);
                System.debug('Added specialisation: ' + sw.specialisationName + ' (ID: ' + sw.specialisationId + ')');
            }
        } catch (Exception e) {
            System.debug('Error fetching batch specialisations: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error fetching batch specialisations: ' + e.getMessage());
        }
        
        return specialisationList;
    }
    
    @AuraEnabled(cacheable=true)
    public static Boolean getBatchIsSpecialisationProgram(Id batchId) {
        if (batchId == null) {
            return false;
        }
        
        try {
            ProgramCohort batch = [
                SELECT SPJIMR_Is_Specialisation_Program__c
                FROM ProgramCohort
                WHERE Id = :batchId
                LIMIT 1
            ];
            return batch.SPJIMR_Is_Specialisation_Program__c == true;
        } catch (Exception e) {
            System.debug('Error fetching batch is specialisation program: ' + e.getMessage());
            return false;
        }
    }
    
    @AuraEnabled
    public static void saveProgramCourses(Id batchId, List<ProgramCourseWrapper> courseSelections, List<Id> programCourseIdsToDelete) {
        if (batchId == null) {
            throw new AuraHandledException('Batch ID is required');
        }
        
        // Check if there's anything to process
        if ((courseSelections == null || courseSelections.isEmpty()) && 
            (programCourseIdsToDelete == null || programCourseIdsToDelete.isEmpty())) {
                return; // Nothing to do
            }
        
        // Get the Program from the Batch (ProgramCohort)
        Id programId = null;
        try {
            ProgramCohort batch = [
                SELECT ProgramId, Program_Name__c
                FROM ProgramCohort
                WHERE Id = :batchId
                LIMIT 1
            ];
            // Use ProgramId (MasterDetail) if available, otherwise use Program_Name__c (Lookup)
            programId = batch.ProgramId != null ? batch.ProgramId : batch.Program_Name__c;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Batch Program: ' + e.getMessage());
        }
        
        if (programId == null) {
            throw new AuraHandledException('Batch does not have an associated Program');
        }
        
        List<Program_Courses__c> programCoursesToInsert = new List<Program_Courses__c>();
        List<Program_Courses__c> programCoursesToUpdate = new List<Program_Courses__c>();
        List<Program_Courses__c> programCoursesToDelete = new List<Program_Courses__c>();
        
        List<SPJIMR_Specialisation_Course__c> specialisationCoursesToInsert = new List<	SPJIMR_Specialisation_Course__c>(); //859
        
        // Delete records for unselected courses
        if (programCourseIdsToDelete != null && !programCourseIdsToDelete.isEmpty()) {
            try {
                programCoursesToDelete = [
                    SELECT Id
                    FROM Program_Courses__c
                    WHERE Id IN :programCourseIdsToDelete AND Batch__c = :batchId
                ];
            } catch (Exception e) {
                throw new AuraHandledException('Error fetching program courses to delete: ' + e.getMessage());
            }
        }
        
        // Get existing Program_Courses__c records for this batch
        Map<Id, Program_Courses__c> existingCoursesMap = new Map<Id, Program_Courses__c>();
        try {
            List<Program_Courses__c> existingCourses = [
                SELECT
                Id,
                Learning_Course__c,
                Is_Multi_Term__c,
                Course_Type__c,
                SPJIMR_Specialisation__c,
                Is_Host_Course__c
                FROM Program_Courses__c
                WHERE Batch__c = :batchId
            ];
            
            for (Program_Courses__c pc : existingCourses) {
                existingCoursesMap.put(pc.Learning_Course__c, pc);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching existing program courses: ' + e.getMessage());
        }
        /*859 start*/
        Set<Id> specialisationIds = new Set<Id>();
        Set<Id> learningCourseIds = new Set<Id>();
        Map<Id, Id> specialisationToMasterMap = new Map<Id, Id>();
        Set<Id> masterSpecialisationIds = new Set<Id>();
        if (courseSelections != null) {
            
            for (ProgramCourseWrapper wrapper : courseSelections) {
                
                if (wrapper.courseType == 'Specialisation'
                    && wrapper.specialisationId != null
                    && wrapper.learningCourseId != null) {
                        
                        specialisationIds.add(wrapper.specialisationId);
                        learningCourseIds.add(wrapper.learningCourseId);
                    }
            }
        }
        if (!specialisationIds.isEmpty()) {
            
            for (Specialisation__c spec : [ 
                SELECT Id, Specialisation_Name__c
   				FROM Specialisation__c
    			WHERE Id IN :specialisationIds
				]) {
    			if (spec.Specialisation_Name__c != null) {
        			specialisationToMasterMap.put(
            		spec.Id,
            		spec.Specialisation_Name__c);

        	masterSpecialisationIds.add(spec.Specialisation_Name__c);
    			}
			}
        }
        
        Set<String> existingSpecCourseKeys = new Set<String>();
        
        if (!specialisationIds.isEmpty()
            && !learningCourseIds.isEmpty()) {
                
                for (SPJIMR_Specialisation_Course__c sc : [
                    
                    SELECT
                    Id,
                    SPJIMR_Specialisation_Master__c,
                    SPJIMR_Course__c
                    FROM SPJIMR_Specialisation_Course__c
                    WHERE SPJIMR_Specialisation_Master__c IN :masterSpecialisationIds
                    AND SPJIMR_Course__c IN :learningCourseIds
                    
                ]) {
                    
                    String key =
                        String.valueOf(sc.SPJIMR_Specialisation_Master__c)
                        + '-'
                        + String.valueOf(sc.SPJIMR_Course__c);
                    
                    existingSpecCourseKeys.add(key);
                }
            }
        /*859 end*/
        try {
            
            // Process course selections for insert/update
            if (courseSelections != null && !courseSelections.isEmpty()) {
                for (ProgramCourseWrapper wrapper : courseSelections) {
                    if (wrapper.selected && wrapper.learningCourseId != null) {
                        // Check if this course already exists (by programCourseId or by lookup)
                        if (wrapper.programCourseId != null && existingCoursesMap.containsKey(wrapper.learningCourseId)) {
                            // Update existing record
                            Program_Courses__c existingPc = existingCoursesMap.get(wrapper.learningCourseId);
                            existingPc.Is_Multi_Term__c = wrapper.isMultiTerm;
                            existingPc.Is_Host_Course__c = resolveIsHostCourse(wrapper);
                            if (String.isNotBlank(wrapper.courseType)) {
                                existingPc.Course_Type__c = wrapper.courseType;
                            }
                            if (wrapper.specialisationId != null) {
                                existingPc.SPJIMR_Specialisation__c = wrapper.specialisationId;
                            } else {
                                existingPc.SPJIMR_Specialisation__c = null;
                            }
                            // Ensure Program_Master__c is set
                            if (programId != null) {
                                existingPc.Program_Master__c = programId;
                            }
                            programCoursesToUpdate.add(existingPc);
                        } else if (existingCoursesMap.containsKey(wrapper.learningCourseId)) {
                            // Update existing record (found by lookup)
                            Program_Courses__c existingPc = existingCoursesMap.get(wrapper.learningCourseId);
                            existingPc.Is_Multi_Term__c = wrapper.isMultiTerm;
                            existingPc.Is_Host_Course__c = resolveIsHostCourse(wrapper);
                            if (String.isNotBlank(wrapper.courseType)) {
                                existingPc.Course_Type__c = wrapper.courseType;
                            }
                            if (wrapper.specialisationId != null) {
                                existingPc.SPJIMR_Specialisation__c = wrapper.specialisationId;
                            } else {
                                existingPc.SPJIMR_Specialisation__c = null;
                            }
                            // Ensure Program_Master__c is set
                            if (programId != null) {
                                existingPc.Program_Master__c = programId;
                            }
                            programCoursesToUpdate.add(existingPc);
                        } else {
                            // Insert new record
                            Program_Courses__c pc = new Program_Courses__c();
                            pc.Batch__c = batchId;
                            pc.Learning_Course__c = wrapper.learningCourseId;
                            pc.Is_Multi_Term__c = wrapper.isMultiTerm;
                            pc.Is_Host_Course__c = resolveIsHostCourse(wrapper);
                            if (String.isNotBlank(wrapper.courseType)) {
                                pc.Course_Type__c = wrapper.courseType;
                            }
                            if (wrapper.specialisationId != null) {
                                pc.SPJIMR_Specialisation__c = wrapper.specialisationId;
                            }
                            // Set Program_Master__c from Batch's Program
                            if (programId != null) {
                                pc.Program_Master__c = programId;
                            }
                            programCoursesToInsert.add(pc);
                        }
                        /*859 start*/
                        if (wrapper.courseType == 'Specialisation' && wrapper.specialisationId != null && wrapper.learningCourseId != null) {
                            Id masterId = specialisationToMasterMap.get(wrapper.specialisationId);
                                String key =
                                    String.valueOf(masterId)
                                    + '-'
                                    + String.valueOf(
                                        wrapper.learningCourseId
                                    );
                                
                                // Prevent duplicates
                                if (!existingSpecCourseKeys.contains(key)) {
                                    SPJIMR_Specialisation_Course__c sc = new SPJIMR_Specialisation_Course__c();
                                    sc.SPJIMR_Specialisation_Master__c = specialisationToMasterMap.get(wrapper.specialisationId);
                                    sc.SPJIMR_Course__c = wrapper.learningCourseId;                                    
                                    specialisationCoursesToInsert.add(sc);                                    
                                    existingSpecCourseKeys.add(key);
                                }
                            }/*859 end*/
                    }
                }
            }
            
            // Perform DML operations
            if (!programCoursesToDelete.isEmpty()) {
                delete programCoursesToDelete;
            }
            
            if (!programCoursesToInsert.isEmpty()) {
                insert programCoursesToInsert;
            }
            
            if (!programCoursesToUpdate.isEmpty()) {
                update programCoursesToUpdate;
            }
            /*859 start*/
            if (!specialisationCoursesToInsert.isEmpty()) {
                insert specialisationCoursesToInsert;
            }
            /*859 end*/
        } catch (Exception e) {
            throw new AuraHandledException('Error saving program courses: ' + e.getMessage());
        }
    }
    
    /**
* Default for host course is true when the LWC does not send the flag.
*/
    private static Boolean resolveIsHostCourse(ProgramCourseWrapper wrapper) {
        if (wrapper == null) {
            return true;
        }
        if (wrapper.isHostCourse == null) {
            return true;
        }
        return wrapper.isHostCourse;
    }
    
    public class CourseWrapper {
        @AuraEnabled public Id courseId {get; set;}
        @AuraEnabled public String courseName {get; set;}
        @AuraEnabled public String courseNumber {get; set;}
    }
    
    public class ProgramCourseWrapper {
        @AuraEnabled public Id learningCourseId {get; set;}
        @AuraEnabled public Boolean selected {get; set;}
        @AuraEnabled public Boolean isMultiTerm {get; set;}
        @AuraEnabled public String courseType {get; set;}
        @AuraEnabled public String courseName {get; set;}
        @AuraEnabled public Id programCourseId {get; set;}
        @AuraEnabled public Id specialisationId {get; set;}
        /** When true, LMS will reference this Program_Courses__c row (via trigger). Defaults to true. */
        @AuraEnabled public Boolean isHostCourse {get; set;}
    }
    
    public class ExistingProgramCourseWrapper {
        @AuraEnabled public Id programCourseId {get; set;}
        @AuraEnabled public Id learningCourseId {get; set;}
        @AuraEnabled public Boolean isMultiTerm {get; set;}
        @AuraEnabled public String courseType {get; set;}
        @AuraEnabled public Id specialisationId {get; set;}
        @AuraEnabled public Boolean isHostCourse {get; set;}
        @AuraEnabled public Boolean isLocked {get; set;}
    }
    
    public class SpecialisationWrapper {
        @AuraEnabled public Id specialisationId {get; set;}
        @AuraEnabled public String specialisationName {get; set;}
    }
}
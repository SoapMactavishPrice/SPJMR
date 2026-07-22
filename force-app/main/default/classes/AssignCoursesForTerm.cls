public with sharing class AssignCoursesForTerm {
    
    @AuraEnabled(cacheable=true)
    public static List<ProgramCourseWrapper> getUnassignedProgramCourses(Id termId) {
        List<ProgramCourseWrapper> courseList = new List<ProgramCourseWrapper>();
        
        if (termId == null) {
            return courseList;
        }
        
        try {
            // Get the Term record and its Batch
            Term__c term = [
                SELECT Id, Batch__c
                FROM Term__c
                WHERE Id = :termId
                LIMIT 1
            ];
            
            if (term.Batch__c == null) {
                return courseList;
            }
            
            // Get all Program Courses related to the same Batch
            List<Program_Courses__c> programCourses = [
                SELECT Id, Name, Learning_Course__c, Learning_Course__r.Name, 
                       Learning_Course__r.CourseNumber, Is_Multi_Term__c,
                       Program_Course_Code__c
                FROM Program_Courses__c
                WHERE Batch__c = :term.Batch__c
                ORDER BY Learning_Course__r.Name
            ];
            
            // Get all Course Offerings for this batch to find which courses are already assigned to any term
            Set<Id> assignedProgramCourseIds = new Set<Id>();
            List<CourseOffering> existingOfferings = [
                SELECT Id, ProgramCourse__c
                FROM CourseOffering
                WHERE ProgramCourse__c IN :(new Map<Id, Program_Courses__c>(programCourses).keySet())
            ];
            
            for (CourseOffering co : existingOfferings) {
                if (co.ProgramCourse__c != null) {
                    assignedProgramCourseIds.add(co.ProgramCourse__c);
                }
            }
            
            // Build wrapper list - only include courses that haven't been assigned to any term
            Integer rowNumber = 1;
            for (Program_Courses__c pc : programCourses) {
                if (!assignedProgramCourseIds.contains(pc.Id)) {
                    ProgramCourseWrapper wrapper = new ProgramCourseWrapper();
                    wrapper.programCourseId = pc.Id;
                    wrapper.courseName = pc.Learning_Course__r.Name;
                    wrapper.courseNumber = pc.Learning_Course__r.CourseNumber != null ? pc.Learning_Course__r.CourseNumber : '';
                    wrapper.isMultiTerm = pc.Is_Multi_Term__c != null ? pc.Is_Multi_Term__c : false;
                    wrapper.programCourseCode = pc.Program_Course_Code__c;
                    wrapper.rowNumber = rowNumber++;
                    wrapper.selected = false;
                    wrapper.startDate = null;
                    wrapper.endDate = null;
                    wrapper.evaluationTermId = null;
                    courseList.add(wrapper);
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching program courses: ' + e.getMessage());
        }
        
        return courseList;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<EvaluationTermWrapper> getEvaluationTermsForBatchGroup(Id termId) {
        List<EvaluationTermWrapper> termList = new List<EvaluationTermWrapper>();
        
        if (termId == null) {
            return termList;
        }
        
        try {
            // Get the Term record and its Batch
            Term__c term = [
                SELECT Id, Batch__c
                FROM Term__c
                WHERE Id = :termId
                LIMIT 1
            ];
            
            if (term.Batch__c == null) {
                return termList;
            }
            
            // Get all AcademicTerms for the same Batch using Batch_Name__c
            // This gets all terms in the batch group
            List<AcademicTerm> academicTerms = [
                SELECT Id, Name, Term_Code__c
                FROM AcademicTerm
                WHERE Batch_Name__c = :term.Batch__c
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
    public static void createCourseOfferings(Id termId, List<CourseOfferingWrapper> courseOfferings) {
        if (termId == null) {
            throw new AuraHandledException('Term ID is required');
        }
        
        if (courseOfferings == null || courseOfferings.isEmpty()) {
            throw new AuraHandledException('At least one course offering is required');
        }
        
        try {
            // Get the Term record to get the Academic Term
            Term__c term = [
                SELECT Id, Term__c
                FROM Term__c
                WHERE Id = :termId
                LIMIT 1
            ];
            
            List<CourseOffering> offeringsToInsert = new List<CourseOffering>();
            
            for (CourseOfferingWrapper wrapper : courseOfferings) {
                if (wrapper.programCourseId == null || wrapper.startDate == null || wrapper.endDate == null) {
                    continue;
                }
                
                CourseOffering co = new CourseOffering();
                co.ProgramCourse__c = wrapper.programCourseId;
                co.StartDate = wrapper.startDate;
                co.EndDate = wrapper.endDate;
                
                // If evaluation term is provided, use it; otherwise use the term's academic term
                if (wrapper.evaluationTermId != null) {
                    co.Academic_Term__c = wrapper.evaluationTermId;
                } else {
                    co.Academic_Term__c = term.Term__c; // Set the Academic Term from Term__c.Term__c
                }
                
                offeringsToInsert.add(co);
            }
            
            if (!offeringsToInsert.isEmpty()) {
                insert offeringsToInsert;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error creating course offerings: ' + e.getMessage());
        }
    }
    
    public class ProgramCourseWrapper {
        @AuraEnabled public Id programCourseId {get; set;}
        @AuraEnabled public String courseName {get; set;}
        @AuraEnabled public String courseNumber {get; set;}
        @AuraEnabled public Boolean isMultiTerm {get; set;}
        @AuraEnabled public String programCourseCode {get; set;}
        @AuraEnabled public Integer rowNumber {get; set;}
        @AuraEnabled public Boolean selected {get; set;}
        @AuraEnabled public Date startDate {get; set;}
        @AuraEnabled public Date endDate {get; set;}
        @AuraEnabled public Id evaluationTermId {get; set;}
    }
    
    public class CourseOfferingWrapper {
        @AuraEnabled public Id programCourseId {get; set;}
        @AuraEnabled public Date startDate {get; set;}
        @AuraEnabled public Date endDate {get; set;}
        @AuraEnabled public Id evaluationTermId {get; set;}
    }
    
    public class EvaluationTermWrapper {
        @AuraEnabled public Id id {get; set;}
        @AuraEnabled public String name {get; set;}
        @AuraEnabled public String termCode {get; set;}
        @AuraEnabled public Integer termNumber {get; set;}
    }
}
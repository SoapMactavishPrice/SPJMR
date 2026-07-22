public with sharing class TermCourseOfferingController {
    
    @AuraEnabled(cacheable=true)
    public static List<ProgramCourseWrapper> getProgramCoursesForTerm(Id termId) {
        List<ProgramCourseWrapper> courseList = new List<ProgramCourseWrapper>();
        
        if (termId == null) {
            return courseList;
        }
        
        try {
            // Get the Term record and its Batch
            Term__c term = [
                SELECT Id, Batch__c, Term__c
                FROM Term__c
                WHERE Id = :termId
                LIMIT 1
            ];
            
            if (term.Batch__c == null) {
                return courseList;
            }
            
            // Get Program Courses related to the same Batch
            List<Program_Courses__c> programCourses = [
                SELECT Id, Name, Learning_Course__c, Learning_Course__r.Name, 
                       Learning_Course__r.CourseNumber, Is_Multi_Term__c,
                       Program_Course_Code__c
                FROM Program_Courses__c
                WHERE Batch__c = :term.Batch__c
                ORDER BY Learning_Course__r.Name
            ];
            
            // Get the Academic Term from the Term record
            Id academicTermId = term.Term__c;
            
            // Get existing Course Offerings for this Academic Term to check which courses are already offered
            Set<Id> existingProgramCourseIds = new Set<Id>();
            if (academicTermId != null) {
                List<CourseOffering> existingOfferings = [
                    SELECT Id, ProgramCourse__c
                    FROM CourseOffering
                    WHERE Academic_Term__c = :academicTermId
                ];
                
                for (CourseOffering co : existingOfferings) {
                    if (co.ProgramCourse__c != null) {
                        existingProgramCourseIds.add(co.ProgramCourse__c);
                    }
                }
            }
            
            // Build wrapper list
            for (Program_Courses__c pc : programCourses) {
                ProgramCourseWrapper wrapper = new ProgramCourseWrapper();
                wrapper.programCourseId = pc.Id;
                wrapper.courseName = pc.Learning_Course__r.Name;
                wrapper.courseNumber = pc.Learning_Course__r.CourseNumber;
                wrapper.isMultiTerm = pc.Is_Multi_Term__c != null ? pc.Is_Multi_Term__c : false;
                wrapper.programCourseCode = pc.Program_Course_Code__c;
                wrapper.isAlreadyOffered = existingProgramCourseIds.contains(pc.Id);
                courseList.add(wrapper);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching program courses: ' + e.getMessage());
        }
        
        return courseList;
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
                if (wrapper.programCourseId == null) {
                    continue;
                }
                
                CourseOffering co = new CourseOffering();
                co.ProgramCourse__c = wrapper.programCourseId;
                co.StartDate = wrapper.startDate;
                co.EndDate = wrapper.endDate;
                
                // If multi-term and evaluation term is provided, use it; otherwise use the term's academic term
                if (wrapper.isMultiTerm && wrapper.evaluationTermId != null) {
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
    
    @AuraEnabled(cacheable=true)
    public static List<AcademicTermWrapper> getAcademicTerms() {
        List<AcademicTermWrapper> termList = new List<AcademicTermWrapper>();
        
        try {
            List<AcademicTerm> terms = [
                SELECT Id, Name, Term_Code__c
                FROM AcademicTerm
                ORDER BY Name
            ];
            
            for (AcademicTerm term : terms) {
                AcademicTermWrapper wrapper = new AcademicTermWrapper();
                wrapper.id = term.Id;
                wrapper.name = term.Name;
                wrapper.termCode = term.Term_Code__c;
                termList.add(wrapper);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching academic terms: ' + e.getMessage());
        }
        
        return termList;
    }
    
    public class ProgramCourseWrapper {
        @AuraEnabled public Id programCourseId {get; set;}
        @AuraEnabled public String courseName {get; set;}
        @AuraEnabled public String courseNumber {get; set;}
        @AuraEnabled public Boolean isMultiTerm {get; set;}
        @AuraEnabled public String programCourseCode {get; set;}
        @AuraEnabled public Boolean isAlreadyOffered {get; set;}
    }
    
    public class CourseOfferingWrapper {
        @AuraEnabled public Id programCourseId {get; set;}
        @AuraEnabled public Date startDate {get; set;}
        @AuraEnabled public Date endDate {get; set;}
        @AuraEnabled public Boolean isMultiTerm {get; set;}
        @AuraEnabled public Id evaluationTermId {get; set;}
    }
    
    public class AcademicTermWrapper {
        @AuraEnabled public Id id {get; set;}
        @AuraEnabled public String name {get; set;}
        @AuraEnabled public String termCode {get; set;}
    }
}
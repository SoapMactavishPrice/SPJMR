public with sharing class DivisionCourseAssignmentController {

    // Wrapper class to return courses with selection status
    public class CourseWrapper {
        @AuraEnabled public Program_Courses__c course;
        @AuraEnabled public Boolean isSelected;
        @AuraEnabled public Id divisionCourseId; // ID of DivisionCourse__c if already assigned
    }

    @AuraEnabled(cacheable=true)
    public static List<CourseWrapper> getExistingCourses(Id divisionId) {
        List<CourseWrapper> courseWrappers = new List<CourseWrapper>();

        if (divisionId == null) {
            System.debug('null divisionId');
            return courseWrappers;
        }

        try {
            System.debug('divisionId: ' + divisionId);

            // Get division information including type, term, and specialisation
            Division__c division = [
                SELECT Id, 
                       DivisionBatch__c,
                       Term__c,
                        SPJIMR_Division_Group_Name__c,Division_Group__r.Is_Specialiation__c,
                       SPJIMR_Specialisation__c
                FROM Division__c
                WHERE Id = :divisionId
                LIMIT 1
            ];

            if (division.Term__c == null) {
                System.debug('Division has no Term');
                return courseWrappers;
            }

            String divisionType = division.SPJIMR_Division_Group_Name__c;
            System.debug('Division Type: ' + divisionType);

            // Get existing DivisionCourse records to identify already assigned courses
            Map<Id, Id> programCourseIdToDivisionCourseId = new Map<Id, Id>();
            try {
                for (DivisionCourse__c dc : [
                    SELECT Id, Course_Offering__r.ProgramCourse__c
                    FROM DivisionCourse__c
                    WHERE Division__c = :divisionId
                    AND Course_Offering__r.ProgramCourse__c != null
                ]) {
                    // Only add if both the DivisionCourse and the relationship are valid
                    if (dc.Course_Offering__r != null && dc.Course_Offering__r.ProgramCourse__c != null) {
                        programCourseIdToDivisionCourseId.put(dc.Course_Offering__r.ProgramCourse__c, dc.Id);
                    }
                }
            } catch (Exception ex) {
                System.debug('Warning: Error querying existing DivisionCourse records: ' + ex.getMessage());
                // Continue execution - this is not critical, just means we won't pre-select existing courses
            }

            // Query CourseOfferings based on division type
            List<CourseOffering> courseOfferings = new List<CourseOffering>();
            
            if (divisionType == 'Fundamental') {
                // For Fundamental divisions, get Core courses from the term
                courseOfferings = [
                    SELECT Id, 
                           ProgramCourse__c,
                           ProgramCourse__r.Id,
                           ProgramCourse__r.Learning_Course__r.Name,
                           ProgramCourse__r.Learning_Course__r.CourseNumber,
                           ProgramCourse__r.Learning_Course__c,
                           ProgramCourse__r.Is_Multi_Term__c,
                           ProgramCourse__r.Course_Type__c,
                           ProgramCourse__r.SPJIMR_Specialisation__c,
                           ProgramCourse__r.SPJIMR_Specialisation__r.Specialisation_Name__r.Name
                    FROM CourseOffering
                    WHERE Academic_Term__c = :division.Term__c
                    AND Course_Type__c = 'Core'
                    AND ProgramCourse__c != null
                ];
            } else if (divisionType == 'Elective') {
                // For Elective divisions, get Elective courses from the term
                courseOfferings = [
                    SELECT Id, 
                           ProgramCourse__c,
                           ProgramCourse__r.Id,
                           ProgramCourse__r.Learning_Course__r.Name,
                           ProgramCourse__r.Learning_Course__r.CourseNumber,
                           ProgramCourse__r.Learning_Course__c,
                           ProgramCourse__r.Is_Multi_Term__c,
                           ProgramCourse__r.Course_Type__c,
                           ProgramCourse__r.SPJIMR_Specialisation__c,
                           ProgramCourse__r.SPJIMR_Specialisation__r.Specialisation_Name__r.Name
                    FROM CourseOffering
                    WHERE Academic_Term__c = :division.Term__c
                    AND Course_Type__c = 'Elective'
                    AND ProgramCourse__c != null
                ];
            } else if ( division.Division_Group__r != null && Division.Division_Group__r.Is_Specialiation__c == true && division.SPJIMR_Specialisation__c != null) {
                // For Specialisation divisions, get Specialisation courses matching the division's specialisation
                courseOfferings = [
                    SELECT Id, 
                           ProgramCourse__c,
                           ProgramCourse__r.Id,
                           ProgramCourse__r.Learning_Course__r.Name,
                           ProgramCourse__r.Learning_Course__r.CourseNumber,
                           ProgramCourse__r.Learning_Course__c,
                           ProgramCourse__r.Is_Multi_Term__c,
                           ProgramCourse__r.Course_Type__c,
                           ProgramCourse__r.SPJIMR_Specialisation__c,
                           ProgramCourse__r.SPJIMR_Specialisation__r.Specialisation_Name__r.Name
                    FROM CourseOffering
                    WHERE Academic_Term__c = :division.Term__c
                    AND Course_Type__c = 'Specialisation'
                    AND ProgramCourse__r.SPJIMR_Specialisation__c = :division.SPJIMR_Specialisation__c
                    AND ProgramCourse__c != null
                ];
            } else {
                System.debug('Unknown division type or missing specialisation: ' + divisionType);
                return courseWrappers;
            }

        // Build wrapper list with selection status
Set<Id> processedProgramCourseIds = new Set<Id>();

for (CourseOffering co : courseOfferings) {

    // Only process valid Program Courses once
    if (co.ProgramCourse__c != null
        && co.ProgramCourse__r != null
        && !processedProgramCourseIds.contains(co.ProgramCourse__c)) {

        processedProgramCourseIds.add(co.ProgramCourse__c);

        // Skip already assigned courses
        if (programCourseIdToDivisionCourseId.containsKey(co.ProgramCourse__c)) {
            continue;
        }

        CourseWrapper wrapper = new CourseWrapper();
        wrapper.course = co.ProgramCourse__r;
        wrapper.isSelected = false;
        wrapper.divisionCourseId = null;

        courseWrappers.add(wrapper);
    }
}
System.debug('Returning ' + courseWrappers.size() + ' courses');
return courseWrappers;

        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException(
                'Error fetching program courses: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled
      public static void assignCourses(
      Id divisionId,
      List<Id> courseIds,
      List<Id> divisionCourseIdsToDelete
) {

    if (divisionId == null) {
        throw new AuraHandledException('Division Id is required');
    }

    Division__c division = [
        SELECT Id, Term__c
        FROM Division__c
        WHERE Id = :divisionId
        LIMIT 1
    ];

    if (division.Term__c == null) {
        throw new AuraHandledException('Division Term is missing');
    }

    // ✅ DELETE EXISTING (Unassign)
    if (divisionCourseIdsToDelete != null && !divisionCourseIdsToDelete.isEmpty()) {
        List<DivisionCourse__c> toDelete = [
            SELECT Id
            FROM DivisionCourse__c
            WHERE Division__c = :divisionId
            AND Course_Offering__r.ProgramCourse__c IN :divisionCourseIdsToDelete
        ];

        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    // ✅ VALIDATION
    if (courseIds == null || courseIds.isEmpty()) {
        throw new AuraHandledException('Please select at least one course');
    }

    // ✅ FETCH COURSE OFFERINGS
    List<CourseOffering> courseOfferings = [
        SELECT Id, ProgramCourse__c
        FROM CourseOffering
        WHERE ProgramCourse__c IN :courseIds
        AND Academic_Term__c = :division.Term__c
    ];

    System.debug('CourseOffering Found: ' + courseOfferings.size());

    if (courseOfferings.isEmpty()) {
        throw new AuraHandledException(
            'No Course Offering found for selected courses in this term'
        );
    }

    // ✅ EXISTING LINKS
    Set<Id> existingCourseOfferingIds = new Set<Id>();

    for (DivisionCourse__c dc : [
        SELECT Course_Offering__c
        FROM DivisionCourse__c
        WHERE Division__c = :divisionId
    ]) {
        existingCourseOfferingIds.add(dc.Course_Offering__c);
    }

    // ✅ INSERT NEW LINKS
    List<DivisionCourse__c> toInsert = new List<DivisionCourse__c>();

    for (CourseOffering co : courseOfferings) {
        if (!existingCourseOfferingIds.contains(co.Id)) {
            toInsert.add(new DivisionCourse__c(
                Division__c = divisionId,
                Course_Offering__c = co.Id
            ));
        }
    }

    System.debug('Records to Insert: ' + toInsert.size());

    if (!toInsert.isEmpty()) {
        insert toInsert;
    } else {
        throw new AuraHandledException('Courses already assigned');
    }
}
    
   
}
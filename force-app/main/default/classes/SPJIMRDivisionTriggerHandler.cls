/**
 * Division__c trigger orchestration: term division counts, batch stamping from term, course scaffolding.
 */
public class SPJIMRDivisionTriggerHandler {

    /**
     * Populates Division.Batch__c (Program Cohort) from Term__c → AcademicTerm.Batch_Name__c.
     * Clears Batch__c when Term__c is blank.
     *
     * @param newList Rows in {@code before insert} or {@code before update} context.
     */
    public static void syncBatchFromTerm(List<Division__c> newList) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> termIds = new Set<Id>();
        for (Division__c div : newList) {
            if (div.Term__c != null) {
                termIds.add(div.Term__c);
            }
        }
        Map<Id, Id> termIdToBatchId = new Map<Id, Id>();
        if (!termIds.isEmpty()) {
            for (AcademicTerm termRow : [
                SELECT Id, Batch_Name__c
                FROM AcademicTerm
                WHERE Id IN :termIds
            ]) {
                termIdToBatchId.put(termRow.Id, termRow.Batch_Name__c);
            }
        }
        for (Division__c div : newList) {
            if (div.Term__c == null) {
                div.Batch__c = null;
            } else {
                div.Batch__c = termIdToBatchId.get(div.Term__c);
            }
        }
    }

    public static void updateTermDivisionCounts(
        List<Division__c> newList,
        List<Division__c> oldList,
        Boolean isInsert,
        Boolean isUpdate,
        Boolean isDelete,
        Boolean isUndelete
    ) {
        Set<Id> termIds = new Set<Id>();

        // Collect affected Term IDs from both new and old lists
        if (isInsert || isUpdate || isUndelete) {
            for (Division__c div : newList) {
                if (div.Term__c != null) {
                    termIds.add(div.Term__c);
                }
            }
        }
        if (isUpdate || isDelete) {
            for (Division__c div : oldList) {
                if (div.Term__c != null) {
                    termIds.add(div.Term__c);
                }
            }
        }

        if (termIds.isEmpty()) {
            return;
        }

        // Count remaining divisions per term using aggregate query
        Map<Id, Integer> termCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Term__c termId, COUNT(Id) divisionCount
            FROM Division__c
            WHERE Term__c IN :termIds
            GROUP BY Term__c
        ]) {
            termCounts.put((Id)ar.get('termId'), (Integer)ar.get('divisionCount'));
        }

        // Prepare updates: ensure terms with no rows get 0
        List<AcademicTerm> termsToUpdate = new List<AcademicTerm>();
        for (Id termId : termIds) {
            termsToUpdate.add(new AcademicTerm(
                Id = termId,
                Total_Number_of_Divisions_in_Term__c = termCounts.containsKey(termId) ? termCounts.get(termId) : 0
            ));
        }

        if (!termsToUpdate.isEmpty()) {
            update termsToUpdate;
        }
    }

    public static void handleAfterInsert(List<Division__c> newList) {
        createDivisionCoursesOptimized(newList);
    }

    public static void handleAfterUpdate(List<Division__c> newList, List<Division__c> oldList) {
        // Check if Division Group changed to Specialisation or Specialisation field changed
        List<Division__c> specialisationDivisionsToProcess = new List<Division__c>();
        // Check if Division Group changed to Elective or Term changed for Elective division
        List<Division__c> electiveDivisionsToProcess = new List<Division__c>();
        Map<Id, Division__c> oldMap = new Map<Id, Division__c>(oldList);
        
        for (Division__c div : newList) {
            Division__c oldDiv = oldMap.get(div.Id);
            
            // Process Specialisation divisions
            if (div.Division_Group__c != null && 
                String.isNotBlank(div.SPJIMR_Division_Group_Name__c) &&
                div.SPJIMR_Division_Group_Name__c.contains('Specialisation')) {
                
                // Process if:
                // 1. Changed from non-Specialisation to Specialisation, OR
                // 2. Specialisation value changed
                Boolean shouldProcess = false;
                if (oldDiv == null || oldDiv.SPJIMR_Division_Group_Name__c != 'Specialisation') {
                    shouldProcess = true; // Changed to Specialisation
                } else if (oldDiv.SPJIMR_Specialisation__c != div.SPJIMR_Specialisation__c && div.SPJIMR_Specialisation__c != null) {
                    shouldProcess = true; // Specialisation changed
                }
                
                if (shouldProcess) {
                    specialisationDivisionsToProcess.add(div);
                }
            }
            
            // Process Elective divisions
            if (div.Division_Group__c != null && 
                String.isNotBlank(div.SPJIMR_Division_Group_Name__c) &&
                div.SPJIMR_Division_Group_Name__c == 'Elective' &&
                div.Term__c != null) {
                
                // Process if:
                // 1. Changed from non-Elective to Elective, OR
                // 2. Term changed for Elective division
                Boolean shouldProcess = false;
                if (oldDiv == null || oldDiv.SPJIMR_Division_Group_Name__c != 'Elective') {
                    shouldProcess = true; // Changed to Elective
                } else if (oldDiv.Term__c != div.Term__c && div.Term__c != null) {
                    shouldProcess = true; // Term changed
                }
                
                if (shouldProcess) {
                    electiveDivisionsToProcess.add(div);
                }
            }
        }
        
        if (!specialisationDivisionsToProcess.isEmpty()) {
            createDivisionCoursesForSpecialisation(specialisationDivisionsToProcess);
        }
        
        if (!electiveDivisionsToProcess.isEmpty()) {
            createDivisionCoursesForElective(electiveDivisionsToProcess);
        }
    }

    /**
     * Optimized method to create DivisionCourse records for both Fundamental and Specialisation Divisions
     * Queries Course Offerings once and filters in memory
     */
    private static void createDivisionCoursesOptimized(List<Division__c> newList) {
        // Collect division data
        Map<Id, Id> fundamentalDivisionToTermMap = new Map<Id, Id>();
        Map<Id, Id> specialisationDivisionToSpecialisationMap = new Map<Id, Id>();
        Map<Id, Id> electiveDivisionToTermMap = new Map<Id, Id>();
        Set<Id> termIds = new Set<Id>();
        Set<Id> specialisationIds = new Set<Id>();
        Set<Id> allDivisionIds = new Set<Id>();
        
        // Filter and categorize divisions in a single pass
        for (Division__c div : newList) {
            
            
            allDivisionIds.add(div.Id);
            String divisionGroupName = div.SPJIMR_Division_Group_Name__c;
            
            if (divisionGroupName == 'Fundamental' && div.Term__c != null) {
                fundamentalDivisionToTermMap.put(div.Id, div.Term__c);
                termIds.add(div.Term__c);
            } else if (divisionGroupName.contains('Specialisation') && div.SPJIMR_Specialisation__c != null && div.Term__c != null) {
                specialisationDivisionToSpecialisationMap.put(div.Id, div.SPJIMR_Specialisation__c);
                specialisationIds.add(div.SPJIMR_Specialisation__c);
                termIds.add(div.Term__c); // Add term ID for Specialisation divisions too
            } else if (divisionGroupName == 'Elective' && div.Term__c != null) {
                electiveDivisionToTermMap.put(div.Id, div.Term__c);
                termIds.add(div.Term__c);
            }
        }
        
        if (allDivisionIds.isEmpty()) {
            return;
        }
        
        // Get existing DivisionCourse records to avoid duplicates
        Set<String> existingDivisionCourses = getExistingDivisionCourses(allDivisionIds);
        
        // Query Course Offerings - Core by Term, Elective by Term, and Specialisation by ProgramCourse Specialisation
        Map<Id, List<CourseOffering>> termToCoreOfferingsMap = new Map<Id, List<CourseOffering>>();
        Map<Id, List<CourseOffering>> termToElectiveOfferingsMap = new Map<Id, List<CourseOffering>>();
        Map<Id, List<CourseOffering>> specialisationToOfferingsMap = new Map<Id, List<CourseOffering>>();
        
        if (!termIds.isEmpty()) {
            // Query Core Course Offerings
            for (CourseOffering co : [
                SELECT Id, Academic_Term__c
                FROM CourseOffering
                WHERE Academic_Term__c IN :termIds
                AND Course_Type__c = 'Core'
            ]) {
                if (co.Academic_Term__c != null) {
                    List<CourseOffering> offerings = termToCoreOfferingsMap.get(co.Academic_Term__c);
                    if (offerings == null) {
                        offerings = new List<CourseOffering>();
                        termToCoreOfferingsMap.put(co.Academic_Term__c, offerings);
                    }
                    offerings.add(co);
                }
            }
            
        }
        
        if (!specialisationIds.isEmpty()) {
            for (CourseOffering co : [
                SELECT Id, ProgramCourse__r.SPJIMR_Specialisation__c
                FROM CourseOffering
                WHERE Course_Type__c = 'Specialisation'
                AND Academic_Term__c IN :termIds
                AND ProgramCourse__r.SPJIMR_Specialisation__c IN :specialisationIds
            ]) {
                if (co.ProgramCourse__r != null && co.ProgramCourse__r.SPJIMR_Specialisation__c != null) {
                    Id specialisationId = co.ProgramCourse__r.SPJIMR_Specialisation__c;
                    List<CourseOffering> offerings = specialisationToOfferingsMap.get(specialisationId);
                    if (offerings == null) {
                        offerings = new List<CourseOffering>();
                        specialisationToOfferingsMap.put(specialisationId, offerings);
                    }
                    offerings.add(co);
                }
            }
        }
        
        // Create DivisionCourse records using consolidated processing logic
        List<DivisionCourse__c> divisionCoursesToInsert = new List<DivisionCourse__c>();
        
        // Process Fundamental Divisions
        for (Id divisionId : fundamentalDivisionToTermMap.keySet()) {
            List<CourseOffering> termOfferings = termToCoreOfferingsMap.get(fundamentalDivisionToTermMap.get(divisionId));
            if (termOfferings != null) {
                addDivisionCourses(divisionCoursesToInsert, divisionId, termOfferings, existingDivisionCourses);
            }
        }
        
        // Process Specialisation Divisions
        for (Id divisionId : specialisationDivisionToSpecialisationMap.keySet()) {
            List<CourseOffering> specialisationOfferings = specialisationToOfferingsMap.get(
                specialisationDivisionToSpecialisationMap.get(divisionId)
            );
            if (specialisationOfferings != null) {
                addDivisionCourses(divisionCoursesToInsert, divisionId, specialisationOfferings, existingDivisionCourses);
            }
        }
        
        // Process Elective Divisions
        for (Id divisionId : electiveDivisionToTermMap.keySet()) {
            List<CourseOffering> termElectiveOfferings = termToElectiveOfferingsMap.get(electiveDivisionToTermMap.get(divisionId));
            if (termElectiveOfferings != null) {
                addDivisionCourses(divisionCoursesToInsert, divisionId, termElectiveOfferings, existingDivisionCourses);
            }
        }
        
        if (!divisionCoursesToInsert.isEmpty()) {
            insert divisionCoursesToInsert;
        }
    }
    
    /**
     * Helper method to add DivisionCourse records while avoiding duplicates
     */
    private static void addDivisionCourses(
        List<DivisionCourse__c> divisionCoursesToInsert,
        Id divisionId,
        List<CourseOffering> offerings,
        Set<String> existingDivisionCourses
    ) {
        for (CourseOffering co : offerings) {
            String key = divisionId + '-' + co.Id;
            if (!existingDivisionCourses.contains(key)) {
                divisionCoursesToInsert.add(new DivisionCourse__c(
                    Division__c = divisionId,
                    Course_Offering__c = co.Id
                ));
            }
        }
    }

    /**
     * Creates DivisionCourse records for Divisions with 'Specialisation' Division Group
     * Links Specialisation Course Offerings where Specialisation matches
     */
    private static void createDivisionCoursesForSpecialisation(List<Division__c> newList) {
        // Map to track specialisation divisions, their specialisation IDs, and term IDs
        Map<Id, Id> divisionToSpecialisationMap = new Map<Id, Id>();
        Map<Id, Id> divisionToTermMap = new Map<Id, Id>();
        Set<Id> specialisationIds = new Set<Id>();
        Set<Id> termIds = new Set<Id>();
        
        // Filter divisions with 'Specialisation' Division Group
        for (Division__c div : newList) {
            if (div.Division_Group__c != null && 
                String.isNotBlank(div.SPJIMR_Division_Group_Name__c) && 
                div.SPJIMR_Division_Group_Name__c.contains('Specialisation') &&
                div.SPJIMR_Specialisation__c != null &&
                div.Term__c != null) {
                divisionToSpecialisationMap.put(div.Id, div.SPJIMR_Specialisation__c);
                divisionToTermMap.put(div.Id, div.Term__c);
                specialisationIds.add(div.SPJIMR_Specialisation__c);
                termIds.add(div.Term__c);
            }
        }
        
        if (divisionToSpecialisationMap.isEmpty() || specialisationIds.isEmpty() || termIds.isEmpty()) {
            return;
        }
        
        // Query Specialisation Course Offerings where ProgramCourse Specialisation matches AND Term matches
        Map<Id, List<CourseOffering>> specialisationToCourseOfferingsMap = getSpecialisationCourseOfferings(specialisationIds, termIds);
        
        if (specialisationToCourseOfferingsMap.isEmpty()) {
            return;
        }
        
        // Get existing DivisionCourse records to avoid duplicates
        Set<String> existingDivisionCourses = getExistingDivisionCourses(divisionToSpecialisationMap.keySet());
        
        // Create DivisionCourse records - filter by both specialisation and term
        List<DivisionCourse__c> divisionCoursesToInsert = new List<DivisionCourse__c>();
        
        for (Id divisionId : divisionToSpecialisationMap.keySet()) {
            Id specialisationId = divisionToSpecialisationMap.get(divisionId);
            Id termId = divisionToTermMap.get(divisionId);
            
            // Get all offerings for this specialisation
            List<CourseOffering> allSpecialisationOfferings = specialisationToCourseOfferingsMap.get(specialisationId);
            
            if (allSpecialisationOfferings != null) {
                // Filter offerings to only include those from this division's term
                List<CourseOffering> termSpecificOfferings = new List<CourseOffering>();
                for (CourseOffering co : allSpecialisationOfferings) {
                    if (co.Academic_Term__c == termId) {
                        termSpecificOfferings.add(co);
                    }
                }
                
                if (!termSpecificOfferings.isEmpty()) {
                    addDivisionCourses(divisionCoursesToInsert, divisionId, termSpecificOfferings, existingDivisionCourses);
                }
            }
        }
        
        if (!divisionCoursesToInsert.isEmpty()) {
            insert divisionCoursesToInsert;
        }
    }

    /**
     * Creates DivisionCourse records for Divisions with 'Elective' Division Group
     * Links Elective Course Offerings for the Term
     */
    private static void createDivisionCoursesForElective(List<Division__c> newList) {
        // Map to track elective divisions and their term IDs
        Map<Id, Id> divisionToTermMap = new Map<Id, Id>();
        Set<Id> termIds = new Set<Id>();
        
        // Filter divisions with 'Elective' Division Group
        for (Division__c div : newList) {
            if (div.Division_Group__c != null && 
                String.isNotBlank(div.SPJIMR_Division_Group_Name__c) && 
                div.SPJIMR_Division_Group_Name__c == 'Elective' &&
                div.Term__c != null) {
                divisionToTermMap.put(div.Id, div.Term__c);
                termIds.add(div.Term__c);
            }
        }
        
        if (divisionToTermMap.isEmpty() || termIds.isEmpty()) {
            return;
        }
        
        // Query Elective Course Offerings for the Terms
        Map<Id, List<CourseOffering>> termToElectiveOfferingsMap = getElectiveCourseOfferingsByTerm(termIds);
        
        if (termToElectiveOfferingsMap.isEmpty()) {
            return;
        }
        
        // Get existing DivisionCourse records to avoid duplicates
        Set<String> existingDivisionCourses = getExistingDivisionCourses(divisionToTermMap.keySet());
        
        // Create DivisionCourse records
        List<DivisionCourse__c> divisionCoursesToInsert = new List<DivisionCourse__c>();
        
        for (Id divisionId : divisionToTermMap.keySet()) {
            List<CourseOffering> electiveOfferings = termToElectiveOfferingsMap.get(divisionToTermMap.get(divisionId));
            if (electiveOfferings != null) {
                addDivisionCourses(divisionCoursesToInsert, divisionId, electiveOfferings, existingDivisionCourses);
            }
        }
        
        if (!divisionCoursesToInsert.isEmpty()) {
            insert divisionCoursesToInsert;
        }
    }

    /**
     * Queries and groups Specialisation Course Offerings by Specialisation
     * @param specialisationIds Set of Specialisation IDs
     * @param termIds Set of Term IDs (can be empty, but should be provided for proper filtering)
     * @return Map of Specialisation ID to List of Specialisation Course Offerings
     */
    private static Map<Id, List<CourseOffering>> getSpecialisationCourseOfferings(Set<Id> specialisationIds, Set<Id> termIds) {
        Map<Id, List<CourseOffering>> specialisationToCourseOfferingsMap = new Map<Id, List<CourseOffering>>();
        
        // Query Specialisation Course Offerings where ProgramCourse Specialisation matches
        // Filter by Term if termIds are provided and not empty
        List<CourseOffering> courseOfferings;
        if (termIds != null && !termIds.isEmpty()) {
            courseOfferings = [
                SELECT Id, Academic_Term__c, ProgramCourse__r.SPJIMR_Specialisation__c
                FROM CourseOffering
                WHERE Course_Type__c = 'Specialisation'
                AND ProgramCourse__r.SPJIMR_Specialisation__c IN :specialisationIds
                AND Academic_Term__c IN :termIds
            ];
        } else {
            courseOfferings = [
                SELECT Id, Academic_Term__c, ProgramCourse__r.SPJIMR_Specialisation__c
                FROM CourseOffering
                WHERE Course_Type__c = 'Specialisation'
                AND ProgramCourse__r.SPJIMR_Specialisation__c IN :specialisationIds
            ];
        }
        
        for (CourseOffering co : courseOfferings) {
            if (co.ProgramCourse__r != null && co.ProgramCourse__r.SPJIMR_Specialisation__c != null) {
                Id specialisationId = co.ProgramCourse__r.SPJIMR_Specialisation__c;
                List<CourseOffering> offerings = specialisationToCourseOfferingsMap.get(specialisationId);
                if (offerings == null) {
                    offerings = new List<CourseOffering>();
                    specialisationToCourseOfferingsMap.put(specialisationId, offerings);
                }
                offerings.add(co);
            }
        }
        
        return specialisationToCourseOfferingsMap;
    }

    /**
     * Gets existing DivisionCourse records to avoid duplicates
     * @param divisionIds Set of Division IDs
     * @return Set of composite keys (DivisionId-CourseOfferingId)
     */
    private static Set<String> getExistingDivisionCourses(Set<Id> divisionIds) {
        Set<String> existingKeys = new Set<String>();
        
        List<DivisionCourse__c> existingRecords = [
            SELECT Division__c, Course_Offering__c
            FROM DivisionCourse__c
            WHERE Division__c IN :divisionIds
        ];
        
        for (DivisionCourse__c dc : existingRecords) {
            existingKeys.add(dc.Division__c + '-' + dc.Course_Offering__c);
        }
        
        return existingKeys;
    }

    /**
     * Queries and groups Core Course Offerings by Academic Term
     * @param termIds Set of Academic Term IDs
     * @return Map of Term ID to List of Core Course Offerings
     */
    private static Map<Id, List<CourseOffering>> getCoreCourseOfferingsByTerm(Set<Id> termIds) {
        Map<Id, List<CourseOffering>> termToCourseOfferingsMap = new Map<Id, List<CourseOffering>>();
        
        // Query Core Course Offerings for the Terms
        for (CourseOffering co : [
            SELECT Id, Academic_Term__c
            FROM CourseOffering
            WHERE Academic_Term__c IN :termIds
            AND Course_Type__c = 'Core'
        ]) {
            if (co.Academic_Term__c != null) {
                List<CourseOffering> offerings = termToCourseOfferingsMap.get(co.Academic_Term__c);
                if (offerings == null) {
                    offerings = new List<CourseOffering>();
                    termToCourseOfferingsMap.put(co.Academic_Term__c, offerings);
                }
                offerings.add(co);
            }
        }
        
        return termToCourseOfferingsMap;
    }

    /**
     * Queries and groups Elective Course Offerings by Academic Term
     * @param termIds Set of Academic Term IDs
     * @return Map of Term ID to List of Elective Course Offerings
     */
    private static Map<Id, List<CourseOffering>> getElectiveCourseOfferingsByTerm(Set<Id> termIds) {
        Map<Id, List<CourseOffering>> termToCourseOfferingsMap = new Map<Id, List<CourseOffering>>();
        
        // Query Elective Course Offerings for the Terms
        for (CourseOffering co : [
            SELECT Id, Academic_Term__c
            FROM CourseOffering
            WHERE Academic_Term__c IN :termIds
            AND Course_Type__c = 'Elective'
        ]) {
            if (co.Academic_Term__c != null) {
                List<CourseOffering> offerings = termToCourseOfferingsMap.get(co.Academic_Term__c);
                if (offerings == null) {
                    offerings = new List<CourseOffering>();
                    termToCourseOfferingsMap.put(co.Academic_Term__c, offerings);
                }
                offerings.add(co);
            }
        }
        
        return termToCourseOfferingsMap;
    }
    
  // To Validate Duplicate Division Name   
   public static void validateDuplicateDivision(List<Division__c> newDivisions) {

    Set<String> keys = new Set<String>();

    // Build keys from incoming records
    for (Division__c div : newDivisions) {
        if (div.Term__c != null && div.Division_Name__c != null) {
            String key = String.valueOf(div.Term__c) + '-' + String.valueOf(div.Division_Name__c);

            if (keys.contains(key)) {
                div.addError('Duplicate Division Name found in the same batch.');
            }
            keys.add(key);
        }
    }

    // Get matching existing records
    Map<String, Division__c> existingMap = new Map<String, Division__c>();

    for (Division__c existing : [
        SELECT Id, Term__c, Division_Name__c
        FROM Division__c
        WHERE Term__c != null AND Division_Name__c != null
    ]) {
        String key = String.valueOf(existing.Term__c) + '-' + String.valueOf(existing.Division_Name__c);
        existingMap.put(key, existing);
    }

    // Compare with database records
    for (Division__c div : newDivisions) {
        if (div.Term__c == null || div.Division_Name__c == null) continue;

        String key = String.valueOf(div.Term__c) + '-' + String.valueOf(div.Division_Name__c);

        if (existingMap.containsKey(key)) {
            Division__c existing = existingMap.get(key);

            // IMPORTANT: allow same record during update
            if (div.Id == null || div.Id != existing.Id) {
                div.addError('Division Name already exists under the selected Term.');
            }
        }
    }
   }
    
 }
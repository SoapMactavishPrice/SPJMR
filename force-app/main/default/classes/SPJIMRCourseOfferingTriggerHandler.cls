public class SPJIMRCourseOfferingTriggerHandler {

    /**
     * Handles after insert logic for CourseOffering
     * Creates DivisionCourse records for 'Fundamental' Divisions when Core Course Offerings are inserted
     */
    public static void handleAfterInsert(List<CourseOffering> newList) {
        createDivisionCoursesForCoreOfferings(newList);
    }

    /**
     * Creates DivisionCourse records for Divisions with 'Fundamental' Division Group
     * when Core Course Offerings are inserted
     */
    private static void createDivisionCoursesForCoreOfferings(List<CourseOffering> newList) {
        // Filter Core Course Offerings and collect Term IDs in one pass
        List<CourseOffering> coreOfferings = new List<CourseOffering>();
        Set<Id> termIds = new Set<Id>();
        
        for (CourseOffering co : newList) {
            if (co.Course_Type__c == 'Core' && co.Academic_Term__c != null) {
                coreOfferings.add(co);
                termIds.add(co.Academic_Term__c);
            }
        }
        
        if (coreOfferings.isEmpty() || termIds.isEmpty()) {
            return;
        }
        
        // Query Fundamental Divisions for the affected Terms
        Map<Id, List<Division__c>> termToDivisionsMap = getFundamentalDivisionsByTerm(termIds);
        
        if (termToDivisionsMap.isEmpty()) {
            return;
        }
        
        // Create DivisionCourse records
        List<DivisionCourse__c> divisionCoursesToInsert = new List<DivisionCourse__c>();
        
        // Process only Core CourseOfferings
        for (CourseOffering co : coreOfferings) {
            List<Division__c> termDivisions = termToDivisionsMap.get(co.Academic_Term__c);
            
            if (termDivisions != null) {
                for (Division__c div : termDivisions) {
                    divisionCoursesToInsert.add(new DivisionCourse__c(
                        Division__c = div.Id,
                        Course_Offering__c = co.Id
                    ));
                }
            }
        }
        
        if (!divisionCoursesToInsert.isEmpty()) {
            insert divisionCoursesToInsert;
        }
    }

    /**
     * Handles before delete logic for CourseOffering
     * Prevents deletion if any Session is using the course from the Course Offering
    
    public static void handleBeforeDelete(List<CourseOffering> oldList) {
        // 1️⃣ Collect all Course Offering Ids
        Set<Id> courseOfferingIds = new Set<Id>();
        for (CourseOffering co : oldList) {
            courseOfferingIds.add(co.Id);
        }
        
        // 2️⃣ Query Course Offerings to get LearningCourseId values
        Map<Id, Id> courseOfferingToLearningCourseMap = new Map<Id, Id>();
        for (CourseOffering co : [
            SELECT Id, LearningCourseId
            FROM CourseOffering
            WHERE Id IN :courseOfferingIds
            AND LearningCourseId != null
        ]) {
            courseOfferingToLearningCourseMap.put(co.Id, co.LearningCourseId);
        }
        
        if (courseOfferingToLearningCourseMap.isEmpty()) {
            return;
        }
        
        // 3️⃣ Collect all LearningCourseIds
        Set<Id> learningCourseIds = new Set<Id>(courseOfferingToLearningCourseMap.values());
        
        // 4️⃣ Check if any Session is using these courses
        Map<Id, Integer> courseUsageMap = new Map<Id, Integer>();
        
        for (AggregateResult ar : [
            SELECT Course__c courseId, COUNT(Id) sessionCount
            FROM Session__c
            WHERE Course__c IN :learningCourseIds and schedule_type__c in ('Published', 'Completed', 'Republished', 'Cancelled')
            GROUP BY Course__c
        ]) {
            Id courseId = (Id) ar.get('courseId');
            Integer sessionCount = (Integer) ar.get('sessionCount');
            courseUsageMap.put(courseId, sessionCount);
        }
        
        // 5️⃣ Block deletion if any Session is using the course
        for (CourseOffering co : oldList) {
            Id learningCourseId = courseOfferingToLearningCourseMap.get(co.Id);
            if (learningCourseId != null && courseUsageMap.containsKey(learningCourseId)) {
                Integer sessionCount = courseUsageMap.get(learningCourseId);
                co.addError('Cannot delete Course Offering. There ' + 
                    (sessionCount == 1 ? 'is 1 Session' : 'are ' + sessionCount + ' Sessions') + 
                    ' associated with this course. Please remove the Session(s) before deleting the Course Offering.');
            }
        }
    } */
/**
 * Handles before delete logic for CourseOffering.
 * Prevents deletion when Sessions exist for the same
 * Learning Course and Academic Term.
 */
public static void handleBeforeDelete(List<CourseOffering> oldList) {

    // Query Course Offerings with required fields
    Map<Id, CourseOffering> courseOfferingMap = new Map<Id, CourseOffering>([
        SELECT Id,
               LearningCourseId,
               Academic_Term__c
        FROM CourseOffering
        WHERE Id IN :oldList
        AND LearningCourseId != null
        AND Academic_Term__c != null
    ]);

    if (courseOfferingMap.isEmpty()) {
        return;
    }

    // Collect Learning Course Ids and Term Ids
    Set<Id> learningCourseIds = new Set<Id>();
    Set<Id> termIds = new Set<Id>();

    for (CourseOffering co : courseOfferingMap.values()) {
        learningCourseIds.add(co.LearningCourseId);
        termIds.add(co.Academic_Term__c);
    }

    // Store Session counts by Course + Term
    Map<String, Integer> sessionCountMap = new Map<String, Integer>();

    for (AggregateResult ar : [
        SELECT Course__c courseId,
               Term__c termId,
               COUNT(Id) sessionCount
        FROM Session__c
        WHERE Course__c IN :learningCourseIds
        AND Term__c IN :termIds
        AND Schedule_Type__c IN (
            'Published',
            'Completed',
            'Republished',
            'Cancelled'
        )
        GROUP BY Course__c, Term__c
    ]) {
        String key =
            String.valueOf(ar.get('courseId')) + '-' +
            String.valueOf(ar.get('termId'));

        sessionCountMap.put(
            key,
            (Integer)ar.get('sessionCount')
        );
    }

    // Prevent deletion when matching Sessions exist
    for (CourseOffering co : oldList) {

        CourseOffering queriedCO = courseOfferingMap.get(co.Id);

        if (queriedCO == null) {
            continue;
        }

        String key =
            queriedCO.LearningCourseId + '-' +
            queriedCO.Academic_Term__c;

        if (sessionCountMap.containsKey(key)) {

            Integer sessionCount = sessionCountMap.get(key);

            co.addError(
                'Cannot delete Course Offering. There ' +
                (sessionCount == 1
                    ? 'is 1 Session'
                    : 'are ' + sessionCount + ' Sessions') +
                ' associated with this course for the selected term. ' +
                'Please remove the Session(s) before deleting the Course Offering.'
            );
        }
    }
}

    /**
     * Queries and groups Fundamental Divisions by Academic Term
     * @param termIds Set of Academic Term IDs
     * @return Map of Term ID to List of Fundamental Divisions
     */
    private static Map<Id, List<Division__c>> getFundamentalDivisionsByTerm(Set<Id> termIds) {
        // Query Fundamental Divisions for the Terms
        List<Division__c> fundamentalDivisions = [
            SELECT Id, Term__c
            FROM Division__c
            WHERE Term__c IN :termIds
            AND Division_Group__c != null
            AND SPJIMR_Division_Group_Name__c = 'Fundamental'
        ];
        
        // Group by Term using efficient map initialization
        Map<Id, List<Division__c>> termToDivisionsMap = new Map<Id, List<Division__c>>();
        for (Division__c div : fundamentalDivisions) {
            if (!termToDivisionsMap.containsKey(div.Term__c)) {
                termToDivisionsMap.put(div.Term__c, new List<Division__c>());
            }
            termToDivisionsMap.get(div.Term__c).add(div);
        }
        
        return termToDivisionsMap;
    }
}
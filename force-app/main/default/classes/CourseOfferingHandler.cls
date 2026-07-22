public with sharing class CourseOfferingHandler {

    public static void handleCourseOfferingAfterInsert(
        List<CourseOffering> newCourseOfferings
    ) {
        syncDivisionCourses(newCourseOfferings, null);
    }

    public static void handleDivisionAfterInsert(
        List<Division__c> newDivisions
    ) {
        syncDivisionCourses(null, newDivisions);
    }

    private static void syncDivisionCourses(
        List<CourseOffering> courseOfferings,
        List<Division__c> divisions
    ) {

        Set<Id> termIds = new Set<Id>();

        // Collect Term IDs
        if (courseOfferings != null) {
            for (CourseOffering co : courseOfferings) {
                if (co.Academic_Term__c != null) termIds.add(co.Academic_Term__c);
            }
        }

        if (divisions != null) {
            for (Division__c div : divisions) {
                if (div.Term__c != null) termIds.add(div.Term__c);
            }
        }

        if (termIds.isEmpty()) return;

        // Fetch all Course Offerings
        Map<Id, List<CourseOffering>> termToCoursesMap = new Map<Id, List<CourseOffering>>();
        Set<Id> allCourseOfferingIds = new Set<Id>();

        for (CourseOffering co : [
            SELECT Id, Academic_Term__c, Course_Type__c
            FROM CourseOffering
            WHERE Academic_Term__c IN :termIds
        ]) {
            allCourseOfferingIds.add(co.Id);
            if (!termToCoursesMap.containsKey(co.Academic_Term__c))
                termToCoursesMap.put(co.Academic_Term__c, new List<CourseOffering>());
            termToCoursesMap.get(co.Academic_Term__c).add(co);
        }

        // Fetch Divisions + Division Groups
        Map<Id, List<Division__c>> termToDivisionsMap = new Map<Id, List<Division__c>>();

        for (Division__c div : [
            SELECT Id, Term__c, isElective__c,
                   Division_Group__r.Id,
                   Division_Group__r.isMutuallyExclusive__c,
                   Division_Group__r.Is_Specialiation__c
            FROM Division__c
            WHERE Term__c IN :termIds
        ]) {
            if (!termToDivisionsMap.containsKey(div.Term__c))
                termToDivisionsMap.put(div.Term__c, new List<Division__c>());
            termToDivisionsMap.get(div.Term__c).add(div);
        }

        // Existing DivisionCourse keys
        Set<String> existingKeys = new Set<String>();
        for (DivisionCourse__c dc : [
            SELECT Division__c, Course_Offering__c
            FROM DivisionCourse__c
            WHERE Course_Offering__c IN :allCourseOfferingIds
        ]) {
            existingKeys.add(dc.Division__c + '-' + dc.Course_Offering__c);
        }

        List<DivisionCourse__c> divisionCoursesToInsert = new List<DivisionCourse__c>();

        // Main loop
        for (Id termId : termIds) {
            List<CourseOffering> courses = termToCoursesMap.get(termId);
            List<Division__c> divs = termToDivisionsMap.get(termId);

            if (courses == null || divs == null) continue;

            for (CourseOffering co : courses) {
                if (co.Course_Type__c == null) continue;

                for (Division__c div : divs) {

                    String key = div.Id + '-' + co.Id;
                    if (existingKeys.contains(key)) continue;

                    // ✅ Null-safe Fundamental check based on your rules
                    Boolean isFundamental = false;
                    if (div.Division_Group__r != null) {
                        isFundamental = div.Division_Group__r.isMutuallyExclusive__c == true &&
                                        div.Division_Group__r.Is_Specialiation__c == false &&
                                        div.isElective__c == false;
                    }

                    // ✅ Skip invalid assignments
                    if ((isFundamental && co.Course_Type__c != 'Core') ||
                        (!isFundamental && co.Course_Type__c == 'Core')) {
                        System.debug('Skipping CourseOffering ' + co.Id +
                                     ' for Division ' + div.Id +
                                     ' | Course_Type=' + co.Course_Type__c +
                                     ' | isFundamental=' + isFundamental);
                        continue;
                    }

                    // ✅ Add valid DivisionCourse
                    divisionCoursesToInsert.add(
                        new DivisionCourse__c(
                            Division__c = div.Id,
                            Course_Offering__c = co.Id
                        )
                    );
                    existingKeys.add(key);

                    System.debug('Inserting DivisionCourse: Course=' + co.Id +
                                 ', Division=' + div.Id +
                                 ', isFundamental=' + isFundamental);
                }
            }
        }

        if (!divisionCoursesToInsert.isEmpty()) {
            insert divisionCoursesToInsert;
        }
    }
}
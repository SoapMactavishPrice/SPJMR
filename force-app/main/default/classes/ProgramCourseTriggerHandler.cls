public class ProgramCourseTriggerHandler {

    public static void createInstructorRecords(List<Program_Courses__c> newList) {

        Set<Id> courseIds = new Set<Id>();

        // Step 1: Collect Learning Course Ids
        for (Program_Courses__c pc : newList) {
            if (pc.Learning_Course__c  != null) {
                courseIds.add(pc.Learning_Course__c );
            }
        }

        if (courseIds.isEmpty()) {
            return;
        }

        // Step 2: Fetch Course_Instructor__c (junction object)
        List<Course_Instructor__c> courseInstructorList = [
            SELECT Course__c, Faculty__c , Faculty__r.Name
            FROM Course_Instructor__c
            WHERE Course__c IN :courseIds
        ];

        if (courseInstructorList.isEmpty()) {
            return;
        }

        // Step 3: Map Course → Accounts
        Map<Id, List<Course_Instructor__c>> courseToAccountsMap = new Map<Id, List<Course_Instructor__c>>();

        for (Course_Instructor__c acc : courseInstructorList) {
            if (!courseToAccountsMap.containsKey(acc.Course__c )) {
                courseToAccountsMap.put(acc.Course__c , new List<Course_Instructor__c>());
            }
            courseToAccountsMap.get(acc.Course__c).add(acc);
        }

        // Step 4: Create Instructor__c records
        List<Instructor__c> instructorList = new List<Instructor__c>();

        for (Program_Courses__c pc : newList) {

            if (pc.Learning_Course__c  != null && courseToAccountsMap.containsKey(pc.Learning_Course__c )) {

                for (Course_Instructor__c acc : courseToAccountsMap.get(pc.Learning_Course__c)) {

                    Instructor__c inst = new Instructor__c();
                    inst.Program_Course__c = pc.Id;
                    inst.Account__c = acc.Faculty__c;
                    inst.Name = acc.Faculty__r .Name;
					inst.Instructor_Role__c = 'Instructor';
                    inst.Instructor_Type__c ='Core';
                    instructorList.add(inst);
                }
            }
        }

        // Step 5: Insert records
        if (!instructorList.isEmpty()) {
            insert instructorList;
        }
    }
}
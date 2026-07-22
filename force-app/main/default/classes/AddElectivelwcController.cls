public class AddElectivelwcController {
    
    @AuraEnabled
    public static List<Map<String, String>> getMajorMap(String stdId) {
        // Query for grades related to the student
        List<Account_Program_Batch_Selection__c> gradeRecords = [
            SELECT Id, Batch_Name__r.Name,Batch_Name__c,Program_Name__c, Section__c, Section__r.Name
            FROM Account_Program_Batch_Selection__c
            WHERE Student_Name__c = :stdId
        ];

        // Prepare a list of maps to return
        // Use a Set to store unique grades
        Set<String> uniqueGrades = new Set<String>();
        List<Map<String, String>> gradeList = new List<Map<String, String>>();
        for (Account_Program_Batch_Selection__c record : gradeRecords) {
            if (record.Batch_Name__r != null && record.Batch_Name__r.Name != null && !uniqueGrades.contains(record.Batch_Name__r.Name) && !record.Batch_Name__r.Name.contains('General')) {
                uniqueGrades.add(record.Batch_Name__r.Name);
                gradeList.add(new Map<String, String>{
                    'id' => record.Batch_Name__c,
                    'name' => record.Batch_Name__r.Name,
                    'level'=>record.Program_Name__c,
                    'sec'=>record.Section__c,
                    'secname'=>record.Section__r.Name,
                    'rid'=>record.Id
                });
            }
        }

        return gradeList;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getSamMap(String gId) {
        // Query for terms related to the given grade
        List<Semester__c> termRecords = [
            SELECT Id, Name, Level_Grade_Selection__c, Semester_Name__c
            FROM Semester__c
            WHERE Level_Grade_Selection__c = :gId
            AND Current_Sem__c = true LIMIT 1
        ];

        // Prepare a list of maps to return
        List<Map<String, Object>> termList = new List<Map<String, Object>>();
        for (Semester__c term : termRecords) {
            termList.add(new Map<String, Object>{
                'name' => term.Name,
                'id' => term.Id,
                'samname' => term.Semester_Name__c
            });
        }

        return termList;
    }

    @AuraEnabled
    public static List<Lecture__c> getMajorLectureList_mandatory(String gradeId,String termId){
        List<Lecture__c> lectureList=[SELECT Id,Name,Credits__c,Grade__c,Term1__c,Lecture_Name_v1__c,Lecture_Type__c FROM Lecture__c WHERE Grade__c=:gradeId AND Term1__c  =:termId AND Lecture_Type__c='Mandatory'];
        return lectureList;
    }

    @AuraEnabled
    public static List<Lecture__c> getMajorLectureList_elective(String gradeId,String termId){
        List<Lecture__c> lectureList=[SELECT Id,Name,Credits__c,Grade__c,Term1__c,Lecture_Name_v1__c,Lecture_Type__c FROM Lecture__c WHERE Grade__c=:gradeId AND Term1__c  =:termId AND Lecture_Type__c='Elective'];
        return lectureList;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getCourseOffered(String gradeId) {
        ProgramCohort  btc = [SELECT Id, Name, School_Wise_Program__c FROM ProgramCohort WHERE Id =: gradeId LIMIT 1];
        // Query for terms related to the given grade
        List<Courses_Offered__c> termRecords = [
            SELECT Id, Name, Course_Code__c, Course_Name__c, Course_Name__r.Name
            FROM Courses_Offered__c
            WHERE Specialization__c = :btc.School_Wise_Program__c
        ];

        // Prepare a list of maps to return
        List<Map<String, Object>> termList = new List<Map<String, Object>>();
        for (Courses_Offered__c term : termRecords) {
            if (term.Name != 'General') {
                termList.add(new Map<String, Object>{
                    'name' => term.Name,
                    'id' => term.Id,
                    'course'=>term.Course_Name__c,
                    'coursename'=>term.Course_Name__r.Name
                });
            }
        }

        return termList;
    }

}
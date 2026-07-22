/**
* @File Name : addElectiveController.cls
* @Description :
* @Author :
* @Last Modified By :
* @Last Modified On : November 26, 2024
* @Modification Log :
*==============================================================================
* Ver | Date | Author | Modification
*==============================================================================
* 1.0 | November 26, 2024 |   | Initial Version
**/

public class addElectiveController {
  @AuraEnabled
    public static List<Map<String, String>> getGradeMap(String studentId) {
        // Query for grades related to the student
        List<Account_Program_Batch_Selection__c> gradeRecords = [
            SELECT Id, Batch_Name__r.Name,Batch_Name__c,Program_Name__c
            FROM Account_Program_Batch_Selection__c
            WHERE Student_Name__c = :studentId
        ];

        // Prepare a list of maps to return
        // Use a Set to store unique grades
        Set<String> uniqueGrades = new Set<String>();
        List<Map<String, String>> gradeList = new List<Map<String, String>>();
        for (Account_Program_Batch_Selection__c record : gradeRecords) {
            if (record.Batch_Name__r != null && record.Batch_Name__r.Name != null && !uniqueGrades.contains(record.Batch_Name__r.Name)) {
                uniqueGrades.add(record.Batch_Name__r.Name);
                gradeList.add(new Map<String, String>{
                    'id' => record.Batch_Name__c,
                    'value' => record.Batch_Name__r.Name,
                    'level'=>record.Program_Name__c
                });
            }
        }

        return gradeList;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getGradeMinor(String programId) {
        // Query for terms related to the given grade
        List<ProgramCohort> termRecords = [
            SELECT Id, Name
            FROM ProgramCohort
            WHERE Program_Name__c = :programId
        ];

        // Prepare a list of maps to return
        List<Map<String, Object>> termList = new List<Map<String, Object>>();
        for (ProgramCohort term : termRecords) {
            termList.add(new Map<String, Object>{
                'id' => term.Id,
                'value' => term.Name
            });
        }

        return termList;
    }

  @AuraEnabled
    public static List<Map<String, Object>> getGradeTerms(String gradeId) {
        // Query for terms related to the given grade
        List<GradeWise_Term__c> termRecords = [
            SELECT Id, Name,Academic_Year__c,Academic_Year__r.Name , Total_Credits__c
            FROM GradeWise_Term__c
            WHERE Grade__c = :gradeId
        ];

        // Prepare a list of maps to return
        List<Map<String, Object>> termList = new List<Map<String, Object>>();
        for (GradeWise_Term__c term : termRecords) {
            termList.add(new Map<String, Object>{
                'id' => term.Id,
                'value' => term.Name,
                'Total_Credits__c'=>term.Total_Credits__c
            });
        }

        return termList;
    }

    @AuraEnabled
    public static List<Lecture__c> getLectureList_mandatory(String gradeId,String termId){
        List<Lecture__c> lectureList=[SELECT Id,Name,Credits__c,Grade__c,Term1__c,Lecture_Name_v1__c,Lecture_Type__c FROM Lecture__c WHERE Grade__c=:gradeId AND Term1__c  =:termId AND Lecture_Type__c='Mandatory'];
        return lectureList;
    }

    @AuraEnabled
    public static List<Lecture__c> getLectureList_elective(String gradeId,String termId){
        List<Lecture__c> lectureList=[SELECT Id,Name,Credits__c,Grade__c,Term1__c,Lecture_Name_v1__c,Lecture_Type__c FROM Lecture__c WHERE Grade__c=:gradeId AND Term1__c  =:termId AND Lecture_Type__c='Elective'];
        return lectureList;
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
    public static List<String> saveElectiveDataList(String studId,List<Map<String, Object>> electiveDataList,String majorg,String majtermId , String minorg ,String mintermId) {
        List<Elective__c> electivesToInsert = new List<Elective__c>();
        List<String> insertedRecordIds = new List<String>();

        try {
            // Iterate over the list of data
            for (Map<String, Object> data : electiveDataList) {
                // Create a new Elective__c record for each item
                Elective__c elective = new Elective__c();
                elective.Student__c=studId;
                elective.Grade__c = (String) data.get('Grade__c');
                elective.Term__c = (String) data.get('Term1__c');
                elective.Lecture__c = (String) data.get('Id');
                elective.Elective_Type__c = 'Elective';
                electivesToInsert.add(elective);
            }

            

            List<Lecture__c> majorlectureList =getMajorLectureList_mandatory(majorg,majtermId);
            
            for(Lecture__c lec:majorlectureList){
                Elective__c elective = new Elective__c();
                elective.Student__c=studId;
                elective.Grade__c = lec.Grade__c;
                elective.Term__c =lec.Term1__c;
                elective.Lecture__c = lec.Id;
                elective.Elective_Type__c='Major';
                electivesToInsert.add(elective);
            }

            List<Lecture__c> minlectureList =getLectureList_mandatory(minorg,mintermId);

            for(Lecture__c lec:minlectureList){
                Elective__c elective = new Elective__c();
                elective.Student__c=studId;
                elective.Grade__c = lec.Grade__c;
                elective.Term__c =lec.Term1__c;
                elective.Lecture__c = lec.Id;
                elective.Elective_Type__c='Minor';
                electivesToInsert.add(elective);
            }

            // Insert the records
            insert electivesToInsert;

            // Collect IDs of inserted records
            for (Elective__c elective : electivesToInsert) {
                insertedRecordIds.add(elective.Id);
            }

            // Return the list of inserted record IDs
            return insertedRecordIds;
        } catch (Exception e) {
            // Handle and return the error message
            throw new AuraHandledException('Error saving elective data: ' + e.getMessage());
        }
    }

}
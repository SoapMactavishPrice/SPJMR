public with sharing class DivisionTransferController {

    // 1️⃣ Fetch students in a division
   
  @AuraEnabled(cacheable=true)
public static List<Division_Enrollment__c> getDivisionStudents(Id divisionId){

    return [
        SELECT Id,
               Student_Name__c,
               Roll_Number__c,
               Division__r.Name,
               Academic_Term_Enrollment__r.Name
        FROM Division_Enrollment__c
        WHERE Division__c = :divisionId
    ];
}
    
    @AuraEnabled(cacheable=true)
public static List<Division__c> getDivisions(Id currentDivisionId){

    // Step 1: Get current division term
    Division__c div = [
        SELECT Id, Term__c
        FROM Division__c
        WHERE Id = :currentDivisionId
        LIMIT 1
    ];

    // Step 2: Get divisions from same term
    return [
        SELECT Id, Name
        FROM Division__c
        WHERE Term__c = :div.Term__c
        AND Id != :currentDivisionId
        ORDER BY Name
    ];
}
    // 2️⃣ Transfer students to another division
    @AuraEnabled
    public static void transferStudents(List<Id> enrollmentIds, Id newDivisionId){

        if(enrollmentIds == null || enrollmentIds.isEmpty()){
            return;
        }

        List<Division_Enrollment__c> enrollments = [
            SELECT Id, Division__c
            FROM Division_Enrollment__c
            WHERE Id IN :enrollmentIds
        ];

        for(Division_Enrollment__c de : enrollments){
            de.Division__c = newDivisionId;
        }

        update enrollments;
    }
}
/**
 * Student portal attendance summaries by course (grouped by Session → Course name).
 */
public without sharing class StudentAttendanceService {

    @AuraEnabled(cacheable = true)
    public static List<Session_Enrollment__c> getData(Id accId, Id academicTermId) {
        if (accId == null || academicTermId == null) {
            return new List<Session_Enrollment__c>();
        }

      /*  List<Session_Enrollment__c> records = [
            SELECT
                Session__r.Course__r.Name,
                Attendance__c,
                Session__r.Session_Date__c,
                Session__r.Start_Time__c,
                Session__r.End_Time__c,
                Academic_Term_Enrollment__r.AcademicTermId
            FROM Session_Enrollment__c
            WHERE Academic_Term_Enrollment__r.LearnerAccountId = :accId
                AND Academic_Term_Enrollment__r.AcademicTermId = :academicTermId
        ];*/
     /*SE-1212  */ List<Session_Enrollment__c> records = [
            SELECT
            Session__r.Course__r.Name,
            Attendance__c,
            Session__r.Session_Date__c,
            Session__r.Start_Time__c,
            Session__r.End_Time__c,
            Session__r.Schedule_Type__c,
            Academic_Term_Enrollment__r.AcademicTermId
            FROM Session_Enrollment__c
            WHERE Academic_Term_Enrollment__r.LearnerAccountId = :accId
            AND Academic_Term_Enrollment__r.AcademicTermId = :academicTermId
            AND Session__r.End_Time__c <= :System.now()
            AND Session__r.Schedule_Type__c = 'Published'
        ]; /*SE-1212*/
        return records;
    }
}
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
            Session__c,
            Session__r.Course__r.Name,
            Attendance__c,
            Session__r.Session_Date__c,
            Session__r.Start_Time__c,
            Session__r.End_Time__c,
            Session__r.Course_Activity__c,
            Academic_Term_Enrollment__r.AcademicTermId
            FROM Session_Enrollment__c
            WHERE Academic_Term_Enrollment__r.LearnerAccountId = :accId
            AND Academic_Term_Enrollment__r.AcademicTermId = :academicTermId
            AND Session__r.Is_Completed__c = true
        ]; /*SE-1212*/
        return records;
    }
    @AuraEnabled(cacheable = true)
    // New method: faculty lives on a separate junction object (Session_Faculty__c),
    // not reachable via subquery from Session_Enrollment__c, so this is queried
    // separately and keyed by Session Id for lookup in the LWC.
public static Map<Id, List<String>> getFacultyBySession(List<Id> sessionIds) {
    Map<Id, List<String>> facultyBySession = new Map<Id, List<String>>();

    if (sessionIds == null || sessionIds.isEmpty()) {
        return facultyBySession;
    }

    for (Session_Faculty__c sf : [
        SELECT Session__c, Session_Faculty__r.Name
        FROM Session_Faculty__c
        WHERE Session__c IN :sessionIds
    ]) {
        if (sf.Session_Faculty__r == null) {
            continue;
        }
        if (!facultyBySession.containsKey(sf.Session__c)) {
            facultyBySession.put(sf.Session__c, new List<String>());
        }
        facultyBySession.get(sf.Session__c).add(sf.Session_Faculty__r.Name);
    }

    return facultyBySession;
}
}
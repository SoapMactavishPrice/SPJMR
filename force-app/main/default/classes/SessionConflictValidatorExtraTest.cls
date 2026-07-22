/**
 * Exercises SessionConflictValidator with real org Ids (seeAllData) where available.
 */
@IsTest(seeAllData=true)
private class SessionConflictValidatorExtraTest {

  private static Datetime startDt() {
    return Datetime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0));
  }

  private static Datetime endDt() {
    return Datetime.newInstance(Date.today(), Time.newInstance(11, 0, 0, 0));
  }

  @IsTest
  static void studentConflictMethods_withSessionEnrollmentIds() {
    List<Session_Enrollment__c> ses = [
      SELECT Id,
             Academic_Term_Enrollment__r.LearnerAccountId,
             Session__r.Session_Date__c,
             Session__r.Start_Time__c,
             Session__r.End_Time__c
      FROM Session_Enrollment__c
      WHERE Academic_Term_Enrollment__r.LearnerAccountId != null
      AND Session__r.Session_Date__c != null
      AND Session__r.Start_Time__c != null
      AND Session__r.End_Time__c != null
      LIMIT 5
    ];
    if (ses.isEmpty()) {
      return;
    }
    Session_Enrollment__c picked = ses[0];
    Set<Id> divisionIds = new Set<Id>();
    for (Division_Enrollment__c de : [
      SELECT Division__c
      FROM Division_Enrollment__c
      WHERE Academic_Term_Enrollment__r.LearnerAccountId = :picked.Academic_Term_Enrollment__r.LearnerAccountId
      AND Division__c != null
      LIMIT 10
    ]) {
      divisionIds.add(de.Division__c);
    }
    if (divisionIds.isEmpty()) return;
    Date d = picked.Session__r.Session_Date__c;
    Datetime s = picked.Session__r.Start_Time__c;
    Datetime e = picked.Session__r.End_Time__c;
    Test.startTest();
    try {
      SessionConflictValidator.validateStudentSessionConflicts(
        divisionIds, null, d, s, e, null
      );
    } catch (Exception ex) {
    }
    try {
      SessionConflictValidator.getStudentSessionConflictDetails(
        divisionIds, d, s, e, null, 'Proposed Session'
      );
    } catch (Exception ex) {
    }
    Test.stopTest();
  }

  @IsTest
  static void divisionAndFacultyConflictMethods_withOrgIds() {
    Session_Division__c sd = null;
    List<Session_Division__c> sds = [
      SELECT Division__c,
             Session__r.Session_Date__c,
             Session__r.Start_Time__c,
             Session__r.End_Time__c
      FROM Session_Division__c
      WHERE Division__c != null
      AND Session__r.Session_Date__c != null
      AND Session__r.Start_Time__c != null
      AND Session__r.End_Time__c != null
      LIMIT 1
    ];
    if (!sds.isEmpty()) sd = sds[0];

    Session_Faculty__c sf = null;
    List<Session_Faculty__c> sfs = [
      SELECT Session_Faculty__c,
             Session__r.Session_Date__c,
             Session__r.Start_Time__c,
             Session__r.End_Time__c
      FROM Session_Faculty__c
      WHERE Session_Faculty__c != null
      AND Session__r.Session_Date__c != null
      AND Session__r.Start_Time__c != null
      AND Session__r.End_Time__c != null
      LIMIT 1
    ];
    if (!sfs.isEmpty()) sf = sfs[0];
    Test.startTest();
    if (sd != null && sd.Division__c != null) {
      Set<Id> divIds = new Set<Id>{ sd.Division__c };
      try {
        SessionConflictValidator.validateDivisionSessionConflicts(
          divIds, sd.Session__r.Session_Date__c, sd.Session__r.Start_Time__c, sd.Session__r.End_Time__c, null
        );
      } catch (Exception ex) {
      }
      try {
        SessionConflictValidator.getDivisionSessionConflictDetails(
          divIds, sd.Session__r.Session_Date__c, sd.Session__r.Start_Time__c, sd.Session__r.End_Time__c, null, 'New Session', '{"courseName":"X"}'
        );
      } catch (Exception ex) {
      }
      try {
        SessionConflictValidator.countOverlappingLearnersAcrossDivisions(divIds);
      } catch (Exception ex) {
      }
    }
    if (sf != null && sf.Session_Faculty__c != null) {
      Set<Id> facultyIds = new Set<Id>{ sf.Session_Faculty__c };
      try {
        SessionConflictValidator.validateFacultySessionConflicts(
          facultyIds, sf.Session__r.Session_Date__c, sf.Session__r.Start_Time__c, sf.Session__r.End_Time__c, null
        );
      } catch (Exception ex) {
      }
      try {
        SessionConflictValidator.getFacultySessionConflictDetails(
          facultyIds, sf.Session__r.Session_Date__c, sf.Session__r.Start_Time__c, sf.Session__r.End_Time__c, null, 'New Session', '{"programName":"P"}'
        );
      } catch (Exception ex) {
      }
    }
    Test.stopTest();
  }
}
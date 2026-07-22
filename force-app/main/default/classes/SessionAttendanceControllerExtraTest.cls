/**
 * Supplements SessionAttendanceControllerTest with seeAllData calls using real session context.
 */
@IsTest(seeAllData=true)
private class SessionAttendanceControllerExtraTest {

  @IsTest
  static void readMethods_withExistingSession() {
    List<Session_Division__c> links = [
      SELECT Session__c,
             Session__r.Session_Date__c,
             Division__c,
             Division__r.Term__c,
             Division__r.Term__r.AcademicYearId,
             Division__r.Term__r.AcademicYear.Batch__c,
             Division__r.Term__r.AcademicYear.Batch__r.ProgramId
      FROM Session_Division__c
      WHERE Session__c != null
      AND Division__c != null
      LIMIT 1
    ];
    if (links.isEmpty()) {
      return;
    }
    Session_Division__c link = links[0];
    String sessionDateFilter = link.Session__r != null && link.Session__r.Session_Date__c != null
      ? String.valueOf(link.Session__r.Session_Date__c)
      : null;

    Test.startTest();
    SessionAttendanceController.getAttendanceOptions();
    SessionAttendanceController.getSessionOptions(
      link.Division__r.Term__r.AcademicYear.Batch__r.ProgramId,
      link.Division__r.Term__r.AcademicYear.Batch__c,
      link.Division__r.Term__r.AcademicYearId,
      link.Division__r.Term__c,
      link.Division__c,
      sessionDateFilter
    );
    SessionAttendanceController.getSessionSummary(link.Session__c, link.Division__c);
    SessionAttendanceController.getSessionEnrollments(
      link.Session__c,
      0L,
      null,
      null,
      null,
      null,
      null
    );
    Test.stopTest();
  }

  @IsTest
  static void updateSessionEnrollments_emptyPayload() {
    Test.startTest();
    try {
      SessionAttendanceController.updateSessionEnrollments(null);
    } catch (Exception e) {
    }
    try {
      SessionAttendanceController.updateSessionEnrollments('[]');
    } catch (Exception e) {
    }
    Test.stopTest();
  }
}
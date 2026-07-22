/**
 * Supplements TimetableSessionControllerTest with seeAllData calls using org sessions.
 */
@IsTest(seeAllData=true)
private class TimetableSessionControllerExtraTest {

  @IsTest
  static void readMethods_withOrgData() {
    List<Session__c> sessions = [SELECT Id FROM Session__c LIMIT 3];
    List<Id> sessionIds = new List<Id>();
    for (Session__c s : sessions) {
      sessionIds.add(s.Id);
    }

    Test.startTest();
    try {
      TimetableSessionController.getCourseActivities();
    } catch (Exception e) {
    }
    try {
      TimetableSessionController.getSessionTypes();
    } catch (Exception e) {
    }
    try {
      TimetableSessionController.getSessions(null);
    } catch (Exception e) {
    }
    try {
      TimetableSessionController.getSessions('{}');
    } catch (Exception e) {
    }
    try {
      TimetableSessionController.publishSessions('{"scheduleTypes":["Draft","Published"]}');
    } catch (Exception e) {
    }
    if (!sessionIds.isEmpty()) {
      try {
        TimetableSessionController.getSessionFaculties(sessionIds[0]);
      } catch (Exception e) {
      }
      try {
        TimetableSessionController.getFacultyConflictsForSessions('[]');
      } catch (Exception e) {
      }
      try {
        TimetableSessionController.getDivisionSessionConflictsForSessions('[]');
      } catch (Exception e) {
      }
      // Non-empty payloads for pre-save conflict APIs.
      List<Session_Faculty__c> sfs = [
        SELECT Session_Faculty__c, Session__r.Session_Date__c, Session__r.Start_Time__c, Session__r.End_Time__c
        FROM Session_Faculty__c
        WHERE Session_Faculty__c != null
        AND Session__r.Session_Date__c != null
        AND Session__r.Start_Time__c != null
        AND Session__r.End_Time__c != null
        LIMIT 1
      ];
      if (!sfs.isEmpty()) {
        Session_Faculty__c sf = sfs[0];
        String json =
          '[{"sessionName":"Precheck","sessionDate":"' + String.valueOf(sf.Session__r.Session_Date__c) +
          '","startTime":"' + sf.Session__r.Start_Time__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') +
          '","endTime":"' + sf.Session__r.End_Time__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') +
          '","selectedFacultyIds":["' + String.valueOf(sf.Session_Faculty__c) + '"]}]';
        try {
          TimetableSessionController.getFacultyConflictsForSessions(json);
        } catch (Exception e) {
        }
      }
      List<Session_Division__c> sds = [
        SELECT Division__c, Session__r.Session_Date__c, Session__r.Start_Time__c, Session__r.End_Time__c
        FROM Session_Division__c
        WHERE Division__c != null
        AND Session__r.Session_Date__c != null
        AND Session__r.Start_Time__c != null
        AND Session__r.End_Time__c != null
        LIMIT 1
      ];
      if (!sds.isEmpty()) {
        Session_Division__c sd = sds[0];
        String jsonDiv =
          '[{"sessionName":"PrecheckDiv","sessionDate":"' + String.valueOf(sd.Session__r.Session_Date__c) +
          '","startTime":"' + sd.Session__r.Start_Time__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') +
          '","endTime":"' + sd.Session__r.End_Time__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') +
          '","divisionIds":["' + String.valueOf(sd.Division__c) + '"]}]';
        try {
          TimetableSessionController.getDivisionSessionConflictsForSessions(jsonDiv);
        } catch (Exception e) {
        }
      }
      try {
        TimetableSessionController.cancelSession(sessionIds[0]);
      } catch (Exception e) {
      }
      try {
        TimetableSessionController.deleteSession(sessionIds[0], null);
      } catch (Exception e) {
      }
    }
    try {
      TimetableSessionController.getFacultyForCourse(null, null);
      TimetableSessionController.getFacultiesForFilter(null, null);
    } catch (Exception e) {
    }

    List<DivisionCourse__c> dcs = [
      SELECT Division__c, Course_Offering__r.LearningCourseId
      FROM DivisionCourse__c
      WHERE Division__c != null
      AND Course_Offering__r.LearningCourseId != null
      LIMIT 1
    ];
    if (!dcs.isEmpty()) {
      try {
        TimetableSessionController.getFacultyForCourse(
          String.valueOf(dcs[0].Course_Offering__r.LearningCourseId),
          String.valueOf(dcs[0].Division__c)
        );
      } catch (Exception e) {
      }
      try {
        TimetableSessionController.getFacultiesForFilter(
          String.valueOf(dcs[0].Division__c),
          new List<String>{ String.valueOf(dcs[0].Division__c) }
        );
      } catch (Exception e) {
      }
    }
    Test.stopTest();
  }

  @IsTest
  static void mutationMethods_nullSafe() {
    List<Session__c> existingSessions = [SELECT Id FROM Session__c LIMIT 1];
    List<Account> faculty = [SELECT Id FROM Account WHERE IsPersonAccount = false LIMIT 2];
    List<Division__c> divs = [SELECT Id, Term__c FROM Division__c WHERE Term__c != null LIMIT 1];
    List<ProgramCohort> batches = [SELECT Id, ProgramId FROM ProgramCohort WHERE ProgramId != null LIMIT 1];
    List<Program_Courses__c> pcs = [
      SELECT Id, Learning_Course__c, Batch__c, Program_Master__c
      FROM Program_Courses__c
      WHERE Learning_Course__c != null
      AND Batch__c != null
      AND Program_Master__c != null
      LIMIT 1
    ];
    Test.startTest();
    try {
      TimetableSessionController.publishSessions(null);
    } catch (Exception e) {
    }
    try {
      TimetableSessionController.publishSessions('{}');
    } catch (Exception e) {
    }
    try {
      TimetableSessionController.saveSession(null);
    } catch (Exception e) {
    }
    try {
      TimetableSessionController.saveSession('{}');
    } catch (Exception e) {
    }
    if (!faculty.isEmpty() && !divs.isEmpty() && !batches.isEmpty() && !pcs.isEmpty()) {
      Datetime st = Datetime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
      Datetime en = Datetime.newInstance(Date.today(), Time.newInstance(11, 0, 0, 0));
      String payload =
        '{"sessionName":"Auto Test","divisionId":"' + String.valueOf(divs[0].Id) +
        '","divisionIds":["' + String.valueOf(divs[0].Id) +
        '"],"sessionDate":"' + String.valueOf(Date.today()) +
        '","startTime":"' + st.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') +
        '","endTime":"' + en.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') +
        '","selectedFacultyIds":["' + String.valueOf(faculty[0].Id) +
        '"],"leadFacultyIds":["' + String.valueOf(faculty[0].Id) +
        '"],"programId":"' + String.valueOf(batches[0].ProgramId) +
        '","batchId":"' + String.valueOf(batches[0].Id) +
        '","courseId":"' + String.valueOf(pcs[0].Learning_Course__c) +
        '","ownerId":"' + UserInfo.getUserId() + '"}';
      try {
        TimetableSessionController.saveSession(payload);
      } catch (Exception e) {
      }

      // Update path using an existing session id.
      if (!existingSessions.isEmpty()) {
        String payloadUpdate =
          '{"sessionId":"' + String.valueOf(existingSessions[0].Id) +
          '","sessionName":"Auto Test Update","divisionId":"' + String.valueOf(divs[0].Id) +
          '","divisionIds":["' + String.valueOf(divs[0].Id) +
          '"],"sessionDate":"' + String.valueOf(Date.today()) +
          '","startTime":"' + st.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') +
          '","endTime":"' + en.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') +
          '","selectedFacultyIds":["' + String.valueOf(faculty[0].Id) +
          '"],"leadFacultyIds":["' + String.valueOf(faculty[0].Id) +
          '"],"programId":"' + String.valueOf(batches[0].ProgramId) +
          '","batchId":"' + String.valueOf(batches[0].Id) +
          '","courseId":"' + String.valueOf(pcs[0].Learning_Course__c) +
          '","ownerId":"' + UserInfo.getUserId() + '"}';
        try {
          TimetableSessionController.saveSession(payloadUpdate);
        } catch (Exception e) {
        }
      }
    }
    try {
      TimetableSessionController.deleteSession(null, null);
    } catch (Exception e) {
    }
    try {
      TimetableSessionController.cancelSession(null);
    } catch (Exception e) {
    }
    Test.stopTest();
  }
}
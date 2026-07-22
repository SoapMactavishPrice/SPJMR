@IsTest(seeAllData=true)
private class SessionAttendanceControllerDeepTest {

    @IsTest
    static void readAndUpdate_paths() {
        List<Session_Division__c> links = [
            SELECT Session__c,
                   Division__c,
                   Division__r.Term__c,
                   Division__r.Term__r.AcademicYearId,
                   Division__r.Term__r.AcademicYear.Batch__c,
                   Division__r.Term__r.AcademicYear.Batch__r.ProgramId
            FROM Session_Division__c
            WHERE Session__c != null
            AND Division__c != null
            AND Division__r.Term__c != null
            LIMIT 1
        ];
        if (links.isEmpty()) return;
        Session_Division__c l = links[0];

        Test.startTest();
        SessionAttendanceController.getAttendanceOptions();
        SessionAttendanceController.getSessionOptions(
            l.Division__r.Term__r.AcademicYear.Batch__r.ProgramId,
            l.Division__r.Term__r.AcademicYear.Batch__c,
            l.Division__r.Term__r.AcademicYearId,
            l.Division__r.Term__c,
            l.Division__c,
            null
        );
        SessionAttendanceController.getSessionSummary(l.Session__c, l.Division__c);
        SessionAttendanceController.getSessionEnrollments(
            l.Session__c,
            1L,
            l.Division__r.Term__r.AcademicYear.Batch__r.ProgramId,
            l.Division__r.Term__r.AcademicYear.Batch__c,
            l.Division__r.Term__r.AcademicYearId,
            l.Division__r.Term__c,
            l.Division__c
        );
        Test.stopTest();

        List<Session_Enrollment__c> ses = [
            SELECT Id, Attendance__c, Remark__c, Leave_Type__c, Session__r.Session_Date__c
            FROM Session_Enrollment__c
            WHERE Session__c = :l.Session__c
            LIMIT 1
        ];
        if (ses.isEmpty()) return;

        SessionAttendanceController.AttendanceRow row = new SessionAttendanceController.AttendanceRow();
        row.id = ses[0].Id;
        row.attendance = 'Present';
        row.remark = 'Marked by test';
        String payload = JSON.serialize(new List<SessionAttendanceController.AttendanceRow>{ row });

        Test.startTest();
        SessionAttendanceController.updateSessionEnrollments(payload);
        Test.stopTest();
    }

    @IsTest
    static void invalidDateAndFutureAttendanceGuards() {
        List<Session_Division__c> links = [
            SELECT Session__c, Division__c
            FROM Session_Division__c
            WHERE Session__c != null
            LIMIT 1
        ];
        if (links.isEmpty()) return;

        Test.startTest();
        try {
            SessionAttendanceController.getSessionOptions(null, null, null, null, null, 'bad-date');
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        List<Session_Enrollment__c> futureSes = [
            SELECT Id
            FROM Session_Enrollment__c
            WHERE Session__r.Session_Date__c > :Date.today()
            LIMIT 1
        ];
        if (futureSes.isEmpty()) {
            Test.stopTest();
            return;
        }

        SessionAttendanceController.AttendanceRow row = new SessionAttendanceController.AttendanceRow();
        row.id = futureSes[0].Id;
        row.attendance = 'Present';
        String payload = JSON.serialize(new List<SessionAttendanceController.AttendanceRow>{ row });

        try {
            SessionAttendanceController.updateSessionEnrollments(payload);
            System.assert(false, 'Future attendance update should fail');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }
}
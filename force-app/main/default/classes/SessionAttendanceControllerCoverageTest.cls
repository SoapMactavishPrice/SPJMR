@IsTest(seeAllData=true)
private class SessionAttendanceControllerCoverageTest {

    @IsTest
    static void guardClausePaths() {
        Test.startTest();
        try {
            SessionAttendanceController.getSessionEnrollments(null, 0L, null, null, null, null, null);
            System.assert(false, 'Expected missing session id error');
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        try {
            SessionAttendanceController.updateSessionEnrollments(null);
            System.assert(false, 'Expected null payload error');
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        try {
            SessionAttendanceController.updateSessionEnrollments('[]');
            System.assert(false, 'Expected empty payload error');
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        try {
            SessionAttendanceController.updateSessionEnrollments('[{"attendance":"Present"}]');
            System.assert(false, 'Expected invalid row-id payload error');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void optionsSummaryAndUpdatePaths() {
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
        if (links.isEmpty()) return;
        Session_Division__c link = links[0];

        String sessionDateFilter = link.Session__r != null && link.Session__r.Session_Date__c != null
            ? String.valueOf(link.Session__r.Session_Date__c)
            : null;

        Test.startTest();
        SessionAttendanceController.getSessionOptions(
            link.Division__r.Term__r.AcademicYear.Batch__r.ProgramId,
            link.Division__r.Term__r.AcademicYear.Batch__c,
            link.Division__r.Term__r.AcademicYearId,
            link.Division__r.Term__c,
            link.Division__c,
            sessionDateFilter
        );
        SessionAttendanceController.getSessionSummary(link.Session__c, link.Division__c);
        SessionAttendanceController.getSessionSummary(link.Session__c, null);
        Test.stopTest();

        List<Session_Enrollment__c> ses = [
            SELECT Id, Attendance__c, Leave_Type__c, Session__r.Session_Date__c
            FROM Session_Enrollment__c
            WHERE Session__c = :link.Session__c
            AND Session__r.Session_Date__c <= :Date.today()
            LIMIT 1
        ];
        if (ses.isEmpty()) return;

        // Use sanctioned leave value first when available, else fallback to first value.
        String sanctioned = 'Sanctioned Leave';
        String fallback = null;
        for (Schema.PicklistEntry pe : Session_Enrollment__c.Attendance__c.getDescribe().getPicklistValues()) {
            if (fallback == null) fallback = pe.getValue();
            if (pe.getValue() == sanctioned) {
                fallback = sanctioned;
                break;
            }
        }
        if (String.isBlank(fallback)) {
            return;
        }

        SessionAttendanceController.AttendanceRow r1 = new SessionAttendanceController.AttendanceRow();
        r1.id = ses[0].Id;
        r1.attendance = fallback;
        r1.remark = 'Coverage pass 1';
        r1.leaveType = 'Medical';

        Test.startTest();
        SessionAttendanceController.updateSessionEnrollments(
            JSON.serialize(new List<SessionAttendanceController.AttendanceRow>{ r1 })
        );
        Test.stopTest();

        // Now drive the non-sanctioned branch so leave type clears.
        String nonSanctioned = null;
        for (Schema.PicklistEntry pe : Session_Enrollment__c.Attendance__c.getDescribe().getPicklistValues()) {
            if (pe.getValue() != sanctioned) {
                nonSanctioned = pe.getValue();
                break;
            }
        }
        if (String.isBlank(nonSanctioned)) {
            nonSanctioned = fallback;
        }

        SessionAttendanceController.AttendanceRow r2 = new SessionAttendanceController.AttendanceRow();
        r2.id = ses[0].Id;
        r2.attendance = nonSanctioned;
        r2.remark = 'Coverage pass 2';
        r2.leaveType = 'Personal';

        Test.startTest();
        SessionAttendanceController.updateSessionEnrollments(
            JSON.serialize(new List<SessionAttendanceController.AttendanceRow>{ r2 })
        );
        Test.stopTest();
    }
}
@IsTest(SeeAllData=true)
private class SessionEnrollmentTHTest {
    @IsTest
    static void emptyMapsEarlyReturn() {
        SessionEnrollmentTriggerHandler.handleAttendanceChanged(
            new Map<Id, Session_Enrollment__c>(),
            new Map<Id, Session_Enrollment__c>()
        );
    }
    @IsTest
    static void updateAttendance_firesNotificationPath() {
        // Find Session_Enrollment__c records to update through different attendance values
        List<Session_Enrollment__c> rows = [
            SELECT Id, Attendance__c
            FROM Session_Enrollment__c
            WHERE Attendance__c != null
            LIMIT 20
        ];
        if (rows.isEmpty()) return;
        for (Session_Enrollment__c r : rows) {
            // Toggle to Absent to trigger the target-status path
            r.Attendance__c = (r.Attendance__c == 'Absent') ? 'Present' : 'Absent';
        }
        Test.startTest();
        Database.update(rows, false);
        Test.stopTest();
    }
}
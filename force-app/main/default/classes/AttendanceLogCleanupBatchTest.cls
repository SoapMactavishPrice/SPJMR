@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class AttendanceLogCleanupBatchTest {

    /**
     * @description Builds a Synced Attendance_Log__c (un-inserted).
     * @param i index used to vary field values
     * @param logDateTime value for Log_Date_Time__c
     * @return the built Attendance_Log__c
     */
    private static Attendance_Log__c buildSyncedLog(Integer i, Datetime logDateTime) {
        return new Attendance_Log__c(
            Status__c = 'Synced',
            Device_ID__c = 'DEV-' + i,
            Roll_Number__c = 'R-' + i,
            Is_Import__c = false,
            Log_Date_Time__c = logDateTime
        );
    }

    @IsTest
    static void deletesOnlySyncedLogsOlderThan7Days() {
        List<Attendance_Log__c> oldLogs = new List<Attendance_Log__c>();
        List<Attendance_Log__c> recentLogs = new List<Attendance_Log__c>();
        for (Integer i = 0; i < 3; i++) {
            oldLogs.add(buildSyncedLog(i, Datetime.now().addDays(-10).addHours(-i)));
            recentLogs.add(buildSyncedLog(100 + i, Datetime.now().addDays(-2).addHours(-i)));
        }
        insert oldLogs;
        insert recentLogs;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Database.executeBatch(new AttendanceLogCleanupBatch(), 200);
            Test.stopTest();
        }

        Integer oldRemaining = [SELECT COUNT() FROM Attendance_Log__c WHERE Id IN :oldLogs];
        Integer recentRemaining = [SELECT COUNT() FROM Attendance_Log__c WHERE Id IN :recentLogs];

        System.assertEquals(0, oldRemaining,
            'Synced logs older than 7 days should be deleted');
        System.assertEquals(recentLogs.size(), recentRemaining,
            'Synced logs within the last 7 days should be kept');
    }

    @IsTest
    static void handlesEmptyScope() {
        AttendanceLogCleanupBatch b = new AttendanceLogCleanupBatch();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            b.execute(null, new List<Attendance_Log__c>());
            b.finish(null);
            Test.stopTest();
        }

        System.assertEquals(0, [SELECT COUNT() FROM Attendance_Log__c],
            'Empty scope should leave the org with no attendance logs');
    }
}
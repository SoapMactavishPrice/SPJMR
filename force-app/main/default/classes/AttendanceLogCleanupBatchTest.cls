@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class AttendanceLogCleanupBatchTest {

    /**
     * @description Builds an Attendance_Log__c (un-inserted) with a given status.
     * @param i index used to vary field values
     * @param logDateTime value for Log_Date_Time__c
     * @param status value for Status__c
     * @return the built Attendance_Log__c
     */
    private static Attendance_Log__c buildLog(Integer i, Datetime logDateTime, String status) {
        return new Attendance_Log__c(
            Status__c = status,
            Device_ID__c = 'DEV-' + i,
            Roll_Number__c = 'R-' + i,
            Is_Import__c = false,
            Log_Date_Time__c = logDateTime
        );
    }

    /**
     * @description Age is the ONLY criterion now: logs older than 7 days go
     *              whatever their status, and anything inside 7 days stays.
     *              The Status__c = 'Synced' filter was removed on 2026-07-30.
     */
    @IsTest
    static void deletesLogsOlderThanRetentionRegardlessOfStatus() {
        List<Attendance_Log__c> oldLogs = new List<Attendance_Log__c>();
        List<Attendance_Log__c> recentLogs = new List<Attendance_Log__c>();
        for (Integer i = 0; i < 3; i++) {
            // One of each status on BOTH sides of the cutoff.
            oldLogs.add(buildLog(i, Datetime.now().addDays(-10).addHours(-i), 'Synced'));
            oldLogs.add(buildLog(50 + i, Datetime.now().addDays(-10).addHours(-i), 'Pending'));
            recentLogs.add(buildLog(100 + i, Datetime.now().addDays(-2).addHours(-i), 'Synced'));
            recentLogs.add(buildLog(150 + i, Datetime.now().addDays(-2).addHours(-i), 'Pending'));
        }
        insert oldLogs;
        insert recentLogs;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Database.executeBatch(new AttendanceLogCleanupBatch(), 200);
            Test.stopTest();
        }

        System.assertEquals(0,
            [SELECT COUNT() FROM Attendance_Log__c WHERE Id IN :oldLogs],
            'every log older than 7 days should be deleted, Pending ones included');
        System.assertEquals(recentLogs.size(),
            [SELECT COUNT() FROM Attendance_Log__c WHERE Id IN :recentLogs],
            'logs within the last 7 days should be kept, whatever their status');
    }

    /**
     * @description Pins the retention boundary at 7 days: a log 6 days old
     *              survives, one 8 days old does not.
     */
    @IsTest
    static void retentionBoundaryIsFiveDays() {
        Attendance_Log__c inside  = buildLog(1, Datetime.now().addDays(-4), 'Pending');
        Attendance_Log__c outside = buildLog(2, Datetime.now().addDays(-6), 'Pending');
        insert new List<Attendance_Log__c>{ inside, outside };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Database.executeBatch(new AttendanceLogCleanupBatch(), 200);
            Test.stopTest();
        }

        System.assertEquals(1,
            [SELECT COUNT() FROM Attendance_Log__c WHERE Id = :inside.Id],
            'a 4-day-old log is inside the 5-day window and must survive');
        System.assertEquals(0,
            [SELECT COUNT() FROM Attendance_Log__c WHERE Id = :outside.Id],
            'a 6-day-old log is outside the window and must be purged');
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
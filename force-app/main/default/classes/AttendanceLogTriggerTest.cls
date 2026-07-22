@IsTest
private class AttendanceLogTriggerTest {

    // 25 May 2026, 14:27 IST -> stored as UTC (IST minus 5:30).
    private static DateTime expectedUtc() {
        return DateTime.newInstanceGmt(2026, 5, 25, 14, 27, 0).addMinutes(-330);
    }

    private static Attendance_Log__c importLog(String raw) {
        return new Attendance_Log__c(
            Roll_Number__c = 'R001',
            Device_ID__c = 'DEV1',
            Is_Import__c = true,
            Log_Date_Time_Raw__c = raw
        );
    }

    @IsTest
    static void parsesSlashFormat() {
        Attendance_Log__c rec = importLog('25/05/26 14:27');
        Test.startTest();
        insert rec;
        Test.stopTest();

        Attendance_Log__c after = [
            SELECT Log_Date_Time__c, Is_Import__c FROM Attendance_Log__c WHERE Id = :rec.Id];
        System.assertEquals(expectedUtc(), after.Log_Date_Time__c, 'Slash format should parse to IST wall-clock.');
        System.assertEquals(false, after.Is_Import__c, 'Is_Import__c is cleared after parsing.');
    }

    @IsTest
    static void parsesDashFormat() {
        Attendance_Log__c rec = importLog('25-05-26 14:27');
        Test.startTest();
        insert rec;
        Test.stopTest();

        Attendance_Log__c after = [
            SELECT Log_Date_Time__c, Is_Import__c FROM Attendance_Log__c WHERE Id = :rec.Id];
        System.assertEquals(expectedUtc(), after.Log_Date_Time__c,
            'Dash format should parse identically to the slash format.');
        System.assertEquals(false, after.Is_Import__c);
    }

    @IsTest
    static void dashFormatWithSeconds() {
        Attendance_Log__c rec = importLog('25-05-2026 14:27:45');
        Test.startTest();
        insert rec;
        Test.stopTest();

        Attendance_Log__c after = [SELECT Log_Date_Time__c FROM Attendance_Log__c WHERE Id = :rec.Id];
        System.assertEquals(
            DateTime.newInstanceGmt(2026, 5, 25, 14, 27, 45).addMinutes(-330),
            after.Log_Date_Time__c, 'Seconds and 4-digit year should also parse.');
    }

    @IsTest
    static void nonImportRecordIsUntouched() {
        DateTime preset = DateTime.newInstanceGmt(2026, 1, 1, 0, 0, 0);
        Attendance_Log__c rec = new Attendance_Log__c(
            Roll_Number__c = 'R002', Device_ID__c = 'DEV2',
            Is_Import__c = false, Log_Date_Time__c = preset,
            Log_Date_Time_Raw__c = 'this-should-be-ignored');
        Test.startTest();
        insert rec; // Is_Import__c false -> trigger skips parsing
        Test.stopTest();

        Attendance_Log__c after = [SELECT Log_Date_Time__c FROM Attendance_Log__c WHERE Id = :rec.Id];
        System.assertEquals(preset, after.Log_Date_Time__c, 'Non-import records are not reparsed.');
    }

    @IsTest
    static void badFormatAddsError() {
        Attendance_Log__c rec = importLog('not-a-real-date');
        Test.startTest();
        Database.SaveResult sr = Database.insert(rec, false);
        Test.stopTest();
        System.assertEquals(false, sr.isSuccess(), 'Unparseable raw value should be rejected.');
        System.assert(sr.getErrors()[0].getMessage().contains('Expected format'),
            'Error should mention the expected format.');
    }
}
@IsTest
private class BiometricAttendanceSchedulerTest {

    @IsTest
    static void daytimeExecute() {
        Test.setMock(WebServiceMock.class, new TempuriOrgLiveMock());
        Test.startTest();
        new BiometricAttendanceScheduler(false).execute(null);
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void finalSweepExecute() {
        Test.setMock(WebServiceMock.class, new TempuriOrgLiveMock());
        Test.startTest();
        new BiometricAttendanceScheduler(true).execute(null);
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void scheduleAbortAndCheck() {
        Test.startTest();
        BiometricAttendanceScheduler.scheduleAll();
        Integer scheduled = [
            SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Biometric_Sync_%'
        ];
        System.assertEquals(8, scheduled, 'Expected 7 daytime + 1 final job');
        BiometricAttendanceScheduler.checkSchedule();
        BiometricAttendanceScheduler.abortAll();
        Test.stopTest();
        System.assertEquals(
            0,
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Biometric_Sync_%']
        );
    }

    @IsTest
    static void resolveAnchorReturnsScheduledHour() {
        Datetime anchor = BiometricAttendanceScheduler.resolveAnchorTime();
        System.assertEquals(0, anchor.minute());
    }
}
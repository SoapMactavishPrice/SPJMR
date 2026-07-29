/**
 * Tests for DaySyncController — the "Sync" list-view button on Attendance_Log__c.
 *
 * Validation branches (null / future / too-old) need no callout. The success
 * path fires BiometricAttendanceBatch, whose start() calls the ESSL SOAP
 * service, so those tests inject dummy credentials via configOverride and a
 * WebServiceMock. finish() intentionally skips the chained marking batch under
 * Test.isRunningTest(); the marking logic itself is covered by
 * AttendanceBackfillBatchTest.
 */
@IsTest
private class DaySyncControllerTest {

    /** Minimal SOAP mock so BiometricAttendanceBatch.start() returns cleanly. */
    private class DaySyncSoapMock implements WebServiceMock {
        public void doInvoke(
            Object stub, Object request, Map<String, Object> response,
            String endpoint, String soapAction, String requestName,
            String responseNs, String responseName, String responseType
        ) {
            tempuriOrgLive.GetTransactionsLogResponse_element resp =
                new tempuriOrgLive.GetTransactionsLogResponse_element();
            resp.strDataList = 'R001\t2026-01-01 10:00:00\n';
            response.put('response_x', resp);
        }
    }

    private static void seedConfig() {
        BiometricAttendanceBatch.configOverride = new Biometric_API_Config__mdt(
            Api_User__c = 'api', Api_Password__c = 'test-pass');
    }

    @IsTest
    static void getters_returnIsoDateStrings() {
        Test.startTest();
        DaySyncController ctrl = new DaySyncController();
        String minStr = ctrl.getMinDateStr();
        String maxStr = ctrl.getMaxDateStr();
        Test.stopTest();

        System.assertEquals(10, minStr.length(), 'min should be a yyyy-MM-dd string');
        System.assertEquals(10, maxStr.length(), 'max should be a yyyy-MM-dd string');
        System.assert(maxStr > minStr, 'max (yesterday) should be after min (90 days ago)');
    }

    @IsTest
    static void submit_nullDate_rejected() {
        Test.startTest();
        DaySyncController ctrl = new DaySyncController();
        ctrl.selectedDate = null;
        ctrl.submit();
        Test.stopTest();

        System.assertEquals(false, ctrl.isSuccess, 'null date must be rejected');
        System.assert(ctrl.resultMessage.contains('select a date'),
            'should ask the user to select a date');
    }

    @IsTest
    static void submit_futureDate_rejected() {
        Test.startTest();
        DaySyncController ctrl = new DaySyncController();
        ctrl.selectedDate = Date.today().addDays(1);
        ctrl.submit();
        Test.stopTest();

        System.assertEquals(false, ctrl.isSuccess, 'future date must be rejected');
        System.assert(ctrl.resultMessage.contains('past date'),
            'should require a past date');
    }

    @IsTest
    static void submit_tooOldDate_rejected() {
        Test.startTest();
        DaySyncController ctrl = new DaySyncController();
        ctrl.selectedDate = Date.today().addDays(-200);
        ctrl.submit();
        Test.stopTest();

        System.assertEquals(false, ctrl.isSuccess, 'date older than 90 days must be rejected');
        System.assert(ctrl.resultMessage.contains('too far back'),
            'should say the date is too far back');
    }

    @IsTest
    static void submit_validPastDate_startsJob() {
        seedConfig();
        Test.setMock(WebServiceMock.class, new DaySyncSoapMock());

        Test.startTest();
        DaySyncController ctrl = new DaySyncController();
        ctrl.selectedDate = Date.today().addDays(-5);
        ctrl.submit();
        Test.stopTest();

        System.assertEquals(true, ctrl.isSuccess, ctrl.resultMessage);
        System.assert(ctrl.resultMessage.contains('Job Id'),
            'success message should include the job id');
    }
}
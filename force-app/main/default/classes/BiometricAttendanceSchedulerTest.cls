@IsTest
private class BiometricAttendanceSchedulerTest {

    public class EmptyMock implements WebServiceMock {
        public void doInvoke(
            Object stub, Object request, Map<String, Object> response,
            String endpoint, String soapAction, String requestName,
            String responseNs, String responseName, String responseType
        ) {
            tempuriOrgLive.GetTransactionsLogResponse_element resp =
                new tempuriOrgLive.GetTransactionsLogResponse_element();
            resp.strDataList = '';
            response.put('response_x', resp);
        }
    }

    @IsTest
    static void execute_daytimeMode_firesBatch() {
        Test.setMock(WebServiceMock.class, new EmptyMock());
        Test.startTest();
        new BiometricAttendanceScheduler().execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_finalSweepMode_firesBatch() {
        Test.setMock(WebServiceMock.class, new EmptyMock());
        Test.startTest();
        new BiometricAttendanceScheduler(true).execute(null);
        Test.stopTest();
    }

    @IsTest
    static void resolveAnchorTime_returnsValidDatetime() {
        Datetime anchor = BiometricAttendanceScheduler.resolveAnchorTime();
        System.assertNotEquals(null, anchor);
    }

    @IsTest
    static void scheduleAll_andAbortAll() {
        Test.startTest();
        BiometricAttendanceScheduler.scheduleAll();
        BiometricAttendanceScheduler.checkSchedule();
        BiometricAttendanceScheduler.abortAll();
        Test.stopTest();
    }

    @IsTest
    static void abortAll_whenNothingScheduled() {
        Test.startTest();
        BiometricAttendanceScheduler.abortAll();
        Test.stopTest();
    }

    @IsTest
    static void checkSchedule_whenNothingScheduled() {
        Test.startTest();
        BiometricAttendanceScheduler.checkSchedule();
        Test.stopTest();
    }
}
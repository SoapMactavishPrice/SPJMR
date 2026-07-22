/**
 * Tests for BiometricAttendanceBatch. Mocks the SOAP callout via WebServiceMock so
 * start() exercises parse + build paths without hitting the live ESSL device.
 * Credentials are injected via BiometricAttendanceBatch.configOverride so no
 * Biometric_API_Config__mdt org record is required during tests.
 */
@IsTest
private class BiometricAttendanceBatchTest {

    /** Injects dummy API credentials so start() proceeds past the config guard. */
    private static void seedConfig() {
        BiometricAttendanceBatch.configOverride = new Biometric_API_Config__mdt(
            Api_User__c     = 'api',
            Api_Password__c = 'test-pass'
        );
    }

    /** Mock that returns a tab-delimited payload covering: well-formed punches,
     *  malformed datetime (safeParseDateTime catch), and too-few-columns. */
    public class BiometricSoapMock implements WebServiceMock {
        public Boolean returnEmpty;
        public BiometricSoapMock(Boolean empty) { this.returnEmpty = empty; }

        public void doInvoke(
            Object stub, Object request, Map<String, Object> response,
            String endpoint, String soapAction, String requestName,
            String responseNs, String responseName, String responseType
        ) {
            tempuriOrgLive.GetTransactionsLogResponse_element resp =
                new tempuriOrgLive.GetTransactionsLogResponse_element();
            if (this.returnEmpty) {
                resp.strDataList = '';
            } else {
                resp.strDataList =
                    'R001\t2026-05-26 10:15:00\n' +
                    'R001\t2026-05-26 10:30:00\n' +
                    'R002\t2026-05-26 10:45:00\n' +
                    'R003\tnot-a-date\n' +
                    'R004OnlyOneColumn\n' +
                    '\n';
            }
            response.put('response_x', resp);
        }
    }

    @IsTest
    static void constructor_anchorTime() {
        BiometricAttendanceBatch b = new BiometricAttendanceBatch(Datetime.now());
        System.assertNotEquals(null, b);
    }

    @IsTest
    static void constructor_explicitWindow() {
        BiometricAttendanceBatch b = new BiometricAttendanceBatch(
            Datetime.now().addHours(-3), Datetime.now()
        );
        System.assertNotEquals(null, b);
    }

    @IsTest
    static void execute_emptyScope_returnsEarly() {
        BiometricAttendanceBatch b = new BiometricAttendanceBatch(Datetime.now());
        Test.startTest();
        b.execute(null, new List<SObject>());
        b.finish(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_insertsPopulatedScope() {
        BiometricAttendanceBatch b = new BiometricAttendanceBatch(Datetime.now());
        List<SObject> scope = new List<SObject>{
            new Attendance_Log__c(Roll_Number__c='R001', Log_Date_Time__c=Datetime.now(), Device_ID__c='D1', Status__c='Pending'),
            new Attendance_Log__c(Roll_Number__c='R002', Log_Date_Time__c=Datetime.now(), Device_ID__c='D1', Status__c='Pending')
        };
        Test.startTest();
        b.execute(null, scope);
        b.finish(null);
        Test.stopTest();

        System.assertEquals(2,
            [SELECT COUNT() FROM Attendance_Log__c WHERE Device_ID__c = 'D1'],
            'both records should be inserted');
    }

    @IsTest
    static void runBatch_withMock_populatesRecords() {
        seedConfig();
        Test.setMock(WebServiceMock.class, new BiometricSoapMock(false));
        Test.startTest();
        Database.executeBatch(new BiometricAttendanceBatch(Datetime.now()), 200);
        Test.stopTest();

        // Each active device yields exactly 3 valid punches (R001 x2, R002);
        // R003 (bad date), R004 (single column) and the blank line are skipped.
        // The total is therefore a positive multiple of 3, independent of how
        // many Biometric_Device__mdt records exist in the org.
        Integer cnt = [SELECT COUNT() FROM Attendance_Log__c];
        System.assert(cnt > 0, 'valid punches should be inserted');
        System.assertEquals(0, Math.mod(cnt, 3),
            '3 valid punches per device; malformed rows must be skipped');
    }

    @IsTest
    static void runBatch_withMock_emptyResponse() {
        seedConfig();
        Test.setMock(WebServiceMock.class, new BiometricSoapMock(true));
        Test.startTest();
        Database.executeBatch(new BiometricAttendanceBatch(Datetime.now()), 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Attendance_Log__c],
            'empty API response inserts nothing');
    }

    @IsTest
    static void runBatch_missingConfig_abortsGracefully() {
        // Blank credentials → start() aborts before any callout, inserts nothing.
        BiometricAttendanceBatch.configOverride = new Biometric_API_Config__mdt();
        Test.setMock(WebServiceMock.class, new BiometricSoapMock(false));
        Test.startTest();
        Database.executeBatch(new BiometricAttendanceBatch(Datetime.now()), 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Attendance_Log__c],
            'no records when credentials are not configured');
    }
}
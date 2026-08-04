@IsTest
private class BiometricAttendanceBatchTest {

    /**
     * The running user, for the per-method System.runAs wrapper.
     * @return a User reference to the current user
     */
    private static User self() {
        return new User(Id = UserInfo.getUserId());
    }

    /** Injects dummy credentials so the batch does not abort on missing config. */
    private static void seedConfig() {
        BiometricAttendanceBatch.configOverride = new Biometric_API_Config__mdt(
            Api_User__c     = 'api',
            Api_Password__c = 'test-pass'
        );
    }

    /** Canned eSSL response; `empty` returns no rows. */
    public class BiometricSoapMock implements WebServiceMock {
        public Boolean returnEmpty;

        /**
         * Builds the mock in either populated or empty mode.
         * @param empty true to return an empty payload
         */
        public BiometricSoapMock(Boolean empty) { this.returnEmpty = empty; }

        /**
         * Returns the canned payload instead of calling the real service.
         * @param stub         generated stub (unused)
         * @param request      request element (unused)
         * @param response     map the response element is written into
         * @param endpoint     service endpoint (unused)
         * @param soapAction   SOAP action (unused)
         * @param requestName  request element name (unused)
         * @param responseNs   response namespace (unused)
         * @param responseName response element name (unused)
         * @param responseType response type name (unused)
         */
        @SuppressWarnings('PMD.ExcessiveParameterList')
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

    /** Both constructors build a usable instance. */
    @IsTest
    static void constructorsBuildInstances() {
        System.runAs(self()) {
            Test.startTest();
            BiometricAttendanceBatch anchored =
                new BiometricAttendanceBatch(Datetime.now());
            BiometricAttendanceBatch windowed = new BiometricAttendanceBatch(
                Datetime.now().addHours(-3), Datetime.now());
            Test.stopTest();

            System.assertNotEquals(null, anchored, 'anchor ctor should build');
            System.assertNotEquals(null, windowed, 'explicit-window ctor should build');
        }
    }

    /** An empty or null scope must return early without touching the database. */
    @IsTest
    static void executeEmptyScopeReturnsEarly() {
        System.runAs(self()) {
            BiometricAttendanceBatch b = new BiometricAttendanceBatch(Datetime.now());

            Test.startTest();
            b.execute(null, new List<SObject>());
            b.execute(null, null);
            b.finish(null);
            Test.stopTest();

            System.assertEquals(0, [SELECT COUNT() FROM Attendance_Log__c],
                'an empty scope must insert nothing');
        }
    }

    /** A populated scope is inserted. */
    @IsTest
    static void executeInsertsPopulatedScope() {
        System.runAs(self()) {
            BiometricAttendanceBatch b = new BiometricAttendanceBatch(Datetime.now());
            List<SObject> scope = new List<SObject>{
                new Attendance_Log__c(Roll_Number__c = 'R001',
                    Log_Date_Time__c = Datetime.now(), Device_ID__c = 'D1',
                    Status__c = 'Pending'),
                new Attendance_Log__c(Roll_Number__c = 'R002',
                    Log_Date_Time__c = Datetime.now(), Device_ID__c = 'D1',
                    Status__c = 'Pending')
            };

            Test.startTest();
            b.execute(null, scope);
            b.finish(null);
            Test.stopTest();

            System.assertEquals(2,
                [SELECT COUNT() FROM Attendance_Log__c WHERE Device_ID__c = 'D1'],
                'both records should be inserted');
        }
    }

    /** Full run against the mock: valid punches stored, malformed rows skipped. */
    @IsTest
    static void runBatchWithMockPopulatesRecords() {
        System.runAs(self()) {
            seedConfig();
            Test.setMock(WebServiceMock.class, new BiometricSoapMock(false));

            Test.startTest();
            Database.executeBatch(new BiometricAttendanceBatch(Datetime.now()), 200);
            Test.stopTest();

            Integer cnt = [SELECT COUNT() FROM Attendance_Log__c];
            System.assert(cnt > 0, 'valid punches should be inserted');
            System.assertEquals(0, Math.mod(cnt, 3),
                '3 valid punches per device; malformed rows must be skipped');
        }
    }

    /** An empty API response inserts nothing. */
    @IsTest
    static void runBatchWithMockEmptyResponse() {
        System.runAs(self()) {
            seedConfig();
            Test.setMock(WebServiceMock.class, new BiometricSoapMock(true));

            Test.startTest();
            Database.executeBatch(new BiometricAttendanceBatch(Datetime.now()), 200);
            Test.stopTest();

            System.assertEquals(0, [SELECT COUNT() FROM Attendance_Log__c],
                'empty API response inserts nothing');
        }
    }

    /** Missing credentials abort the run instead of throwing. */
    @IsTest
    static void runBatchMissingConfigAbortsGracefully() {
        System.runAs(self()) {
            BiometricAttendanceBatch.configOverride = new Biometric_API_Config__mdt();
            Test.setMock(WebServiceMock.class, new BiometricSoapMock(false));

            Test.startTest();
            Database.executeBatch(new BiometricAttendanceBatch(Datetime.now()), 200);
            Test.stopTest();

            System.assertEquals(0, [SELECT COUNT() FROM Attendance_Log__c],
                'no records when credentials are not configured');
        }
    }

    /**
     * The mock returns R001@10:15 twice. Only ONE row may be inserted — proving
     * duplicates are collapsed WITHIN a single fetch on roll+timestamp.
     */
    @IsTest
    static void dedupCollapsesRepeatsInsideOneFetch() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(WebServiceMock.class, new DuplicateSoapMock());

            Test.startTest();
            Database.executeBatch(new BiometricAttendanceBatch(
                Datetime.newInstanceGmt(2026, 5, 26, 10, 0, 0),
                Datetime.newInstanceGmt(2026, 5, 26, 11, 0, 0)), 200);
            Test.stopTest();

            Integer rows = [
                SELECT COUNT() FROM Attendance_Log__c
                WHERE Roll_Number__c = 'DUP001'
            ];
            System.assertEquals(1, rows,
                'the same roll+timestamp reported twice must insert only once');
        }
    }

    /**
     * A punch that is ALREADY stored must not be inserted again — proving the
     * dedup guard also reads existing rows, which is what makes the overlapping
     * 2-hour windows and the wide 23:39 final sweep safe.
     */
    @IsTest
    static void dedupSkipsPunchAlreadyStored() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(WebServiceMock.class, new DuplicateSoapMock());

            // Pre-store the exact punch the mock will return.
            insert new Attendance_Log__c(
                Roll_Number__c   = 'DUP001',
                Log_Date_Time__c = Datetime.valueOf('2026-05-26 10:15:00'),
                Device_ID__c     = 'PRE-EXISTING',
                Status__c        = 'Pending');

            Test.startTest();
            Database.executeBatch(new BiometricAttendanceBatch(
                Datetime.newInstanceGmt(2026, 5, 26, 10, 0, 0),
                Datetime.newInstanceGmt(2026, 5, 26, 11, 0, 0)), 200);
            Test.stopTest();

            List<Attendance_Log__c> rows = [
                SELECT Device_ID__c FROM Attendance_Log__c
                WHERE Roll_Number__c = 'DUP001'
            ];
            System.assertEquals(1, rows.size(),
                'an already-stored punch must not be inserted a second time');
            System.assertEquals('PRE-EXISTING', rows[0].Device_ID__c,
                'the original row must survive untouched');
        }
    }

    /** The key is roll + GMT instant, so it never shifts with timezone. */
    @IsTest
    static void dedupKeyIsStableAndTimezoneSafe() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Datetime dt = Datetime.newInstanceGmt(2026, 5, 26, 10, 15, 0);

            Test.startTest();
            String a = BiometricAttendanceBatch.dedupKey('R001', dt);
            String b = BiometricAttendanceBatch.dedupKey('R001', dt);
            String c = BiometricAttendanceBatch.dedupKey('R002', dt);
            String nullDt = BiometricAttendanceBatch.dedupKey('R001', null);
            Test.stopTest();

            System.assertEquals(a, b, 'the same roll+instant must give the same key');
            System.assertNotEquals(a, c, 'different rolls must give different keys');
            System.assertEquals('R001|2026-05-26 10:15:00', a,
                'key should be roll|GMT timestamp: ' + a);
            System.assertEquals('R001|', nullDt, 'a null instant yields an empty half');
        }
    }

    /** Mock that reports the SAME punch twice, plus one unique punch. */
    public class DuplicateSoapMock implements WebServiceMock {
        /**
         * Returns the same punch twice plus one unique punch.
         * @param stub         generated stub (unused)
         * @param request      request element (unused)
         * @param response     map the response element is written into
         * @param endpoint     service endpoint (unused)
         * @param soapAction   SOAP action (unused)
         * @param requestName  request element name (unused)
         * @param responseNs   response namespace (unused)
         * @param responseName response element name (unused)
         * @param responseType response type name (unused)
         */
        @SuppressWarnings('PMD.ExcessiveParameterList')
        public void doInvoke(
            Object stub, Object request, Map<String, Object> response,
            String endpoint, String soapAction, String requestName,
            String responseNs, String responseName, String responseType
        ) {
            tempuriOrgLive.GetTransactionsLogResponse_element resp =
                new tempuriOrgLive.GetTransactionsLogResponse_element();
            resp.strDataList =
                'DUP001\t2026-05-26 10:15:00\n' +
                'DUP001\t2026-05-26 10:15:00\n' +
                'DUP002\t2026-05-26 10:20:00\n';
            response.put('response_x', resp);
        }
    }
}
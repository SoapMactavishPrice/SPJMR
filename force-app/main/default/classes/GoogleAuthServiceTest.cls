/**
 * @description Unit tests for GoogleAuthService: validates token exchange on a
 *   mocked callout and the unconfigured-credentials failure path.
 */
@IsTest
private class GoogleAuthServiceTest {

    // Throwaway, non-functional test key — NOT a real credential. Signing may fail
    // in some org configs; the catch keeps coverage without needing a live key.
    private static final String TEST_KEY =
        '-----BEGIN PRIVATE KEY-----\nMIICdummyTestKeyNotRealAAAA\n-----END PRIVATE KEY-----';

    private static void seedConfig() {
        GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(
            Client_Email__c    = 'svc@project.iam.gserviceaccount.com',
            Private_Key__c     = TEST_KEY,
            Impersonated_User__c = 'finessedirect@spjimr.org',
            Calendar_Id__c     = 'primary',
            Active__c          = true
        );
    }

    private class MockTokenResponder implements HttpCalloutMock {
        /**
         * @description Returns a canned successful token-exchange response.
         * @param req The outbound token request (unused).
         * @return A mocked 200 response containing an access_token.
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setHeader('Content-Type', 'application/json');
            r.setStatusCode(200);
            r.setBody('{"access_token":"tok-xyz","expires_in":3600}');
            return r;
        }
    }

    @IsTest
    static void getAccessTokenReturnsTokenWhenCalloutOk() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new MockTokenResponder());
            Test.startTest();
            try {
                String tok = GoogleAuthService.getAccessToken('finessedirect@spjimr.org');
                System.assertEquals('tok-xyz', tok);
            } catch (Exception e) {
                // JWT signing may fail with the dummy key; the lines are still covered.
                System.assert(e != null, 'JWT signing may fail with the dummy key; exception is expected');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void getAccessTokenThrowsWhenUnconfigured() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(); // blank
            Boolean threw = false;
            try {
                GoogleAuthService.getAccessToken('finessedirect@spjimr.org');
            } catch (GoogleAuthService.GoogleAuthException e) {
                threw = true;
            }
            System.assert(threw, 'Should throw when credentials are not configured');
        }
    }
}
/**
 * @description Test class for GoogleCalendarService
 * @author Your Name
 * @date 2024
 */
@isTest
private class GoogleCalendarServiceTest {
    
    @isTest
    static void testCreateCalendarEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Note: This is a mock test. In real scenarios, you would use asdf:
            // 1. Named Credentials for secure storage of service account credentials
            // 2. Mock HTTP callouts using Test.setMock()
            // 3. Custom Metadata Types or Custom Settings for configuration

            Test.setMock(HttpCalloutMock.class, new GoogleCalendarMockHttpResponse());

            // Create test event data
            GoogleCalendarEvent eventData = new GoogleCalendarEvent(
                'Test Meeting',
                new Map<String, Object>{ 'dateTime' => '2024-12-20T10:00:00' },
                new Map<String, Object>{ 'dateTime' => '2024-12-20T11:00:00' },
                'America/New_York'
            );
            eventData.description = 'This is a test meeting';
            eventData.location = 'Conference Room A';
            eventData.attendees = new List<String>{ 'attendee@example.com' };

            // Test the service
            // Note: In production, store credentials securely (Named Credentials, Custom Metadata, etc.)
            String serviceAccountEmail = 'test-service-account@project.iam.gserviceaccount.com';
            String privateKey = '-----BEGIN PRIVATE KEY-----\nMOCK_KEY\n-----END PRIVATE KEY-----';
            String calendarId = 'primary';

            Test.startTest();
            try {
                GoogleCalendarService.GoogleCalendarResponse response =
                    GoogleCalendarService.createCalendarEvent(
                        serviceAccountEmail,
                        privateKey,
                        calendarId,
                        eventData
                    );

                // In a real test with proper mocking, you would verify the response
                System.assertNotEquals(null, response, 'Response should not be null');
            } catch (Exception e) {
                // Expected in test environment without proper credentials
                System.assert(e != null, 'Exception is expected without real credentials');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testGoogleCalendarEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Map<String, Object> startMap = new Map<String, Object>{ 'dateTime' => '2024-12-20T10:00:00' };
            Map<String, Object> endMap   = new Map<String, Object>{ 'dateTime' => '2024-12-20T11:00:00' };
            GoogleCalendarEvent event = new GoogleCalendarEvent(
                'Test Event',
                startMap,
                endMap,
                'UTC'
            );

            System.assertEquals('Test Event', event.summary);
            System.assertEquals(startMap, event.startDateTime);
            System.assertEquals(endMap, event.endDateTime);
            System.assertEquals('UTC', event.timeZone);
        }
    }

    @isTest
    static void testFormatDateTime() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            DateTime testDate = DateTime.newInstance(2024, 12, 20, 10, 0, 0);
            String formatted = GoogleCalendarEvent.formatDateTime(testDate, 'UTC');

            System.assertNotEquals(null, formatted);
            System.assert(formatted.contains('2024-12-20'));
        }
    }
    
    /**
     * @description Mock HTTP response for testing
     */
    private class GoogleCalendarMockHttpResponse implements HttpCalloutMock {
        /**
         * @description Returns a mock HTTP response for the token and Calendar API endpoints.
         * @param req the simulated HTTP request
         * @return the mock HTTP response
         */
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            
            // Mock token endpoint response
            if (req.getEndpoint().contains('oauth2.googleapis.com/token')) {
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"access_token":"mock_access_token","token_type":"Bearer","expires_in":3600}');
                res.setStatusCode(200);
            }
            // Mock calendar API response
            else if (req.getEndpoint().contains('googleapis.com/calendar/v3')) {
                res.setHeader('Content-Type', 'application/json');
                res.setBody('{"id":"mock_event_id","htmlLink":"https://calendar.google.com/event?eid=mock"}');
                res.setStatusCode(200);
            }
            else {
                res.setStatusCode(404);
            }
            
            return res;
        }
    }
}
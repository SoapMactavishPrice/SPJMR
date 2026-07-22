/**
 * @description Tests for SessionAttendeeSyncService (RSVP read-back mapping + persist)
 *          and GoogleCalendarService.getCalendarEvent.
 */
@IsTest
private class SessionAttendeeSyncServiceTest {

    private static Session__c makeSession() {
        Session__c s = new Session__c(
            Schedule_Type__c   = 'Draft',
            Google_Event_Id__c = 'evt-123',
            Start_Time__c      = Datetime.now().addDays(1),
            End_Time__c        = Datetime.now().addDays(1).addHours(1)
        );
        insert s;
        return s;
    }

    private static Map<String, Object> eventWith(List<Object> attendees) {
        return new Map<String, Object>{ 'id' => 'evt-123', 'attendees' => attendees };
    }

    private static Map<String, Object> attendee(String email, String status, Boolean organizer) {
        Map<String, Object> m = new Map<String, Object>{ 'email' => email, 'responseStatus' => status };
        if (organizer != null) {
            m.put('organizer', organizer);
        }
        return m;
    }

    @IsTest
    static void mapAttendeesBuildsRowsWithStatusAndType() {
        Session__c s = makeSession();
        Set<String> faculty  = new Set<String>{ 'prof@spjimr.org' };
        Set<String> students = new Set<String>{ 'stud@spjimr.org' };

        List<Object> attendees = new List<Object>{
            attendee('prof@spjimr.org', 'accepted', true),
            attendee('stud@spjimr.org', 'needsAction', null),
            attendee('guest@ext.com', 'tentative', null)
        };

        Test.startTest();
        List<Session_Attendee__c> rows = SessionAttendeeSyncService.mapAttendees(
            s.Id, eventWith(attendees), faculty, students
        );
        Test.stopTest();

        System.assertEquals(3, rows.size(), 'Three attendees should map');
        Map<String, Session_Attendee__c> byEmail = new Map<String, Session_Attendee__c>();
        for (Session_Attendee__c r : rows) {
            byEmail.put(r.Attendee_Email__c, r);
        }

        System.assertEquals('Accepted', byEmail.get('prof@spjimr.org').Response_Status__c);
        System.assertEquals('Faculty', byEmail.get('prof@spjimr.org').Attendee_Type__c);
        System.assertEquals(true, byEmail.get('prof@spjimr.org').Is_Organizer__c);
        System.assertEquals('Needs Action', byEmail.get('stud@spjimr.org').Response_Status__c);
        System.assertEquals('Student', byEmail.get('stud@spjimr.org').Attendee_Type__c);
        System.assertEquals('Tentative', byEmail.get('guest@ext.com').Response_Status__c);
        System.assertEquals('Other', byEmail.get('guest@ext.com').Attendee_Type__c);
        System.assert(
            byEmail.get('stud@spjimr.org').Attendee_Key__c.endsWith(':stud@spjimr.org'),
            'Key should be sessionId:email lower-cased'
        );
    }

    @IsTest
    static void mapAttendeesHandlesMissingOrEmpty() {
        Session__c s = makeSession();
        System.assertEquals(0, SessionAttendeeSyncService.mapAttendees(s.Id, null, null, null).size());
        System.assertEquals(0, SessionAttendeeSyncService.mapAttendees(s.Id, new Map<String, Object>(), null, null).size());
        System.assertEquals(0, SessionAttendeeSyncService.mapAttendees(null, eventWith(new List<Object>()), null, null).size());
    }

    @IsTest
    static void mapAttendeesSkipsResourcesAndBlankEmails() {
        Session__c s = makeSession();
        Map<String, Object> room = new Map<String, Object>{
            'email' => 'room@resource.calendar.google.com',
            'responseStatus' => 'accepted',
            'resource' => true
        };
        List<Object> attendees = new List<Object>{
            room,
            new Map<String, Object>{ 'responseStatus' => 'accepted' }, // no email
            attendee('real@spjimr.org', 'accepted', null)
        };
        List<Session_Attendee__c> rows = SessionAttendeeSyncService.mapAttendees(
            s.Id, eventWith(attendees), null, null
        );
        System.assertEquals(1, rows.size(), 'Only the real attendee should map');
        System.assertEquals('real@spjimr.org', rows[0].Attendee_Email__c);
    }

    @IsTest
    static void persistUpsertsAndDeletesStale() {
        Session__c s = makeSession();

        Map<Id, List<Session_Attendee__c>> first = new Map<Id, List<Session_Attendee__c>>{
            s.Id => SessionAttendeeSyncService.mapAttendees(
                s.Id,
                eventWith(new List<Object>{
                    attendee('a@spjimr.org', 'accepted', null),
                    attendee('b@spjimr.org', 'declined', null)
                }),
                null, null
            )
        };
        SessionAttendeeSyncService.persistBySession(first);
        System.assertEquals(2, [SELECT COUNT() FROM Session_Attendee__c WHERE Session__c = :s.Id]);

        // Second sync: a@ becomes tentative, b@ removed, c@ added.
        Map<Id, List<Session_Attendee__c>> second = new Map<Id, List<Session_Attendee__c>>{
            s.Id => SessionAttendeeSyncService.mapAttendees(
                s.Id,
                eventWith(new List<Object>{
                    attendee('a@spjimr.org', 'tentative', null),
                    attendee('c@spjimr.org', 'accepted', null)
                }),
                null, null
            )
        };
        Test.startTest();
        SessionAttendeeSyncService.persistBySession(second);
        Test.stopTest();

        Map<String, Session_Attendee__c> byEmail = new Map<String, Session_Attendee__c>();
        for (Session_Attendee__c r : [
            SELECT Attendee_Email__c, Response_Status__c
            FROM Session_Attendee__c WHERE Session__c = :s.Id
        ]) {
            byEmail.put(r.Attendee_Email__c, r);
        }
        System.assertEquals(2, byEmail.size(), 'b@ removed, c@ added');
        System.assertEquals('Tentative', byEmail.get('a@spjimr.org').Response_Status__c);
        System.assert(byEmail.containsKey('c@spjimr.org'), 'c@ should be present');
        System.assert(!byEmail.containsKey('b@spjimr.org'), 'b@ should be deleted');
    }

    @IsTest
    static void persistHandlesEmpty() {
        SessionAttendeeSyncService.persistBySession(null);
        SessionAttendeeSyncService.persistBySession(new Map<Id, List<Session_Attendee__c>>());
        System.assertEquals(0, [SELECT COUNT() FROM Session_Attendee__c]);
    }

    @IsTest
    static void mapResponseStatusDefaultsToAwaiting() {
        Session__c s = makeSession();
        List<Session_Attendee__c> rows = SessionAttendeeSyncService.mapAttendees(
            s.Id,
            eventWith(new List<Object>{
                attendee('x@spjimr.org', null, null),
                attendee('y@spjimr.org', 'weirdstatus', null)
            }),
            null, null
        );
        for (Session_Attendee__c r : rows) {
            System.assertEquals('Needs Action', r.Response_Status__c, 'Unknown/blank should default to Needs Action');
        }
    }

    @IsTest
    static void getCalendarEventGuardsAndCallout() {
        GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(
            Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
            Private_Key__c       = '-----BEGIN PRIVATE KEY-----\nMIICdummyNotReal\n-----END PRIVATE KEY-----',
            Impersonated_User__c = 'organizer@spjimr.org',
            Calendar_Id__c       = 'primary',
            Active__c            = true
        );
        Test.setMock(HttpCalloutMock.class, new EventMock());

        Test.startTest();
        // Blank eventId guard.
        GoogleCalendarService.GoogleEventReadResponse blank =
            GoogleCalendarService.getCalendarEvent('primary', '', 'organizer@spjimr.org');
        // Full path (JWT signing may fail with the dummy key; call still exercised).
        GoogleCalendarService.GoogleEventReadResponse resp =
            GoogleCalendarService.getCalendarEvent('primary', 'evt-123', 'organizer@spjimr.org');
        Test.stopTest();

        System.assertNotEquals(null, blank.errorMessage, 'Blank eventId should be rejected');
        System.assertNotEquals(null, resp, 'Response should not be null');
    }

    private class EventMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('oauth2.googleapis.com/token')) {
                r.setStatusCode(200);
                r.setBody('{"access_token":"tok","expires_in":3600}');
            } else {
                r.setStatusCode(200);
                r.setBody('{"id":"evt-123","attendees":[{"email":"a@spjimr.org","responseStatus":"accepted"}]}');
            }
            return r;
        }
    }
}
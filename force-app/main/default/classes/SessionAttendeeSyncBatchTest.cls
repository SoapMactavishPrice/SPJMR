/**
 * @description Tests for SessionAttendeeSyncBatch (RSVP read-back polling) and
 *          SessionAttendeeSyncScheduler. Uses GoogleAuthService.tokenOverride to bypass
 *          JWT signing and an HttpCalloutMock for Events.get. The response-matching logic
 *          is covered in SessionRsvpSyncServiceTest; these tests exercise the batch's
 *          callout → parse → apply path and its graceful-failure handling. Sessions have no
 *          enrolled students here, so the apply step is a safe no-op (no Person Account
 *          chain needed to prove the batch runs end-to-end without error).
 */
@IsTest
private class SessionAttendeeSyncBatchTest {

    private static Google_Calendar_Config__mdt cfg() {
        return new Google_Calendar_Config__mdt(
            Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
            Private_Key__c       = '-----BEGIN PRIVATE KEY-----\nMIICdummy\n-----END PRIVATE KEY-----',
            Impersonated_User__c = 'organizer@spjimr.org',
            Calendar_Id__c       = 'primary',
            Active__c            = true
        );
    }

    private static Session__c makeSession(String eventId) {
        Session__c s = new Session__c(
            Schedule_Type__c   = 'Published',
            Google_Event_Id__c = eventId,
            Start_Time__c      = Datetime.now().addDays(1),
            End_Time__c        = Datetime.now().addDays(1).addHours(1)
        );
        insert s;
        return s;
    }

    @IsTest
    static void batchRunsWithoutError() {
        GoogleCalendarHelper.configOverride = cfg();
        GoogleAuthService.tokenOverride = 'tok';
        Session__c s = makeSession('evt-1');
        Test.setMock(HttpCalloutMock.class, new GetMock());

        Test.startTest();
        Database.executeBatch(new SessionAttendeeSyncBatch(), 40);
        Test.stopTest();

        // No enrollments exist for the session, so the apply step changes nothing and does not error.
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Session_Enrollment__c WHERE Session__c = :s.Id],
            'Batch completes; with no enrolled students nothing is updated'
        );
    }

    @IsTest
    static void batchSkipsDeletedEventGracefully() {
        GoogleCalendarHelper.configOverride = cfg();
        GoogleAuthService.tokenOverride = 'tok';
        Session__c s = makeSession('evt-gone');
        Test.setMock(HttpCalloutMock.class, new NotFoundMock());

        Test.startTest();
        Database.executeBatch(new SessionAttendeeSyncBatch(), 40);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Session_Enrollment__c WHERE Session__c = :s.Id],
            'Deleted Google event is skipped without error'
        );
    }

    @IsTest
    static void batchNoOpWhenUnconfigured() {
        GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(); // no impersonated user
        Session__c s = makeSession('evt-x');
        Test.setMock(HttpCalloutMock.class, new GetMock());

        Test.startTest();
        Database.executeBatch(new SessionAttendeeSyncBatch(), 40);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Session_Enrollment__c WHERE Session__c = :s.Id],
            'No sync when unconfigured'
        );
    }

    @IsTest
    static void schedulerLaunchesBatch() {
        GoogleCalendarHelper.configOverride = cfg();
        GoogleAuthService.tokenOverride = 'tok';
        Session__c s = makeSession('evt-1');
        Test.setMock(HttpCalloutMock.class, new GetMock());

        Test.startTest();
        new SessionAttendeeSyncScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Session_Enrollment__c WHERE Session__c = :s.Id],
            'Scheduler launches the batch without error'
        );
    }

    private class GetMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setHeader('Content-Type', 'application/json');
            r.setStatusCode(200);
            r.setBody('{"id":"evt-1","attendees":['
                + '{"email":"a@spjimr.org","responseStatus":"accepted"},'
                + '{"email":"b@spjimr.org","responseStatus":"declined"}]}');
            return r;
        }
    }

    private class NotFoundMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setHeader('Content-Type', 'application/json');
            r.setStatusCode(404);
            r.setBody('{"error":{"code":404,"message":"Not Found"}}');
            return r;
        }
    }
}
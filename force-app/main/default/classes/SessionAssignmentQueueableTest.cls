@IsTest
private class SessionAssignmentQueueableTest {

    private static String uniq() {
        return String.valueOf(Crypto.getRandomInteger()).right(6).replace('-', '0');
    }

    private static List<Id> addFutureSessions(Id divisionId, Integer count, String scheduleType) {
        List<Session__c> sessions = new List<Session__c>();
        for (Integer i = 0; i < count; i++) {
            sessions.add(new Session__c(
                Name = 'SAQ-' + uniq() + '-' + i,
                Session_Date__c = Date.today().addDays(2 + i),
                Start_Time__c = Datetime.now().addDays(2 + i),
                End_Time__c = Datetime.now().addDays(2 + i).addHours(1),
                Schedule_Type__c = scheduleType
            ));
        }
        insert sessions;
        List<Session_Division__c> links = new List<Session_Division__c>();
        for (Session__c s : sessions) {
            links.add(new Session_Division__c(Session__c = s.Id, Division__c = divisionId));
        }
        insert links;
        List<Id> ids = new List<Id>();
        for (Session__c s : sessions) ids.add(s.Id);
        return ids;
    }

    private static void resetTestFlags() {
        SessionAssignmentQueueable.lastSuppressValueDuringInsert = null;
        SessionAssignmentQueueable.calendarPushInvoked = false;
        SessionAssignmentQueueable.lastCalendarSessionIds = null;
        SessionAssignmentQueueable.DML_CHUNK_SIZE = 7000;
        SessionCalendarInviteHandler.suppressInvites = false;
    }

    private static Integer countSe(Id ateId, List<Id> sessionIds) {
        return [
            SELECT COUNT()
            FROM Session_Enrollment__c
            WHERE Academic_Term_Enrollment__c = :ateId
              AND Session__c IN :sessionIds
        ];
    }

    private static void runUntilAssigned(Id deId, Id ateId, List<Id> sessionIds) {
        Integer safety = 0;
        while (safety < 10) {
            new SessionAssignmentQueueable(new Set<Id>{ deId }).execute(null);
            if (countSe(ateId, sessionIds) >= sessionIds.size()) {
                break;
            }
            safety++;
        }
    }

    @IsTest
    static void assignsStudentToFutureSessions_singleChunk() {
        resetTestFlags();
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('saq1');
        System.assertNotEquals(null, ctx.divisionEnrollmentId);
        delete [SELECT Id FROM Session_Enrollment__c WHERE Academic_Term_Enrollment__c = :ctx.atEnrollmentId];

        List<Id> sessionIds = addFutureSessions(ctx.divisionId, 3, 'Draft');

        Test.startTest();
        new SessionAssignmentQueueable(new Set<Id>{ ctx.divisionEnrollmentId }).execute(null);
        Test.stopTest();

        System.assertEquals(3, countSe(ctx.atEnrollmentId, sessionIds));
        System.assertEquals(true, SessionAssignmentQueueable.lastSuppressValueDuringInsert);
        System.assertEquals(false, SessionCalendarInviteHandler.suppressInvites);
        System.assertEquals(true, SessionAssignmentQueueable.calendarPushInvoked);
    }

    @IsTest
    static void chunking_suppressOnEachChunk_calendarOnlyOnLast() {
        resetTestFlags();
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('saq2');
        System.assertNotEquals(null, ctx.divisionEnrollmentId);
        delete [SELECT Id FROM Session_Enrollment__c WHERE Academic_Term_Enrollment__c = :ctx.atEnrollmentId];

        List<Id> sessionIds = addFutureSessions(ctx.divisionId, 5, 'Draft');
        SessionAssignmentQueueable.DML_CHUNK_SIZE = 2;

        Test.startTest();
        SessionAssignmentQueueable.calendarPushInvoked = false;
        new SessionAssignmentQueueable(new Set<Id>{ ctx.divisionEnrollmentId }).execute(null);
        System.assertEquals(2, countSe(ctx.atEnrollmentId, sessionIds), 'First chunk size 2');
        System.assertEquals(true, SessionAssignmentQueueable.lastSuppressValueDuringInsert);
        System.assertEquals(false, SessionAssignmentQueueable.calendarPushInvoked,
            'Calendar push must not run while more chunks remain');

        runUntilAssigned(ctx.divisionEnrollmentId, ctx.atEnrollmentId, sessionIds);
        Test.stopTest();

        System.assertEquals(5, countSe(ctx.atEnrollmentId, sessionIds));
        System.assertEquals(true, SessionAssignmentQueueable.calendarPushInvoked,
            'Calendar push runs on the last chunk');
        System.assertEquals(false, SessionCalendarInviteHandler.suppressInvites,
            'suppressInvites must be restored after execute');
    }

    @IsTest
    static void idempotent_secondRunCreatesNoDuplicates() {
        resetTestFlags();
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('saq3');
        delete [SELECT Id FROM Session_Enrollment__c WHERE Academic_Term_Enrollment__c = :ctx.atEnrollmentId];
        List<Id> sessionIds = addFutureSessions(ctx.divisionId, 3, 'Draft');

        Test.startTest();
        new SessionAssignmentQueueable(new Set<Id>{ ctx.divisionEnrollmentId }).execute(null);
        Integer afterFirst = countSe(ctx.atEnrollmentId, sessionIds);
        new SessionAssignmentQueueable(new Set<Id>{ ctx.divisionEnrollmentId }).execute(null);
        Integer afterSecond = countSe(ctx.atEnrollmentId, sessionIds);
        Test.stopTest();

        System.assertEquals(3, afterFirst);
        System.assertEquals(3, afterSecond, 'Second run must not duplicate Session Enrollments');
    }

    @IsTest
    static void cancelledSessions_areSkipped() {
        resetTestFlags();
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('saq4');
        delete [SELECT Id FROM Session_Enrollment__c WHERE Academic_Term_Enrollment__c = :ctx.atEnrollmentId];

        List<Id> liveIds = addFutureSessions(ctx.divisionId, 2, 'Draft');
        List<Id> cancelledIds = addFutureSessions(ctx.divisionId, 2, 'Cancelled');

        Test.startTest();
        new SessionAssignmentQueueable(new Set<Id>{ ctx.divisionEnrollmentId }).execute(null);
        Test.stopTest();

        System.assertEquals(2, countSe(ctx.atEnrollmentId, liveIds));
        System.assertEquals(0, countSe(ctx.atEnrollmentId, cancelledIds));
    }

    @IsTest
    static void emptyEnrollmentIds_noOp() {
        resetTestFlags();
        Test.startTest();
        new SessionAssignmentQueueable(new Set<Id>()).execute(null);
        new SessionAssignmentQueueable(null).execute(null);
        Test.stopTest();
        System.assertEquals(false, SessionAssignmentQueueable.calendarPushInvoked);
    }

    @IsTest
    static void sliceAssignments_respectsChunkSize() {
        List<Session_Enrollment__c> source = new List<Session_Enrollment__c>{
            new Session_Enrollment__c(),
            new Session_Enrollment__c(),
            new Session_Enrollment__c()
        };
        List<Session_Enrollment__c> sliced = SessionAssignmentQueueable.sliceAssignments(source, 2);
        System.assertEquals(2, sliced.size());
    }

    @IsTest
    static void triggerPath_enqueuesAssignment_forNewDivisionEnrollment() {
        resetTestFlags();
        SpjimrPortalTestDataFactory.Ctx ctx = SpjimrPortalTestDataFactory.buildAll('saq5');
        List<Id> sessionIds = addFutureSessions(ctx.divisionId, 2, 'Draft');

        String tag2 = 'trig' + uniq();
        Account learner2 = new Account(
            RecordTypeId = ctx.learner.RecordTypeId,
            FirstName = 'TrigF' + tag2,
            LastName = 'TrigL' + tag2,
            PersonEmail = ('trig' + tag2 + '@example.com').toLowerCase(),
            PersonMobilePhone = '98' + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(8)
        );
        insert learner2;
        Id ate2 = SpjimrPortalTestDataFactory.insertAcademicTermEnrollment(learner2.Id, ctx.academicTermId);

        Test.startTest();
        Id de2 = SpjimrPortalTestDataFactory.insertDivisionEnrollment(ctx.divisionId, ate2);
        Test.stopTest();

        System.assertNotEquals(null, de2);
        Integer seForNew = [
            SELECT COUNT()
            FROM Session_Enrollment__c
            WHERE Academic_Term_Enrollment__c = :ate2
              AND Session__c IN :sessionIds
        ];
        System.assertEquals(2, seForNew,
            'Trigger-enqueued assignment should enroll new DE onto existing future sessions');
    }
}
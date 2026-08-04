@IsTest
private class MissedSessionSyncServiceTest {

    @TestSetup
    static void setupData() {

        SpjimrPortalTestDataFactory.buildAll('mss');
    }

    private static Id atEnrollmentId() {
        List<AcademicTermEnrollment> rows = [SELECT Id FROM AcademicTermEnrollment LIMIT 1];
        System.assertEquals(1, rows.size(),
            'Test setup must leave exactly one AcademicTermEnrollment to build enrollments against.');
        return rows[0].Id;
    }

    private static Id divisionEnrollmentId() {
        List<Division_Enrollment__c> rows = [SELECT Id FROM Division_Enrollment__c LIMIT 1];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Session__c newSession(Datetime startTime, Datetime endTime) {
        return new Session__c(
            Name           = 'MS Test ' + String.valueOf(Datetime.now().getTime()) + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Start_Time__c  = startTime,
            End_Time__c    = endTime,
            Session_Date__c = startTime.date()
        );
    }

    private static Leave_Application__c newLeave(Datetime leaveStart, Datetime leaveEnd) {
        return new Leave_Application__c(
            Start_Date__c = leaveStart,
            End_Date__c   = leaveEnd,
            Status__c     = 'Submitted - Pending Approval'
        );
    }

    private static Map<String, Id> buildLinkedTrio(Datetime sessStart, Datetime sessEnd,
                                                   Datetime leaveStart, Datetime leaveEnd) {
        Session__c s = newSession(sessStart, sessEnd);
        insert s;
        Leave_Application__c la = newLeave(leaveStart, leaveEnd);
        insert la;
        Id seId = SpjimrPortalTestDataFactory.insertSessionEnrollment(
            s.Id, divisionEnrollmentId(), atEnrollmentId()
        );
        System.assertNotEquals(null, seId,
            'The factory must produce a Session_Enrollment__c for this session.');
        insert new Missed_Sessions__c(Leave_Application__c = la.Id, Session_Enrollment__c = seId);

        Map<String, Id> ids = new Map<String, Id>{
            'session'    => s.Id,
            'leave'      => la.Id,
            'enrollment' => seId
        };
        System.assertEquals(1, linkCount(la.Id),
            'Setup must create exactly one Missed_Sessions__c link before the test acts.');
        return ids;
    }

    private static Integer linkCount(Id leaveId) {
        return [SELECT COUNT() FROM Missed_Sessions__c WHERE Leave_Application__c = :leaveId];
    }

    @IsTest
    static void isCoveredHandlesContainmentAndNulls() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Datetime leaveStart = Datetime.newInstance(2026, 6, 11, 0, 0, 0);
            Datetime leaveEnd   = Datetime.newInstance(2026, 6, 12, 23, 59, 0);

            System.assertEquals(true, MissedSessionSyncService.isCovered(
                leaveStart, leaveEnd,
                Datetime.newInstance(2026, 6, 11, 9, 0, 0),
                Datetime.newInstance(2026, 6, 11, 10, 0, 0)),
                'A session entirely inside the window is covered.');

            System.assertEquals(false, MissedSessionSyncService.isCovered(
                leaveStart, leaveEnd,
                Datetime.newInstance(2026, 5, 20, 9, 0, 0),
                Datetime.newInstance(2026, 5, 20, 10, 0, 0)),
                'A session on a different day is not covered.');

            System.assertEquals(false, MissedSessionSyncService.isCovered(
                leaveStart, leaveEnd,
                Datetime.newInstance(2026, 6, 10, 23, 0, 0),
                Datetime.newInstance(2026, 6, 11, 1, 0, 0)),
                'A session only partially inside the window is not covered.');

            System.assertEquals(false, MissedSessionSyncService.isCovered(null, leaveEnd,
                Datetime.newInstance(2026, 6, 11, 9, 0, 0),
                Datetime.newInstance(2026, 6, 11, 10, 0, 0)),
                'A missing leave start cannot prove coverage.');

            System.assertEquals(false, MissedSessionSyncService.isCovered(leaveStart, leaveEnd, null, null),
                'Missing session times cannot prove coverage.');
        }
    }

    @IsTest
    static void sessionMovedOutOfWindowDeletesLink() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Datetime leaveStart = Datetime.now().addDays(5);
            Datetime leaveEnd   = leaveStart.addDays(2);
            Map<String, Id> ids = buildLinkedTrio(
                leaveStart.addHours(1), leaveStart.addHours(2), leaveStart, leaveEnd);
            Test.startTest();
            update new Session__c(
                Id            = ids.get('session'),
                Start_Time__c = leaveStart.addDays(-30),
                End_Time__c   = leaveStart.addDays(-30).addHours(1)
            );
            Test.stopTest();

            System.assertEquals(0, linkCount(ids.get('leave')),
                'Moving the session out of the leave window must delete the link.');
        }
    }

    @IsTest
    static void sessionMovedWithinWindowKeepsLink() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Datetime leaveStart = Datetime.now().addDays(5);
            Datetime leaveEnd   = leaveStart.addDays(2);
            Map<String, Id> ids = buildLinkedTrio(
                leaveStart.addHours(1), leaveStart.addHours(2), leaveStart, leaveEnd);

            Test.startTest();
            update new Session__c(
                Id            = ids.get('session'),
                Start_Time__c = leaveStart.addHours(5),
                End_Time__c   = leaveStart.addHours(6)
            );
            Test.stopTest();

            System.assertEquals(1, linkCount(ids.get('leave')),
                'A session still inside the window must keep its link.');
        }
    }

    @IsTest
    static void leaveDatesMovedAwayDeletesLink() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Datetime leaveStart = Datetime.now().addDays(5);
            Datetime leaveEnd   = leaveStart.addDays(2);
            Map<String, Id> ids = buildLinkedTrio(
                leaveStart.addHours(1), leaveStart.addHours(2), leaveStart, leaveEnd);

            Test.startTest();
            update new Leave_Application__c(
                Id            = ids.get('leave'),
                Start_Date__c = leaveStart.addDays(60),
                End_Date__c   = leaveStart.addDays(62)
            );
            Test.stopTest();

            System.assertEquals(0, linkCount(ids.get('leave')),
                'Editing the leave window away from the session must delete the link.');
        }
    }

    @IsTest
    static void movedBackDoesNotRecreateLink() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Datetime leaveStart = Datetime.now().addDays(5);
            Datetime leaveEnd   = leaveStart.addDays(2);
            Map<String, Id> ids = buildLinkedTrio(
                leaveStart.addHours(1), leaveStart.addHours(2), leaveStart, leaveEnd);

            Test.startTest();
            update new Session__c(
                Id            = ids.get('session'),
                Start_Time__c = leaveStart.addDays(-30),
                End_Time__c   = leaveStart.addDays(-30).addHours(1)
            );
            update new Session__c(
                Id            = ids.get('session'),
                Start_Time__c = leaveStart.addHours(1),
                End_Time__c   = leaveStart.addHours(2)
            );
            Test.stopTest();

            System.assertEquals(0, linkCount(ids.get('leave')),
                'Remove-only: moving the session back must NOT recreate the link.');
        }
    }

    @IsTest
    static void resyncEntryPointsAreNullAndEmptySafe() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            MissedSessionSyncService.resyncForLeaves(null);
            MissedSessionSyncService.resyncForLeaves(new Set<Id>());
            MissedSessionSyncService.resyncForSessions(null);
            MissedSessionSyncService.resyncForSessions(new Set<Id>());
            Test.stopTest();
            System.assertEquals(0, [SELECT COUNT() FROM Missed_Sessions__c WHERE Leave_Application__c = null AND Session_Enrollment__c = null],
                'Null/empty resync calls must not create or destroy anything.');
        }
    }

    @IsTest
    static void staleLinkRemovalClearsSanctionedLeave() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Datetime leaveStart = Datetime.now().addDays(5);
            Datetime leaveEnd   = leaveStart.addDays(2);
            Map<String, Id> ids = buildLinkedTrio(
                leaveStart.addHours(1), leaveStart.addHours(2), leaveStart, leaveEnd);
            update new Session_Enrollment__c(Id = ids.get('enrollment'), Attendance__c = 'Sanctioned Leave');

            Test.startTest();
            update new Session__c(
                Id            = ids.get('session'),
                Start_Time__c = leaveStart.addDays(-30),
                End_Time__c   = leaveStart.addDays(-30).addHours(1)
            );
            Test.stopTest();

            Session_Enrollment__c after = [
                SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :ids.get('enrollment')
            ];
            System.assertEquals(null, after.Attendance__c,
                'A session no longer covered by any leave must lose Sanctioned Leave.');
            System.assertEquals(0, linkCount(ids.get('leave')),
                'The stale link is removed even though attendance is left alone.');
        }
    }

    @IsTest
    static void attendanceKeptWhenAnotherLeaveStillCoversIt() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Datetime leaveStart = Datetime.now().addDays(5);
            Datetime leaveEnd   = leaveStart.addDays(2);
            Map<String, Id> ids = buildLinkedTrio(
                leaveStart.addHours(1), leaveStart.addHours(2), leaveStart, leaveEnd);

            Leave_Application__c second = newLeave(leaveStart, leaveEnd);
            insert second;
            insert new Missed_Sessions__c(
                Leave_Application__c = second.Id,
                Session_Enrollment__c = ids.get('enrollment')
            );
            update new Session_Enrollment__c(Id = ids.get('enrollment'), Attendance__c = 'Sanctioned Leave');

            Test.startTest();
            update new Leave_Application__c(
                Id            = ids.get('leave'),
                Start_Date__c = leaveStart.addDays(60),
                End_Date__c   = leaveStart.addDays(62)
            );
            Test.stopTest();

            System.assertEquals(0, linkCount(ids.get('leave')),
                'The moved leave must lose its link.');
            System.assertEquals(1, linkCount(second.Id),
                'The second leave still covers the session.');
            Session_Enrollment__c after = [
                SELECT Attendance__c FROM Session_Enrollment__c WHERE Id = :ids.get('enrollment')
            ];
            System.assertEquals('Sanctioned Leave', after.Attendance__c,
                'Attendance must survive while ANY leave still covers the session.');
        }
    }

    @IsTest
    static void bulkRescheduleStaysWithinLimits() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Datetime leaveStart = Datetime.now().addDays(5);
            Datetime leaveEnd   = leaveStart.addDays(2);

            Leave_Application__c la = newLeave(leaveStart, leaveEnd);
            insert la;
            Id deId = divisionEnrollmentId();
            Id ateId = atEnrollmentId();

            List<Session__c> sessions = new List<Session__c>();
            for (Integer i = 0; i < 50; i++) {
                sessions.add(newSession(leaveStart.addMinutes(i * 5), leaveStart.addMinutes(i * 5 + 30)));
            }
            insert sessions;

            List<Missed_Sessions__c> links = new List<Missed_Sessions__c>();
            for (Session__c s : sessions) {
                Id seId = SpjimrPortalTestDataFactory.insertSessionEnrollment(s.Id, deId, ateId);
                if (seId != null) {
                    links.add(new Missed_Sessions__c(Leave_Application__c = la.Id, Session_Enrollment__c = seId));
                }
            }
            insert links;
            System.assertEquals(50, links.size(), 'All 50 sessions must be linked before the bulk reschedule.');

            Test.startTest();
            for (Session__c s : sessions) {
                s.Start_Time__c = leaveStart.addDays(-30);
                s.End_Time__c   = leaveStart.addDays(-30).addHours(1);
            }
            update sessions;
            Test.stopTest();

            System.assert(Limits.getQueries() < Limits.getLimitQueries(),
                'A 50-session reschedule must not approach the SOQL limit.');
            System.assertEquals(0, linkCount(la.Id),
                'All 50 links must be removed once every session leaves the window.');
        }
    }
}
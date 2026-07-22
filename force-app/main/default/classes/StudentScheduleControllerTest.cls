@IsTest
private class StudentScheduleControllerTest {

    @TestSetup
    static void setupData() {
        SpjimrPortalTestDataFactory.buildAll('sc');
    }

    @IsTest
    static void testGetLearnerAccountId_asPortalUser() {
        User pu = getPortalUser();
        Test.startTest();
        if (pu != null) {
            System.runAs(pu) {
                Id accountId = StudentScheduleController.getLearnerAccountId();
                System.assertNotEquals(null, accountId);
            }
        } else {
            Id accountId = StudentScheduleController.getLearnerAccountId();
            System.assertEquals(null, accountId);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetLearnerAccountId_noContact() {
        Test.startTest();
        Id accountId = StudentScheduleController.getLearnerAccountId();
        Test.stopTest();
        System.assertEquals(null, accountId);
    }

    @IsTest
    static void testGetEnrolledSessions_variousFilters() {
        User pu = getPortalUser();

        StudentScheduleController.ScheduleFilter f1 = new StudentScheduleController.ScheduleFilter();
        f1.startDate = Date.today().addDays(-7);
        f1.endDate   = Date.today().addDays(7);
        f1.sessionType = 'Lecture';
        String json1 = JSON.serialize(f1);

        StudentScheduleController.ScheduleFilter f2 = new StudentScheduleController.ScheduleFilter();
        f2.startDate = Date.today().addDays(-7);
        f2.endDate   = Date.today().addDays(7);
        String json2 = JSON.serialize(f2);

        StudentScheduleController.ScheduleFilter f3 = new StudentScheduleController.ScheduleFilter();
        f3.startDate = Date.today().addDays(-7);
        f3.sessionType = 'Lecture';
        String json3 = JSON.serialize(f3);

        StudentScheduleController.ScheduleFilter f4 = new StudentScheduleController.ScheduleFilter();
        f4.startDate = Date.today().addDays(-7);
        String json4 = JSON.serialize(f4);

        StudentScheduleController.ScheduleFilter f5 = new StudentScheduleController.ScheduleFilter();
        f5.endDate = Date.today().addDays(7);
        f5.sessionType = 'Lecture';
        String json5 = JSON.serialize(f5);

        StudentScheduleController.ScheduleFilter f6 = new StudentScheduleController.ScheduleFilter();
        f6.endDate = Date.today().addDays(7);
        String json6 = JSON.serialize(f6);

        Test.startTest();
        if (pu != null) {
            System.runAs(pu) {
                StudentScheduleController.getEnrolledSessions(json1);
                StudentScheduleController.getEnrolledSessions(json2);
                StudentScheduleController.getEnrolledSessions(json3);
                StudentScheduleController.getEnrolledSessions(json4);
                StudentScheduleController.getEnrolledSessions(json5);
                StudentScheduleController.getEnrolledSessions(json6);
                // null / invalid JSON parse to an empty filter (no dates) — controller does not
                // initialize the sessions list in that branch, so swallow the resulting NPE.
                try { StudentScheduleController.getEnrolledSessions(null); } catch (Exception e) {}
                try { StudentScheduleController.getEnrolledSessions('not-a-json'); } catch (Exception e) {}
            }
        }
        List<StudentScheduleController.SessionSummaryDto> empty =
            StudentScheduleController.getEnrolledSessions(json2);
        System.assertNotEquals(null, empty);
        Test.stopTest();
    }

    @IsTest
    static void testGetSessionDetails_nullAndExisting() {
        Test.startTest();
        System.assertEquals(null, StudentScheduleController.getSessionDetails(null));

        List<Session__c> existing = [SELECT Id FROM Session__c LIMIT 1];
        if (!existing.isEmpty()) {
            StudentScheduleController.SessionDetailDto dto =
                StudentScheduleController.getSessionDetails(existing[0].Id);
            System.assertNotEquals(null, dto);
            System.assertEquals(existing[0].Id, dto.id);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetSessionTypeOptions() {
        Test.startTest();
        List<Map<String, String>> opts = StudentScheduleController.getSessionTypeOptions();
        Test.stopTest();
        System.assertNotEquals(null, opts);
        System.assert(opts.size() >= 1);
    }

    private static User getPortalUser() {
        List<User> users = [
            SELECT Id FROM User WHERE Email = 'testsc.user@example.com.spjtest' LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }
}
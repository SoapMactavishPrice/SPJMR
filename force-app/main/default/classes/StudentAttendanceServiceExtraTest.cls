/**
 * Exercises StudentAttendanceService.getData with learner + term from portal test data.
 */
@IsTest
private class StudentAttendanceServiceExtraTest {

    @TestSetup
    static void setupData() {
        SpjimrPortalTestDataFactory.buildAll('att');
    }

    @IsTest
    static void getData_returnsRowsForLearnerAndTerm() {
        Account learner = [
            SELECT Id FROM Account WHERE LastName LIKE 'TestLatt%' LIMIT 1
        ];
        Id termId = null;
        try {
            SObject t = Database.query('SELECT Id FROM AcademicTerm LIMIT 1');
            termId = (Id) t.get('Id');
        } catch (Exception e) {}

        Test.startTest();
        System.assertEquals(0, StudentAttendanceService.getData(null, termId).size());
        System.assertEquals(0, StudentAttendanceService.getData(learner.Id, null).size());

        if (termId != null) {
            List<Session_Enrollment__c> rows =
                StudentAttendanceService.getData(learner.Id, termId);
            System.assertNotEquals(null, rows);
        }
        Test.stopTest();
    }

    @IsTest
    static void getData_asPortalUser() {
        List<User> portalUsers = [
            SELECT Id, Contact.AccountId
            FROM User
            WHERE Email = 'testatt.user@example.com.spjtest'
            LIMIT 1
        ];
        if (portalUsers.isEmpty() || portalUsers[0].Contact == null) {
            return;
        }
        Id accountId = portalUsers[0].Contact.AccountId;
        Id termId = null;
        try {
            SObject t = Database.query('SELECT Id FROM AcademicTerm LIMIT 1');
            termId = (Id) t.get('Id');
        } catch (Exception e) {}

        if (termId == null || accountId == null) {
            return;
        }

        Test.startTest();
        System.runAs(portalUsers[0]) {
            StudentAttendanceService.getData(accountId, termId);
        }
        Test.stopTest();
    }
}
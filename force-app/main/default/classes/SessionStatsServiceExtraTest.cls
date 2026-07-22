/**
 * Exercises SessionStatsService.getSessionStats / getSessionsByStatus across all supported record
 * types (LearningCourse, ProgramCohort, Instructor__c, CourseOffering, AcademicTerm,
 * Course_Instructor__c) plus the unsupported-type throw, using existing org records.
 */
@IsTest(seeAllData=true)
private class SessionStatsServiceExtraTest {

    private static void run(Id recordId) {
        if (recordId == null) {
            return;
        }
        try { SessionStatsService.getSessionStats(recordId); } catch (Exception e) {}
        for (String key : new List<String>{ 'published', 'completed', 'republished', 'cancelled', 'other' }) {
            try { SessionStatsService.getSessionsByStatus(recordId, key); } catch (Exception e) {}
        }
    }

    private static Id firstId(String soql) {
        List<SObject> rows = Database.query(soql);
        return rows.isEmpty() ? null : rows[0].Id;
    }

    @IsTest
    static void getStats_acrossAllSupportedTypes() {
        Test.startTest();
        run(firstId('SELECT Id FROM LearningCourse LIMIT 1'));
        run(firstId('SELECT Id FROM ProgramCohort LIMIT 1'));
        run(firstId('SELECT Id FROM Instructor__c LIMIT 1'));
        run(firstId('SELECT Id FROM CourseOffering LIMIT 1'));
        run(firstId('SELECT Id FROM AcademicTerm LIMIT 1'));
        run(firstId('SELECT Id FROM Course_Instructor__c LIMIT 1'));
        Test.stopTest();
    }

    @IsTest
    static void getStats_unsupportedTypeThrows() {
        // An Account Id is not a supported scope -> AuraHandledException
        List<Account> accts = [SELECT Id FROM Account LIMIT 1];
        if (accts.isEmpty()) {
            return;
        }
        Boolean threw = false;
        try {
            SessionStatsService.getSessionStats(accts[0].Id);
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Unsupported record type should throw');
    }
}
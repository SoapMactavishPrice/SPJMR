@IsTest(seeAllData=true)
private class TimetableWizardControllerTest {

    @IsTest
    static void testProgramAndCommonLookups() {
        Test.startTest();
        TimetableWizardController.ProgramOptionsResult pr =
            TimetableWizardController.getPrograms();
        System.assertNotEquals(null, pr);
        System.assertNotEquals(null, pr.options);

        List<TimetableWizardController.OptionWrapper> allDivs =
            TimetableWizardController.getAllDivisions();
        System.assertNotEquals(null, allDivs);

        List<TimetableWizardController.OptionWrapper> allTerms =
            TimetableWizardController.getAllTerms();
        System.assertNotEquals(null, allTerms);
        Test.stopTest();
    }

    @IsTest
    static void testScopedLookupsAndAssignments() {
        List<Program> programs = [SELECT Id FROM Program WHERE IsActive = true LIMIT 1];
        List<AcademicYear> years = [SELECT Id, Batch__c FROM AcademicYear WHERE Batch__c != null LIMIT 1];
        List<AcademicTerm> terms = [SELECT Id FROM AcademicTerm WHERE AcademicYearId != null LIMIT 1];
        List<Division__c> divs = [SELECT Id, Name FROM Division__c LIMIT 1];
        List<Session__c> sessions = [SELECT Id FROM Session__c LIMIT 1];

        Test.startTest();
        System.assertEquals(0, TimetableWizardController.getTermsForPrograms(null).size());
        System.assertEquals(0, TimetableWizardController.getBatchesForProgram(null).size());
        System.assertEquals(0, TimetableWizardController.getBatchGroupsForBatch(null).size());
        System.assertEquals(0, TimetableWizardController.getTermsForBatchGroup(null).size());
        System.assertEquals(0, TimetableWizardController.getCoursesForDivision(null).size());
        System.assertEquals(0, TimetableWizardController.getDivisionsForTerms(null).size());
        TimetableWizardController.getCourseAssignments(null, null, null, null, null, null);
        TimetableWizardController.getSessionDivisions(null, null);
        if (!programs.isEmpty()) {
            TimetableWizardController.getTermsForPrograms(new List<Id>{ programs[0].Id });
            TimetableWizardController.getBatchesForProgram(programs[0].Id);
        }
        if (!years.isEmpty()) {
            TimetableWizardController.getBatchGroupsForBatch(years[0].Batch__c);
            TimetableWizardController.getTermsForBatchGroup(years[0].Id);
        }
        if (!divs.isEmpty()) {
            TimetableWizardController.getCoursesForDivision(String.valueOf(divs[0].Id));
            TimetableWizardController.getCoursesForDivision(divs[0].Name);
            TimetableWizardController.getCoursesForDivision('invalid-division-token');
        }
        if (!terms.isEmpty()) {
            TimetableWizardController.getDivisionsForTerms(new List<Id>{ terms[0].Id });
        }
        if (!sessions.isEmpty()) {
            TimetableWizardController.getSessionDivisions(sessions[0].Id, 'refresh');
        }

        // Drive deeper getCourseAssignments path with real context when available
        List<DivisionCourse__c> dcs = [
            SELECT Division__c,
                   Division__r.Term__c,
                   Division__r.Term__r.AcademicYearId,
                   Division__r.Term__r.AcademicYear.Batch__c,
                   Division__r.Term__r.AcademicYear.Batch__r.ProgramId,
                   Course_Offering__r.LearningCourseId
            FROM DivisionCourse__c
            WHERE Division__c != null
            AND Division__r.Term__c != null
            AND Course_Offering__r.LearningCourseId != null
            LIMIT 1
        ];
        if (!dcs.isEmpty()) {
            DivisionCourse__c dc = dcs[0];
            TimetableWizardController.getCourseAssignments(
                String.valueOf(dc.Course_Offering__r.LearningCourseId),
                String.valueOf(dc.Division__c),
                dc.Division__r.Term__r.AcademicYear.Batch__r.ProgramId != null ? String.valueOf(dc.Division__r.Term__r.AcademicYear.Batch__r.ProgramId) : null,
                dc.Division__r.Term__r.AcademicYear.Batch__c != null ? String.valueOf(dc.Division__r.Term__r.AcademicYear.Batch__c) : null,
                dc.Division__r.Term__r.AcademicYearId != null ? String.valueOf(dc.Division__r.Term__r.AcademicYearId) : null,
                dc.Division__r.Term__c != null ? String.valueOf(dc.Division__r.Term__c) : null
            );
            // Variant without program/batch context to hit broader filtering branch.
            TimetableWizardController.getCourseAssignments(
                String.valueOf(dc.Course_Offering__r.LearningCourseId),
                String.valueOf(dc.Division__c),
                null,
                null,
                null,
                dc.Division__r.Term__c != null ? String.valueOf(dc.Division__r.Term__c) : null
            );
        }
        Test.stopTest();
    }
}
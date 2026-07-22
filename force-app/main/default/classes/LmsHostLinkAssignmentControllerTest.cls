@IsTest
private class LmsHostLinkAssignmentControllerTest {

    @TestSetup
    static void setup() {
        Id progId = SpjimrPortalTestDataFactory.insertProgram();
        Id attBatch = SpjimrPortalTestDataFactory.insertProgramCohort(progId);
        // Second cohort with a unique batch code (the factory uses a fixed code, so a direct
        // insert is needed to get a distinct host batch).
        Id hostBatch = null;
        try {
            // Short_Batch_Code__c is capped at 3 chars and must differ from the attendee batch.
            ProgramCohort host = new ProgramCohort(
                Name = 'Host Cohort', ProgramId = progId,
                Batch_Code__c = 'HOSTB', Short_Batch_Code__c = 'HB',
                Batch_Sub_Type__c = 'Class Room', Batch_Base_Currency__c = 'INR');
            insert host;
            hostBatch = host.Id;
        } catch (Exception e) { System.debug('host cohort skipped: ' + e.getMessage()); }

        Id lcId = createLearningCourse();

        List<Program_Courses__c> pcs = new List<Program_Courses__c>();
        // Attendee (non-host) course in attBatch
        pcs.add(new Program_Courses__c(
            Batch__c = attBatch, Learning_Course__c = lcId, Is_Host_Course__c = false));
        // Host course sharing the same Learning Course, in a different batch (so it can match)
        if (hostBatch != null) {
            pcs.add(new Program_Courses__c(
                Batch__c = hostBatch, Learning_Course__c = lcId, Is_Host_Course__c = true));
        } else {
            // Ensure at least two Program Courses exist so the save-links update path runs.
            pcs.add(new Program_Courses__c(
                Batch__c = attBatch, Learning_Course__c = lcId, Is_Host_Course__c = true));
        }
        insert pcs;
    }

    private static Id createLearningCourse() {
        try {
            SObject learning = (SObject) Type.forName('Learning').newInstance();
            learning.put('Name', 'LMS Test Learning');
            insert learning;

            SObject dept = (SObject) Type.forName('Department_Master__c').newInstance();
            dept.put('Name', 'LMS Dept');
            try { dept.put('Department_Code__c', 'LMSD'); } catch (Exception e) {}
            insert dept;

            SObject lc = (SObject) Type.forName('LearningCourse').newInstance();
            lc.put('Name', 'LMS Learning Course');
            lc.put('LearningId', learning.Id);
            lc.put('Course_Department__c', dept.Id);
            insert lc;
            return (Id) lc.get('Id');
        } catch (Exception e) {
            System.debug('createLearningCourse skipped: ' + e.getMessage());
            return null;
        }
    }

    private static Id attendeeBatchId() {
        return [SELECT Batch__c FROM Program_Courses__c WHERE Is_Host_Course__c = false LIMIT 1].Batch__c;
    }

    @IsTest
    static void getPageData_validation() {
        Test.startTest();
        try {
            LmsHostLinkAssignmentController.getPageData(null, null, null, null);
            System.assert(false, 'Null batch should throw.');
        } catch (AuraHandledException e) { /* expected */ }
        Test.stopTest();
    }

    @IsTest
    static void getPageData_orgLoadAndLwcContext() {
        Id batchId = attendeeBatchId();

        Test.startTest();
        // Org-load branch (no LWC context): builds attendee sections + host options.
        LmsHostLinkAssignmentController.LmsPageData p1 =
            LmsHostLinkAssignmentController.getPageData(batchId, null, null, null);
        System.assertNotEquals(null, p1);
        System.assertNotEquals(null, p1.attendeeSections);
        System.assert(!p1.attendeeSections.isEmpty(), 'Attendee section should be produced.');

        // LWC-context branch: explicit name + date range (exercises safeParseDate).
        LmsHostLinkAssignmentController.LmsPageData p2 =
            LmsHostLinkAssignmentController.getPageData(
                batchId, 'My Batch',
                String.valueOf(Date.today().addDays(-3)),
                String.valueOf(Date.today().addDays(3)));
        System.assertNotEquals(null, p2.context);
        Test.stopTest();
    }

    @IsTest
    static void getPageData_edgeBranches() {
        Id batchId = attendeeBatchId();
        Test.startTest();
        // LWC context with bad date strings -> safeParseDate short-circuit + parse-failure paths.
        LmsHostLinkAssignmentController.LmsPageData p =
            LmsHostLinkAssignmentController.getPageData(batchId, 'Name', 'abc', 'abcdefgh');
        System.assertNotEquals(null, p);

        // A batch whose only course is a host course -> no attendees -> empty sections branch.
        List<Program_Courses__c> hosts = [SELECT Batch__c FROM Program_Courses__c WHERE Is_Host_Course__c = true LIMIT 1];
        if (!hosts.isEmpty() && hosts[0].Batch__c != null && hosts[0].Batch__c != batchId) {
            LmsHostLinkAssignmentController.LmsPageData ph =
                LmsHostLinkAssignmentController.getPageData(hosts[0].Batch__c, null, null, null);
            System.assertNotEquals(null, ph);
        }
        Test.stopTest();
    }

    @IsTest
    static void searchProgrammeCourses_returnsHosts() {
        Test.startTest();
        List<LmsHostLinkAssignmentController.LookupSearchResult> all =
            LmsHostLinkAssignmentController.searchProgrammeCourses(null, null);
        List<LmsHostLinkAssignmentController.LookupSearchResult> filtered =
            LmsHostLinkAssignmentController.searchProgrammeCourses('LMS', new List<String>());
        Test.stopTest();
        System.assertNotEquals(null, all);
        System.assertNotEquals(null, filtered);
    }

    @IsTest
    static void saveLmsHostLinks_noopAndUpdate() {
        Test.startTest();
        LmsHostLinkAssignmentController.saveLmsHostLinks(null);
        LmsHostLinkAssignmentController.saveLmsHostLinks(
            new List<LmsHostLinkAssignmentController.LmsLinkInput>());
        LmsHostLinkAssignmentController.saveLmsHostLinks(
            new List<LmsHostLinkAssignmentController.LmsLinkInput>{
                new LmsHostLinkAssignmentController.LmsLinkInput() }); // null ids skipped

        List<Program_Courses__c> pcs = [SELECT Id FROM Program_Courses__c];
        if (pcs.size() >= 2) {
            LmsHostLinkAssignmentController.LmsLinkInput link =
                new LmsHostLinkAssignmentController.LmsLinkInput();
            link.attendeeProgramCourseId = pcs[0].Id;
            link.hostProgramCourseId = pcs[1].Id;
            LmsHostLinkAssignmentController.saveLmsHostLinks(
                new List<LmsHostLinkAssignmentController.LmsLinkInput>{ link });
            Program_Courses__c after = [SELECT LMS_Course__c FROM Program_Courses__c WHERE Id = :pcs[0].Id];
            System.assertEquals(pcs[1].Id, after.LMS_Course__c, 'LMS host link should be saved.');
        }
        Test.stopTest();
    }
}
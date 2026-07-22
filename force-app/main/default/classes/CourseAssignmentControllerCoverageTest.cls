/**
 * Deterministic, self-contained coverage for CourseAssignmentController.
 * Builds the full Program -> ProgramCohort(Batch) -> AcademicYear(Batch Group) ->
 * AcademicTerm -> Program_Courses__c -> CourseOffering chain in @TestSetup so the
 * controller's queries return real rows regardless of org seed data.
 */
@IsTest
private class CourseAssignmentControllerCoverageTest {

    @TestSetup
    static void setup() {
        Id progId = SpjimrPortalTestDataFactory.insertProgram();
        Id cohortId = SpjimrPortalTestDataFactory.insertProgramCohort(progId);

        // AcademicYear = "Batch Group", links the Batch (ProgramCohort) to its terms.
        AcademicYear ay = new AcademicYear(
            Name = 'CAC Batch Group',
            Batch__c = cohortId,
            Batch_Group_Sub_Type__c = 'Class Room',
            Batch_Group_Base_Currency__c = 'INR'
        );
        insert ay;

        // Two terms in the same Batch Group (term1 = current, term2 = evaluation/end term).
        AcademicTerm term1 = new AcademicTerm(Name = 'CAC Term 1', AcademicYearId = ay.Id);
        AcademicTerm term2 = new AcademicTerm(Name = 'CAC Term 2', AcademicYearId = ay.Id);
        insert new List<AcademicTerm>{ term1, term2 };

        // Learning course chain (Learning -> Department_Master -> LearningCourse).
        SObject learning = (SObject) Type.forName('Learning').newInstance();
        learning.put('Name', 'CAC Learning');
        insert learning;

        SObject dept = (SObject) Type.forName('Department_Master__c').newInstance();
        dept.put('Name', 'CAC Dept');
        try { dept.put('Department_Code__c', 'CACD'); } catch (Exception e) {}
        insert dept;

        SObject lc = (SObject) Type.forName('LearningCourse').newInstance();
        lc.put('Name', 'CAC Learning Course');
        lc.put('LearningId', learning.Id);
        lc.put('Course_Department__c', dept.Id);
        insert lc;
        Id lcId = (Id) lc.get('Id');

        // Program Courses: one multi-term, two single-term (one assigned elsewhere, one free).
        Program_Courses__c pcMulti = new Program_Courses__c(
            Batch__c = cohortId, Learning_Course__c = lcId,
            Is_Active__c = true, Is_Multi_Term__c = true, Course_Type__c = 'Core');
        Program_Courses__c pcSingleAssigned = new Program_Courses__c(
            Batch__c = cohortId, Learning_Course__c = lcId,
            Is_Active__c = true, Is_Multi_Term__c = false, Course_Type__c = 'Core');
        Program_Courses__c pcSingleFree = new Program_Courses__c(
            Batch__c = cohortId, Learning_Course__c = lcId,
            Is_Active__c = true, Is_Multi_Term__c = false, Course_Type__c = 'Elective');
        insert new List<Program_Courses__c>{ pcMulti, pcSingleAssigned, pcSingleFree };

        // CourseOfferings:
        //  - multi-term offering in term2 WITH End_Term__c -> drives the "read-only evaluation
        //    term" branch in getTermDetails / getBatchCourseOfferings.
        //  - single-term offering in term2 -> marks pcSingleAssigned as "assigned to other term".
        List<CourseOffering> offerings = new List<CourseOffering>();
        offerings.add(new CourseOffering(
            Name = 'CAC Multi Offering', Instructor_Role__c = 'Instructor',
            LearningCourseId = lcId, ProgramCourse__c = pcMulti.Id,
            Academic_Term__c = term2.Id, End_Term__c = term2.Id,
            StartDate = Date.today().addDays(-5), EndDate = Date.today().addDays(5)));
        offerings.add(new CourseOffering(
            Name = 'CAC Single Offering', Instructor_Role__c = 'Instructor',
            LearningCourseId = lcId, ProgramCourse__c = pcSingleAssigned.Id,
            Academic_Term__c = term2.Id,
            StartDate = Date.today().addDays(-5), EndDate = Date.today().addDays(5)));
        insert offerings;
    }

    private static Id term1Id() {
        return [SELECT Id FROM AcademicTerm WHERE Name = 'CAC Term 1' LIMIT 1].Id;
    }
    private static Id term2Id() {
        return [SELECT Id FROM AcademicTerm WHERE Name = 'CAC Term 2' LIMIT 1].Id;
    }

    @IsTest
    static void readMethods_happyPaths() {
        Id term1 = term1Id();
        Id term2 = term2Id();

        Test.startTest();
        // Null/guard paths
        System.assertEquals(0, CourseAssignmentController.getEvaluationTermsForBatch(null).size());
        System.assertEquals(0,
            CourseAssignmentController.getExistingCourseOfferingsForEvaluationTerm(null, null).size());

        List<CourseAssignmentController.CourseWrapper> details =
            CourseAssignmentController.getTermDetails(term1);
        System.assertNotEquals(null, details);

        List<CourseAssignmentController.EvaluationTermWrapper> evalTerms =
            CourseAssignmentController.getEvaluationTermsForBatch(term1);
        System.assert(evalTerms.size() >= 2, 'Both terms in the batch should be returned.');

        CourseAssignmentController.BatchCourseOfferingsResponse resp =
            CourseAssignmentController.getBatchCourseOfferings(term1, null);
        System.assertNotEquals(null, resp);
        // With an evaluation term that matches the multi-term offering's End_Term__c.
        CourseAssignmentController.BatchCourseOfferingsResponse resp2 =
            CourseAssignmentController.getBatchCourseOfferings(term1, term2);
        System.assertNotEquals(null, resp2);

        Id pcMultiId = [SELECT Id FROM Program_Courses__c WHERE Is_Multi_Term__c = true LIMIT 1].Id;
        List<CourseAssignmentController.ExistingCourseOfferingWrapper> existing =
            CourseAssignmentController.getExistingCourseOfferingsForEvaluationTerm(pcMultiId, term2);
        System.assertNotEquals(null, existing);
        Test.stopTest();
    }

    @IsTest
    static void saveEditableCourses_singleAndMultiTerm() {
        Id term1 = term1Id();
        Id term2 = term2Id();
        Program_Courses__c pcMulti =
            [SELECT Id, Learning_Course__c FROM Program_Courses__c WHERE Is_Multi_Term__c = true LIMIT 1];
        Program_Courses__c pcSingle =
            [SELECT Id, Learning_Course__c FROM Program_Courses__c WHERE Is_Multi_Term__c = false LIMIT 1];

        // Single-term insert
        CourseAssignmentController.CourseAssignmentWrapper single =
            new CourseAssignmentController.CourseAssignmentWrapper();
        single.courseId = pcSingle.Id;
        single.learningCourse = pcSingle.Learning_Course__c;
        single.courseName = 'Single';
        single.startDate = Date.today();
        single.endDate = Date.today().addDays(20);
        single.isMultiTerm = false;

        // Multi-term, same term (termId == evaluationTermId) -> single record branch
        CourseAssignmentController.CourseAssignmentWrapper sameTerm =
            new CourseAssignmentController.CourseAssignmentWrapper();
        sameTerm.courseId = pcMulti.Id;
        sameTerm.learningCourse = pcMulti.Learning_Course__c;
        sameTerm.courseName = 'Multi-Same';
        sameTerm.startDate = Date.today();
        sameTerm.endDate = Date.today().addDays(20);
        sameTerm.isMultiTerm = true;
        sameTerm.evaluationTermId = term1;

        // Multi-term, different term -> two-record branch
        CourseAssignmentController.CourseAssignmentWrapper diffTerm =
            new CourseAssignmentController.CourseAssignmentWrapper();
        diffTerm.courseId = pcMulti.Id;
        diffTerm.learningCourse = pcMulti.Learning_Course__c;
        diffTerm.courseName = 'Multi-Diff';
        diffTerm.startDate = Date.today();
        diffTerm.endDate = Date.today().addDays(20);
        diffTerm.isMultiTerm = true;
        diffTerm.evaluationTermId = term2;

        Test.startTest();
        // No-op path
        CourseAssignmentController.saveEditableCourses(
            term1, new List<CourseAssignmentController.CourseAssignmentWrapper>(), new List<Id>());
        // Insert paths
        CourseAssignmentController.saveEditableCourses(
            term1, new List<CourseAssignmentController.CourseAssignmentWrapper>{ single, sameTerm, diffTerm }, null);
        Test.stopTest();

        System.assert(
            [SELECT COUNT() FROM CourseOffering WHERE Academic_Term__c = :term1] > 0,
            'Offerings should have been created for the current term.');
    }

    @IsTest
    static void saveEditableCourses_readOnlyAndUpdateAndDelete() {
        Id term1 = term1Id();
        Id term2 = term2Id();
        Program_Courses__c pcMulti =
            [SELECT Id, Learning_Course__c FROM Program_Courses__c WHERE Is_Multi_Term__c = true LIMIT 1];

        // existingCourseOfferingId update branch + read-only branch
        CourseOffering existingMulti =
            [SELECT Id FROM CourseOffering WHERE ProgramCourse__c = :pcMulti.Id AND End_Term__c != NULL LIMIT 1];

        CourseAssignmentController.CourseAssignmentWrapper readOnly =
            new CourseAssignmentController.CourseAssignmentWrapper();
        readOnly.courseId = pcMulti.Id;
        readOnly.learningCourse = pcMulti.Learning_Course__c;
        readOnly.courseName = 'Read Only';
        readOnly.startDate = Date.today();
        readOnly.endDate = Date.today().addDays(10);
        readOnly.isMultiTerm = true;
        readOnly.evaluationTermId = term2;
        readOnly.isEvaluationTermReadOnly = true;

        CourseAssignmentController.CourseAssignmentWrapper withExisting =
            new CourseAssignmentController.CourseAssignmentWrapper();
        withExisting.courseId = pcMulti.Id;
        withExisting.learningCourse = pcMulti.Learning_Course__c;
        withExisting.courseName = 'With Existing';
        withExisting.startDate = Date.today();
        withExisting.endDate = Date.today().addDays(10);
        withExisting.isMultiTerm = true;
        withExisting.evaluationTermId = term2;
        withExisting.existingCourseOfferingId = existingMulti.Id;

        Id toDeleteId = existingMulti.Id;

        Test.startTest();
        CourseAssignmentController.saveEditableCourses(
            term1, new List<CourseAssignmentController.CourseAssignmentWrapper>{ readOnly }, null);
        CourseAssignmentController.saveEditableCourses(
            term1, new List<CourseAssignmentController.CourseAssignmentWrapper>{ withExisting }, null);
        // Delete branch
        CourseAssignmentController.saveEditableCourses(
            term1, new List<CourseAssignmentController.CourseAssignmentWrapper>(), new List<Id>{ toDeleteId });
        Test.stopTest();
    }
}
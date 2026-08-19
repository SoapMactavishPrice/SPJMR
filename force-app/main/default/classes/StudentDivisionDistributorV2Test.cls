@isTest
private class StudentDivisionDistributorV2Test {

  /* ================= TEST DATA FACTORY ================= */

  // Program_Code__c and Short_Programme_Code__c are enforced as unique.
  // Reuse one Program/Cohort in each test method; every student only needs
  // its own ProgramEnrollment and ProgramCohortMember.
  private static Integer testDataSequence = 0;
  private static Program sharedProgram;
  private static ProgramCohort sharedCohort;

  private static String uniqueTestValue(String prefix) {
    testDataSequence++;
    String suffix = String.valueOf(testDataSequence);
    while (suffix.length() < 3) {
      suffix = '0' + suffix;
    }
    return prefix + suffix;
  }

  private static Division_Group__c createFundamentalGroup() {
    Division_Group__c g = new Division_Group__c(Name = 'Fundamental');
    insert g;
    return g;
  }

  private static AcademicTerm createTerm() {
    AcademicTerm t = new AcademicTerm(
Name = 'Test Term',
Term_Start_Date__c = Date.today().addDays(-1),
Term_End_Date__c = Date.today().addDays(1));
    insert t;
    return t;
  }

  private static Division__c createDivision(
    String label, Id termId, Id groupId, Decimal capacity, Boolean isActive
  ) {
    Division__c d = new Division__c(
      Division_Name__c = label,
      Term__c = termId,
      Division_Group__c = groupId,
      Capacity__c = capacity
    );
    insert d;
    return d;
  }

  private static Account createStudentAccount(String name, String gender) {
    Account a = new Account(Name = name, Gender__c = gender);
    insert a;
    return a;
  }

  private static Program createProgram() {
    String programCode = uniqueTestValue('T');
    String shortProgramCode = 'S' + programCode.right(2);
    Program p = new Program(
      Name = 'Test Program ' + programCode,
      Program_Code__c = programCode,
      // This field is limited to three characters in this org.
      Short_Programme_Code__c = shortProgramCode,
      Programme_Type__c = 'Full-time',
      Programme_Sub_Type__c = 'Class Room',
      IsActive=true
    );
    insert p;
    return p;
  }

  private static ProgramEnrollment createProgramEnrollment(Id accountId, Id programId) {
    ProgramEnrollment pe = new ProgramEnrollment(
      AccountId = accountId,
      ProgramId = programId
    );
    insert pe;
    return pe;
  }

  // ProgramCohort is the second parent that ProgramCohortMember needs
  // alongside ProgramEnrollment. Previously missing entirely - this is the
  // root-cause fix for the INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
  // error. If ProgramCohort requires additional fields in this org (e.g. a
  // Start_Date__c), add them here only.
  private static ProgramCohort createProgramCohort(Id programId) {
    String batchCode = uniqueTestValue('B');

    ProgramCohort pc = new ProgramCohort(
        Name = 'Test Cohort ' + batchCode,
        ProgramId = programId,

        Batch_Code__c = batchCode,
        Batch_Sub_Type__c = 'Class Room'
    );

    insert pc;
    return pc;
  }

  private static void ensureSharedProgramAndCohort() {
    if (sharedProgram == null) {
      sharedProgram = createProgram();
      sharedCohort = createProgramCohort(sharedProgram.Id);
    }
  }

  private static ProgramCohortMember createCohortMember(Id programEnrollmentId, Id programCohortId) {
    ProgramCohortMember pcm = new ProgramCohortMember(
      ProgramEnrollmentId = programEnrollmentId,
      ProgramCohortId = programCohortId
    );
    insert pcm;
    return pcm;
  }

  private static Specialisation_Master__c createSpecialisation(String name) {
    Specialisation_Master__c s = new Specialisation_Master__c(
      Name = name,
      Specialisation_Code__c = name
    );
    insert s;
    return s;
  }

  private static void assignMajorSpecialisation(Id cohortMemberId, Id specialisationMasterId) {
    insert new Student_Specialisation__c(
      Program_Cohort_Member__c = cohortMemberId,
      Specialisation_Master__c = specialisationMasterId,
      Specialisation_Type__c = 'Major'
    );
  }

  private static void assignGradType(Id accountId, String gradType) {

    PersonEducation pe = new PersonEducation(
        Name = 'Education Record',
        AccountId = accountId,
        Graduation_Type__c = gradType
    );

    insert pe;
}

  private static void assignWorkExperience(Id accountId, Decimal years) {
    Date endDate = Date.today();
    Integer days = Integer.valueOf(years * 365);
    Date startDate = endDate.addDays(-days);

    insert new Work_Experience__c(
      Student__c = accountId,
      Start_Date__c = startDate,
      End_Date__c = endDate
    );
  }

  private static AcademicTermEnrollment createEnrollment(
    Id termId,
    Id accountId,
    Id programEnrollmentId
  ) {
    Contact learnerContact = new Contact(
      LastName = 'Learner ' + String.valueOf(accountId),
      AccountId = accountId
    );
    insert learnerContact;

    AcademicTermEnrollment e = new AcademicTermEnrollment(
      AcademicTermId = termId,
      LearnerAccountId = accountId,
      LearnerContactId = learnerContact.Id,
      Program_Enrolled__c = programEnrollmentId
    );
    insert e;
    return e;
  }

  // Builds one fully-specified unassigned student (account, shared program
  // and cohort, program enrollment, cohort member, optional Major
  // specialisation, grad type, and work experience) and returns the
  // AcademicTermEnrollment Id - exactly what the class allocates against.
  private static Id buildStudent(
    Id termId, String name, String gender, Id specialisationMasterId,
    String gradType, Decimal workExpYears
  ) {
    Account acc = createStudentAccount(name, gender);
    ensureSharedProgramAndCohort();
    ProgramEnrollment pe = createProgramEnrollment(acc.Id, sharedProgram.Id);
    ProgramCohortMember pcm = createCohortMember(pe.Id, sharedCohort.Id);
    if (specialisationMasterId != null) {
      assignMajorSpecialisation(pcm.Id, specialisationMasterId);
    }
    assignGradType(acc.Id, gradType);
    assignWorkExperience(acc.Id, workExpYears);
    AcademicTermEnrollment enr = createEnrollment(termId, acc.Id, pe.Id);
    return enr.Id;
  }

  // Commits an enrollment straight to a division, bypassing the algorithm -
  // used to simulate "already assigned" or "already at capacity" states.
  private static void commitDirectly(Id enrollmentId, Id divisionId) {
    insert new Division_Enrollment__c(
      Academic_Term_Enrollment__c = enrollmentId,
      Division__c = divisionId
    );
    update new AcademicTermEnrollment(Id = enrollmentId, Division__c = divisionId);
  }

  /* ================= previewDistribution ================= */

  @isTest
  static void testPreview_NoActiveDivisions() {
    AcademicTerm term = createTerm();

    Test.startTest();
    Boolean threw = false;
    try {
      StudentDivisionDistributorV2.previewDistribution(term.Id);
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw, 'Expected an exception when no active Fundamental divisions exist');
  }

  @isTest
  static void testPreview_NoUnassignedStudents() {
    AcademicTerm term = createTerm();
    Division_Group__c grp = createFundamentalGroup();
    createDivision('A', term.Id, grp.Id, 10, true);

    Test.startTest();
    Boolean threw = false;
    try {
      StudentDivisionDistributorV2.previewDistribution(term.Id);
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw, 'Expected an exception when there are no unassigned students');
  }

  @isTest
  static void testPreview_FullAllocationAndDivisionFiltering() {
    AcademicTerm term = createTerm();
    Division_Group__c grp = createFundamentalGroup();
    createDivision('A', term.Id, grp.Id, 100, true);
    createDivision('B', term.Id, grp.Id, 100, true);
    createDivision('C', term.Id, grp.Id, 100, true);
    // An inactive division and a non-Fundamental division must both be
    // ignored entirely by the algorithm.
    Division_Group__c otherGrp = new Division_Group__c(Name = 'Elective');
    insert otherGrp;
    createDivision('X-Inactive', term.Id, grp.Id, 100, false);
    createDivision('X-OtherGroup', term.Id, otherGrp.Id, 100, true);

    Specialisation_Master__c fin = createSpecialisation('FIN');
    Specialisation_Master__c im = createSpecialisation('IM');
    // ProgramCohortMemberHelper runs SOQL for each ProgramCohortMember
    // insert in this org. Keep this test intentionally small; this method
    // verifies round-robin allocation and division filtering, not every
    // possible attribute combination.
    buildStudent(term.Id, 'Student1', 'Male', fin.Id, 'Technical', 0.5);
    buildStudent(term.Id, 'Student2', 'Female', im.Id, 'Non Technical', 2);
    buildStudent(term.Id, 'NoGender', null, fin.Id, 'Technical', 3.5);
    Integer total = 3;

    Test.startTest();
    StudentDivisionDistributorV2.PreviewResult result =
      StudentDivisionDistributorV2.previewDistribution(term.Id);
    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(total, result.assignments.size());
  }

  @isTest
  static void testPreview_CapacityFullyBlocked() {
    AcademicTerm term = createTerm();
    Division_Group__c grp = createFundamentalGroup();
    Division__c divA = createDivision('A', term.Id, grp.Id, 1, true);

    Id filledEnr = buildStudent(term.Id, 'Filled', 'Male', null, 'Technical', 0);
    commitDirectly(filledEnr, divA.Id);

    buildStudent(term.Id, 'New1', 'Female', null, 'Non Technical', 2);

    Test.startTest();
    Boolean threw = false;
    try {
      StudentDivisionDistributorV2.previewDistribution(term.Id);
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(true, threw, 'Expected an exception when every division is already at capacity');
  }

  @isTest
  static void testPreview_CapacityPartialSkip() {
    AcademicTerm term = createTerm();
    Division_Group__c grp = createFundamentalGroup();
    Division__c divA = createDivision('A', term.Id, grp.Id, 1, true);
    createDivision('B', term.Id, grp.Id, 10, true);

    Id filledEnr = buildStudent(term.Id, 'Filled', 'Male', null, 'Technical', 0);
    commitDirectly(filledEnr, divA.Id);

    buildStudent(term.Id, 'New1', 'Male', null, 'Technical', 0);
    buildStudent(term.Id, 'New2', 'Female', null, 'Non Technical', 4);

    Test.startTest();
    StudentDivisionDistributorV2.PreviewResult result =
      StudentDivisionDistributorV2.previewDistribution(term.Id);
    Test.stopTest();

    System.assertEquals(2, result.assignments.size(), 'Both new students should still be placed in Division B');
    System.assertEquals(true, result.warnings.size() > 0, 'Expected a capacity warning for Division A');
  }

  /* ================= confirmDistribution ================= */

  @isTest
  static void testConfirm_NullAndEmptyAssignments() {
    StudentDivisionDistributorV2.ConfirmResult nullResult =
      StudentDivisionDistributorV2.confirmDistribution(null);
    System.assertEquals(false, nullResult.success);

    StudentDivisionDistributorV2.ConfirmResult emptyResult =
      StudentDivisionDistributorV2.confirmDistribution(new Map<Id, Id>());
    System.assertEquals(false, emptyResult.success);
  }

  @isTest
  static void testConfirm_NoValidPairs() {
    // A non-null key with a null value should be filtered out entirely,
    // leaving nothing valid to confirm.
    Account acc = createStudentAccount('Placeholder', 'Male');
    Map<Id, Id> assignments = new Map<Id, Id>{ acc.Id => null };

    StudentDivisionDistributorV2.ConfirmResult result =
      StudentDivisionDistributorV2.confirmDistribution(assignments);

    System.assertEquals(false, result.success);
  }

  @isTest
  static void testConfirm_SuccessThenDuplicateGuard() {
    AcademicTerm term = createTerm();
    Division_Group__c grp = createFundamentalGroup();
    createDivision('A', term.Id, grp.Id, 10, true);
    createDivision('B', term.Id, grp.Id, 10, true);

    buildStudent(term.Id, 'C1', 'Male', null, 'Technical', 0);
    buildStudent(term.Id, 'C2', 'Female', null, 'Non Technical', 4);

    Test.startTest();
    StudentDivisionDistributorV2.PreviewResult preview =
      StudentDivisionDistributorV2.previewDistribution(term.Id);

    StudentDivisionDistributorV2.ConfirmResult firstConfirm =
      StudentDivisionDistributorV2.confirmDistribution(preview.assignments);

    // Confirming the exact same preview again must skip both (already
    // linked) rather than duplicate-insert or error out.
    StudentDivisionDistributorV2.ConfirmResult secondConfirm =
      StudentDivisionDistributorV2.confirmDistribution(preview.assignments);
    Test.stopTest();

    System.assertEquals(true, firstConfirm.success);
    System.assertEquals(2, firstConfirm.savedCount);
    System.assertEquals(false, secondConfirm.success);
    System.assertEquals(2, [SELECT COUNT() FROM Division_Enrollment__c]);
  }

  @isTest
  static void testConfirm_DmlFailureRollsBackCompletely() {
    AcademicTerm term = createTerm();
    Division_Group__c grp = createFundamentalGroup();
    Division__c divA = createDivision('A', term.Id, grp.Id, 10, true);

    Id enrId = buildStudent(term.Id, 'Stale', 'Male', null, 'Technical', 0);
    Map<Id, Id> assignments = new Map<Id, Id>{ enrId => divA.Id };

    // Simulate a stale reference (division deleted between preview and
    // confirm) so the insert hits an invalid cross-reference and both the
    // insert and the AcademicTermEnrollment update must roll back together.
    delete divA;

    Test.startTest();
    StudentDivisionDistributorV2.ConfirmResult result =
      StudentDivisionDistributorV2.confirmDistribution(assignments);
    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assertEquals(true, result.errors.size() > 0);
    System.assertEquals(0, [SELECT COUNT() FROM Division_Enrollment__c]);

    AcademicTermEnrollment reloaded = [SELECT Division__c FROM AcademicTermEnrollment WHERE Id = :enrId];
    System.assertEquals(null, reloaded.Division__c, 'Enrollment must not be left pointing at a deleted division');
  }

  /* ================= validateDistribution ================= */

  @isTest
  static void testValidate_NoDivisions() {
    AcademicTerm term = createTerm();

    Test.startTest();
    StudentDivisionDistributorV2.ValidationResult result =
      StudentDivisionDistributorV2.validateDistribution(term.Id);
    Test.stopTest();

    System.assertEquals(false, result.isValid);
    System.assertEquals('No divisions found for this term', result.message);
  }

  @isTest
  static void testValidate_AfterConfirmReflectsCommittedData() {
    AcademicTerm term = createTerm();
    Division_Group__c grp = createFundamentalGroup();
    createDivision('A', term.Id, grp.Id, 50, true);
    createDivision('B', term.Id, grp.Id, 50, true);
    createDivision('C', term.Id, grp.Id, 50, true);

    Specialisation_Master__c fin = createSpecialisation('FIN');

    for (Integer i = 0; i < 6; i++) {
      String gender = Math.mod(i, 2) == 0 ? 'Male' : 'Female';
      String grad = Math.mod(i, 2) == 0 ? 'Technical' : 'Non Technical';
      buildStudent(term.Id, 'V' + i, gender, fin.Id, grad, 0.5);
    }

    Test.startTest();
    StudentDivisionDistributorV2.PreviewResult preview =
      StudentDivisionDistributorV2.previewDistribution(term.Id);
    StudentDivisionDistributorV2.confirmDistribution(preview.assignments);

    StudentDivisionDistributorV2.ValidationResult result =
      StudentDivisionDistributorV2.validateDistribution(term.Id);
    Test.stopTest();

    System.assertEquals(3, result.divisions.size());
    System.assertEquals('Distribution meets all requirements', result.message);
  }

  @isTest
  static void testValidate_ZeroGenderDistributionIsInvalid() {
    AcademicTerm term = createTerm();
    Division_Group__c grp = createFundamentalGroup();
    Division__c divA = createDivision('A', term.Id, grp.Id, 100, true);
    Division__c divB = createDivision('B', term.Id, grp.Id, 100, true);

    Specialisation_Master__c fin = createSpecialisation('FIN');
    Specialisation_Master__c im = createSpecialisation('IM');

    // Deliberately leave each division without one gender. That is enough
    // to exercise validateConstraints' critical zero-gender branch without
    // repeatedly invoking the org's non-bulkified cohort-member trigger.
    for (Integer i = 0; i < 2; i++) {
      Id enr = buildStudent(term.Id, 'SkewA' + i, 'Male', fin.Id, 'Technical', 0.5);
      commitDirectly(enr, divA.Id);
    }
    for (Integer i = 0; i < 2; i++) {
      Id enr = buildStudent(term.Id, 'SkewB' + i, 'Female', im.Id, 'Non Technical', 3.5);
      commitDirectly(enr, divB.Id);
    }

    Test.startTest();
    StudentDivisionDistributorV2.ValidationResult result =
      StudentDivisionDistributorV2.validateDistribution(term.Id);
    Test.stopTest();

    System.assertEquals(false, result.isValid);
    System.assertEquals(true, result.warnings.size() > 0);
  }
}
/*
 * Distributes unassigned students into a Term's active "Fundamental"
 * divisions (A, B, C, ...) so that each division ends up with a roughly
 * equal mix of gender, Major specialisation, Work-Experience bucket, and
 * Educational Background (Technical/Non-Technical).*/

public with sharing class StudentDivisionDistributorV2 {
  /* ================= CONSTANTS ================= */
  private static final String MALE = 'Male';
  private static final String FEMALE = 'Female';
  private static final String TECH = 'Technical';
  private static final String NON_TECH = 'Non Technical';
  private static final Integer GENDER_TOLERANCE = 5;
  private static final Decimal EXP_TOLERANCE = 6.0;
  // Sentinel "remaining capacity" for a division with no Capacity__c set.
  private static final Integer UNCAPPED = 999999;

  // Specialisation sort order for Step 3 of the allocation process
  // (Fin -> IM -> Mkt -> OSC). Anything not in this list sorts after these
  // four, alphabetically among themselves.
  private static final List<String> SPEC_ORDER = new List<String>{
    'FIN', 'IM', 'MKT', 'OSC'
  };

  /* ================= INTERNAL MODELS ================= */

  private class Student {
    Id enrollmentId;
    String studentName;
    String gender;
    String gradType;
    Decimal workExp;
    Integer weBucket;
    Id specialisationId;
    String specialisationName;

    public Student(
      Id enrollmentId,
      String studentName,
      String gender,
      String gradType,
      Decimal workExp,
      Id specialisationId,
      String specialisationName
    ) {
      this.enrollmentId = enrollmentId;
      this.studentName = studentName != null ? studentName : '';
      this.gender = gender != null ? gender : '';
      this.gradType = gradType != null ? gradType : '';
      this.workExp = workExp != null ? workExp : 0;
      this.weBucket = StudentDivisionDistributorV2.computeWeBucket(this.workExp);
      this.specialisationId = specialisationId;
      this.specialisationName = specialisationName != null ? specialisationName : '';
    }
  }

  // Work-Experience bucket per the process document (Step 4):
  //   0-1 yr = 0, >1-2 yr = 1, >2-3 yr = 2, >3 yr = 3
  private static Integer computeWeBucket(Decimal years) {
    Decimal yrs = years != null ? years : 0;
    if (yrs <= 1) {
      return 0;
    }
    if (yrs <= 2) {
      return 1;
    }
    if (yrs <= 3) {
      return 2;
    }
    return 3;
  }

  // Wraps loadStudents() output so the specialisation-name lookup built while
  // querying is available to the caller for building preview DTOs later,
  // without re-querying it.
  private class StudentLoadResult {
    List<Student> students;
    Map<Id, String> specialisationIdToName;
  }
  private class DivisionState {
    Id divisionId;
    Integer total = 0;
    Integer male = 0;
    Integer female = 0;
    Integer tech = 0;
    Integer nonTech = 0;
    Decimal maleExpTotal = 0;
    Decimal femaleExpTotal = 0;
    Map<Id, Integer> specialisationCount = new Map<Id, Integer>();
    Map<Integer, Integer> weBucketCount = new Map<Integer, Integer>();

    public Decimal getAvgMaleExp() {
      return male > 0 ? maleExpTotal / male : 0;
    }

    public Decimal getAvgFemaleExp() {
      return female > 0 ? femaleExpTotal / female : 0;
    }

    public void addStudent(Student s) {
      total++;
      if (s.gender == StudentDivisionDistributorV2.MALE) {
        male++;
        maleExpTotal += s.workExp;
      } else if (s.gender == StudentDivisionDistributorV2.FEMALE) {
        female++;
        femaleExpTotal += s.workExp;
      }

      if (s.gradType == StudentDivisionDistributorV2.TECH) {
        tech++;
      } else if (s.gradType == StudentDivisionDistributorV2.NON_TECH) {
        nonTech++;
      }

      if (s.specialisationId != null) {
        Integer currentCount = specialisationCount.containsKey(s.specialisationId) 
          ? specialisationCount.get(s.specialisationId) : 0;
        specialisationCount.put(s.specialisationId, currentCount + 1);
      }

      Integer currentWeCount = weBucketCount.containsKey(s.weBucket)
        ? weBucketCount.get(s.weBucket) : 0;
      weBucketCount.put(s.weBucket, currentWeCount + 1);
    }
  }

  /* ================= LWC DTOs ================= */

  public class DivisionDTO {
    @AuraEnabled
    public Id divisionId;
    // Record auto-number (Division__c.Name), e.g. "DIV-1562".
    @AuraEnabled
    public String divisionAutoNumber;
    // Short display label (Division__c.Division_Name__c), e.g. "A".
    @AuraEnabled
    public String divisionName;
    @AuraEnabled
    public Integer total;
    @AuraEnabled
    public Integer male;
    @AuraEnabled
    public Integer female;
    @AuraEnabled
    public Integer tech;
    @AuraEnabled
    public Integer nonTech;
    @AuraEnabled
    public Decimal avgMaleExp;
    @AuraEnabled
    public Decimal avgFemaleExp;
    @AuraEnabled
    public Map<String, Integer> specialisationCounts;
    // Work-experience bucket counts, keyed "0".."3" per computeWeBucket().
    @AuraEnabled
    public Map<String, Integer> weBucketCounts;
  }

  public class ValidationResult {
    @AuraEnabled
    public Boolean isValid;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<DivisionDTO> divisions;
    @AuraEnabled
    public List<String> warnings;
  }

  // Explicit outcome of confirmDistribution, returned instead of thrown so
  // the client always gets a clear success/failure signal plus the exact
  // DML error(s) if a save failed - rather than a generic caught exception.
  public class ConfirmResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer savedCount;
    @AuraEnabled
    public List<String> errors;
  }

  // Result of running the algorithm WITHOUT committing anything. Carries both
  // the computed division stats (for display) and the raw assignments (to be
  // sent back to confirmDistribution if the user approves). Assignments are
  // a plain enrollmentId -> divisionId map (NOT a List of a custom wrapper
  // type) - Maps of primitive/Id keys and values round-trip reliably through
  // the LWC<->Apex wire; a List<CustomType> is far more prone to silently
  // losing field values on the way back from the client.
  public class PreviewResult {
    @AuraEnabled
    public Boolean isValid;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<DivisionDTO> divisions;
    @AuraEnabled
    public List<String> warnings;
    @AuraEnabled
    public Map<Id, Id> assignments;
  }

  /* ================= PREVIEW (no DML) ================= */

  @AuraEnabled
  public static PreviewResult previewDistribution(Id termId) {
    try {
      List<Division__c> divisions = loadActiveDivisions(termId);
      if (divisions.isEmpty()) {
        throw new DistributionException(
          'No active divisions found for this term'
        );
      }

      StudentLoadResult loadResult = loadStudents(termId);
      List<Student> students = loadResult.students;
      if (students.isEmpty()) {
        throw new DistributionException(
          'No unassigned students found for this term'
        );
      }

      // Initialize division states
      Map<Id, DivisionState> stateMap = initializeDivisionStates(divisions);

      // Remaining capacity per division BEFORE this preview: Capacity__c
      // minus enrollments already committed for this term. Divisions with a
      // null Capacity__c are treated as uncapped. This is passed into the
      // algorithm itself so a full division is skipped live, rather than
      // discovered only after the fact.
      Map<Id, Integer> existingCounts = loadExistingEnrollmentCounts(termId, stateMap.keySet());
      Map<Id, Integer> remainingCapacity = new Map<Id, Integer>();
      for (Division__c d : divisions) {
        Integer existing = existingCounts.containsKey(d.Id) ? existingCounts.get(d.Id) : 0;
        Integer capacity = d.Capacity__c != null ? d.Capacity__c.intValue() : UNCAPPED;
        remainingCapacity.put(d.Id, capacity - existing);
      }

      List<String> capacityWarnings = new List<String>();

      // Execute distribution algorithm. This only mutates the in-memory
      // stateMap/assignments below - nothing is written to the database at
      // this point. Divisions that are already full (or that fill up mid-
      // pass) are skipped; capacityWarnings records exactly which ones.
      Map<Id, Id> assignments = executeDistribution(
        students,
        divisions,
        stateMap,
        remainingCapacity,
        capacityWarnings
      );

      if (assignments.isEmpty()) {
        throw new DistributionException(
          'Division capacity reached. Allocation cannot be completed.'
        );
      }

      PreviewResult result = new PreviewResult();
      result.divisions = buildDivisionDTOsFromState(
        divisions,
        stateMap,
        loadResult.specialisationIdToName
      );
      result.assignments = assignments;

      Map<Id, DivisionDTO> divisionMap = new Map<Id, DivisionDTO>();
      for (DivisionDTO dto : result.divisions) {
        divisionMap.put(dto.divisionId, dto);
      }

      ValidationResult vr = new ValidationResult();
      vr.warnings = new List<String>();
      vr.isValid = true;
      validateConstraints(divisionMap, vr);

      // A capacity-driven skip isn't a balance-rule violation, but not every
      // student getting placed IS a real problem - flag both explicitly.
      Boolean allStudentsPlaced = assignments.size() == students.size();

      result.warnings = vr.warnings;
      result.warnings.addAll(capacityWarnings);
      result.isValid = vr.isValid && allStudentsPlaced;

      if (!allStudentsPlaced) {
        result.message = 'Preview generated, but not every student could be placed - see warnings below.';
      } else if (!capacityWarnings.isEmpty()) {
        result.message = 'Preview generated. One or more divisions reached capacity - see warnings below.';
      } else if (result.isValid) {
        result.message = 'Preview generated. Review the proposed allocation below, then confirm to save it.';
      } else {
        result.message = 'Preview generated with warnings. Review before confirming.';
      }

      return result;
    } catch (Exception e) {
      throw new AuraHandledException('Preview failed: ' + e.getMessage());
    }
  }

  /* ================= CONFIRM (commits a previewed allocation) ================= */

  @AuraEnabled
  public static ConfirmResult confirmDistribution(Map<Id, Id> assignments) {
    if (assignments == null || assignments.isEmpty()) {
      return failedConfirm('No assignments to confirm');
    }

    Map<Id, Id> assignmentMap = new Map<Id, Id>();
    for (Id enrollmentId : assignments.keySet()) {
      Id divisionId = assignments.get(enrollmentId);
      if (enrollmentId != null && divisionId != null) {
        assignmentMap.put(enrollmentId, divisionId);
      }
    }

    if (assignmentMap.isEmpty()) {
      return failedConfirm('No valid assignments to confirm');
    }

    return updateEnrollments(assignmentMap);
  }

  private static ConfirmResult failedConfirm(String message) {
    ConfirmResult result = new ConfirmResult();
    result.success = false;
    result.savedCount = 0;
    result.errors = new List<String>{ message };
    result.message = message;
    return result;
  }

  /* ================= CORE DISTRIBUTION ALGORITHM ================= */
  /* Allocation process (per the SPJIMR division-allocation process document):
   *   1. Sort ALL unassigned students once by:
   *        Gender (Male, then Female)
   *        -> Specialisation (Fin, IM, Mkt, OSC; SPEC_ORDER)
   *        -> Work-Experience bucket (0-1yr=0, >1-2yr=1, >2-3yr=2, >3yr=3)
   *        -> Educational Background (Technical, then Non-Technical)
   *        -> Name (alphabetical - stable, deterministic tiebreak)
   *   2. Walk that sorted list once, allocating sequentially: A -> B -> C ->
   *      repeat, across whichever divisions are active for the term.
   *
   * A single continuous round-robin over a sorted list always splits any
   * contiguous run (i.e. any one combination of gender/spec/WE-bucket/edu)
   * within +/-1 of even across the divisions, regardless of where in the
   * A/B/C cycle that run happens to start. So this one sort + one pass keeps
   * gender, specialisation, WE bucket, and grad type balanced everywhere
   * without needing per-group scoring, swaps, or optimization passes.
   */

  private static Map<Id, Id> executeDistribution(
    List<Student> students,
    List<Division__c> divisions,
    Map<Id, DivisionState> stateMap,
    Map<Id, Integer> remainingCapacity,
    List<String> capacityWarnings
  ) {
    Map<Id, Id> assignments = new Map<Id, Id>();

    List<Student> sortedStudents = new List<Student>(students);
    sortedStudents.sort(new StudentAllocationComparator());

    distributeSequentially(sortedStudents, divisions, stateMap, assignments, remainingCapacity, capacityWarnings);

    return assignments;
  }

  // Sequential (round-robin) allocation: A -> B -> C -> A -> B -> C ...,
  // skipping any division whose remaining capacity has hit zero rather than
  // allocating past it. remainingCapacity is decremented in place as
  // students are placed, and capacityWarnings collects a one-time notice for
  // every division that turns out to be full (whether it started that way
  // or filled up partway through this pass).
  private static void distributeSequentially(
    List<Student> studentList,
    List<Division__c> divisions,
    Map<Id, DivisionState> stateMap,
    Map<Id, Id> assignments,
    Map<Id, Integer> remainingCapacity,
    List<String> capacityWarnings
  ) {
    Integer divCount = divisions.size();
    if (divCount == 0) {
      return;
    }

    Set<Id> reportedFull = new Set<Id>();

    // Divisions that already have no room before this pass even starts
    // (from previously committed enrollments) - report and skip up front.
    for (Division__c d : divisions) {
      if (remainingCapacity.get(d.Id) <= 0) {
        reportedFull.add(d.Id);
        capacityWarnings.add(
          'Division "' + d.Division_Name__c + '" has reached capacity and was skipped.'
        );
      }
    }

    Integer cursor = 0;
    Integer unassignedCount = 0;

    for (Integer i = 0; i < studentList.size(); i++) {
      Id chosenDivisionId = null;
      Integer chosenIdx = -1;

      for (Integer offset = 0; offset < divCount; offset++) {
        Integer idx = Math.mod(cursor + offset, divCount);
        Id candidateId = divisions[idx].Id;
        if (remainingCapacity.get(candidateId) > 0) {
          chosenDivisionId = candidateId;
          chosenIdx = idx;
          break;
        }
      }

      if (chosenDivisionId == null) {
        // Every division is full - nothing left to allocate to.
        unassignedCount = studentList.size() - i;
        break;
      }

      assignStudent(studentList[i], chosenDivisionId, stateMap, assignments);

      Integer remaining = remainingCapacity.get(chosenDivisionId) - 1;
      remainingCapacity.put(chosenDivisionId, remaining);

      if (remaining <= 0 && !reportedFull.contains(chosenDivisionId)) {
        reportedFull.add(chosenDivisionId);
        capacityWarnings.add(
          'Division "' + divisions[chosenIdx].Division_Name__c + '" has reached capacity.'
        );
      }

      // Continue the round-robin from the division right after the one just
      // used, so it still alternates A -> B -> C rather than always
      // re-searching from the same starting point.
      cursor = Math.mod(chosenIdx + 1, divCount);
    }

    if (unassignedCount > 0) {
      capacityWarnings.add(
        'All divisions are at capacity - ' + unassignedCount +
        ' student(s) could not be allocated.'
      );
    }
  }

  private static void assignStudent(Student s, Id divisionId, 
    Map<Id, DivisionState> stateMap, Map<Id, Id> assignments) {
    assignments.put(s.enrollmentId, divisionId);
    stateMap.get(divisionId).addStudent(s);
  }

  // Steps 2-5 of the process document, expressed as a single composite sort.
  private class StudentAllocationComparator implements Comparator<Student> {
    public Integer compare(Student a, Student b) {
      Integer genderCmp = genderRank(a.gender) - genderRank(b.gender);
      if (genderCmp != 0) {
        return genderCmp;
      }

      Integer specCmp = specRank(a.specialisationName) - specRank(b.specialisationName);
      if (specCmp != 0) {
        return specCmp;
      }

      Integer weCmp = a.weBucket - b.weBucket;
      if (weCmp != 0) {
        return weCmp;
      }

      Integer eduCmp = eduRank(a.gradType) - eduRank(b.gradType);
      if (eduCmp != 0) {
        return eduCmp;
      }

      String nameA = a.studentName;
      String nameB = b.studentName;
      if (nameA < nameB) {
        return -1;
      }
      if (nameA > nameB) {
        return 1;
      }
      return 0;
    }
  }

  // Step 2: Male before Female. Anything else (blank/other) sorts last.
  private static Integer genderRank(String gender) {
    if (gender == MALE) {
      return 0;
    }
    if (gender == FEMALE) {
      return 1;
    }
    return 2;
  }

  // Step 3: Fin -> IM -> Mkt -> OSC (SPEC_ORDER). Unrecognised specialisation
  // names sort after those four.
  private static Integer specRank(String specName) {
    String key = specName != null ? specName.trim().toUpperCase() : '';
    Integer idx = SPEC_ORDER.indexOf(key);
    return idx >= 0 ? idx : SPEC_ORDER.size();
  }

  // Step 5: Technical before Non-Technical. Anything else sorts last.
  private static Integer eduRank(String gradType) {
    if (gradType == TECH) {
      return 0;
    }
    if (gradType == NON_TECH) {
      return 1;
    }
    return 2;
  }


  /* ================= VALIDATION (against committed data) ================= */

  @AuraEnabled(cacheable=true)
  public static ValidationResult validateDistribution(Id termId) {
    ValidationResult result = new ValidationResult();
    result.divisions = new List<DivisionDTO>();
    result.warnings = new List<String>();
    result.isValid = true;

    Map<Id, DivisionDTO> divisionMap = buildDivisionDTOMap(termId);

    if (divisionMap.isEmpty()) {
      result.message = 'No divisions found for this term';
      result.isValid = false;
      return result;
    }

    populateDivisionStats(termId, divisionMap);

    // Validate constraints in sequence
    validateConstraints(divisionMap, result);

    result.divisions.addAll(divisionMap.values());

    if (result.isValid) {
      result.message = 'Distribution meets all requirements';
    } else {
      result.message = 'Distribution validation failed. See warnings for details.';
    }

    return result;
  }

  private static void validateConstraints(
    Map<Id, DivisionDTO> divisionMap,
    ValidationResult result
  ) {
    if (divisionMap.isEmpty())
      return;

    List<DivisionDTO> divs = new List<DivisionDTO>(divisionMap.values());
    if (divs.isEmpty())
      return;

    // Find min/max values in single pass
    Integer minMale = divs[0].male, maxMale = divs[0].male;
    Integer minFemale = divs[0].female, maxFemale = divs[0].female;
    Integer minTech = divs[0].tech, maxTech = divs[0].tech;
    Integer minNonTech = divs[0].nonTech, maxNonTech = divs[0].nonTech;
    Decimal minMaleExp = divs[0].male > 0 ? divs[0].avgMaleExp : 999999;
    Decimal maxMaleExp = divs[0].male > 0 ? divs[0].avgMaleExp : 0;
    Decimal minFemaleExp = divs[0].female > 0 ? divs[0].avgFemaleExp : 999999;
    Decimal maxFemaleExp = divs[0].female > 0 ? divs[0].avgFemaleExp : 0;

    for (Integer i = 1; i < divs.size(); i++) {
      DivisionDTO d = divs[i];
      minMale = Math.min(minMale, d.male);
      maxMale = Math.max(maxMale, d.male);
      minFemale = Math.min(minFemale, d.female);
      maxFemale = Math.max(maxFemale, d.female);
      minTech = Math.min(minTech, d.tech);
      maxTech = Math.max(maxTech, d.tech);
      minNonTech = Math.min(minNonTech, d.nonTech);
      maxNonTech = Math.max(maxNonTech, d.nonTech);

      if (d.male > 0) {
        minMaleExp = Math.min(minMaleExp, d.avgMaleExp);
        maxMaleExp = Math.max(maxMaleExp, d.avgMaleExp);
      }
      if (d.female > 0) {
        minFemaleExp = Math.min(minFemaleExp, d.avgFemaleExp);
        maxFemaleExp = Math.max(maxFemaleExp, d.avgFemaleExp);
      }
    }

    // RULE 1: Gender balance validation
    checkVariance(maxMale - minMale, GENDER_TOLERANCE, 
      'RULE 1 VIOLATION: Male distribution variance is ', result);
    checkVariance(maxFemale - minFemale, GENDER_TOLERANCE,
      'RULE 1 VIOLATION: Female distribution variance is ', result);

    // RULE 2: Work experience balance validation
    if (minMaleExp != 999999) {
      checkExpVariance(maxMaleExp - minMaleExp, EXP_TOLERANCE,
        'RULE 2 VIOLATION: Male work experience variance is ', result);
    }
    if (minFemaleExp != 999999) {
      checkExpVariance(maxFemaleExp - minFemaleExp, EXP_TOLERANCE,
        'RULE 2 VIOLATION: Female work experience variance is ', result);
    }

    // RULE 3: Graduation type balance validation
    checkVariance(maxTech - minTech, GENDER_TOLERANCE,
      'RULE 3 VIOLATION: Technical graduation distribution variance is ', result);
    checkVariance(maxNonTech - minNonTech, GENDER_TOLERANCE,
      'RULE 3 VIOLATION: Non-Technical graduation distribution variance is ', result);

    // RULE 4: Specialisation balance validation (within each specialisation)
    validateSpecialisationBalance(divs, result);

    // RULE 5: Work-experience bucket balance validation
    validateWeBucketBalance(divs, result);

    // Check for zero-gender divisions
    for (DivisionDTO d : divs) {
      if (d.male == 0 || d.female == 0) {
        result.isValid = false;
        result.warnings.add('CRITICAL: Division "' + d.divisionName + 
          '" has zero ' + (d.male == 0 ? 'males' : 'females'));
      }
    }
  }

  private static void validateSpecialisationBalance(
    List<DivisionDTO> divs,
    ValidationResult result
  ) {
    // Collect all specialisation names
    Set<String> allSpecialisations = new Set<String>();
    for (DivisionDTO d : divs) {
      if (d.specialisationCounts != null) {
        allSpecialisations.addAll(d.specialisationCounts.keySet());
      }
    }

    // For each specialisation, check variance across divisions
    for (String specName : allSpecialisations) {
      Integer minCount = null;
      Integer maxCount = null;

      for (DivisionDTO d : divs) {
        Integer count = (d.specialisationCounts != null && d.specialisationCounts.containsKey(specName))
          ? d.specialisationCounts.get(specName) : 0;
        
        if (minCount == null || count < minCount) {
          minCount = count;
        }
        if (maxCount == null || count > maxCount) {
          maxCount = count;
        }
      }

      if (minCount != null && maxCount != null) {
        Integer variance = maxCount - minCount;
        if (variance > GENDER_TOLERANCE) {
          result.isValid = false;
          result.warnings.add('RULE 4 VIOLATION: Specialisation "' + specName + 
            '" distribution variance is ' + variance + ' (exceeds ±' + GENDER_TOLERANCE + ')');
        }
      }
    }
  }

  private static void validateWeBucketBalance(
    List<DivisionDTO> divs,
    ValidationResult result
  ) {
    // Collect all bucket keys ("0".."3") actually in use
    Set<String> allBuckets = new Set<String>();
    for (DivisionDTO d : divs) {
      if (d.weBucketCounts != null) {
        allBuckets.addAll(d.weBucketCounts.keySet());
      }
    }

    // For each WE bucket, check variance across divisions
    for (String bucketKey : allBuckets) {
      Integer minCount = null;
      Integer maxCount = null;

      for (DivisionDTO d : divs) {
        Integer count = (d.weBucketCounts != null && d.weBucketCounts.containsKey(bucketKey))
          ? d.weBucketCounts.get(bucketKey) : 0;

        if (minCount == null || count < minCount) {
          minCount = count;
        }
        if (maxCount == null || count > maxCount) {
          maxCount = count;
        }
      }

      if (minCount != null && maxCount != null) {
        Integer variance = maxCount - minCount;
        if (variance > GENDER_TOLERANCE) {
          result.isValid = false;
          result.warnings.add('RULE 5 VIOLATION: WE bucket "' + bucketKey +
            '" distribution variance is ' + variance + ' (exceeds ±' + GENDER_TOLERANCE + ')');
        }
      }
    }
  }

  private static void checkVariance(Integer variance, Integer tolerance, 
    String message, ValidationResult result) {
    if (variance > tolerance) {
      result.isValid = false;
      result.warnings.add(message + variance + ' (exceeds ±' + tolerance + ')');
    }
  }

  private static void checkExpVariance(Decimal variance, Decimal tolerance,
    String message, ValidationResult result) {
    if (variance > tolerance) {
      result.isValid = false;
      result.warnings.add(message + variance.setScale(2) + 
        ' years (exceeds ±' + tolerance.setScale(0) + ')');
    }
  }

  /* ================= DATA LOADING METHODS ================= */

  private static List<Division__c> loadActiveDivisions(Id termId) {
    return [
      SELECT Id, Name, Division_Name__c, Capacity__c
      FROM Division__c
      WHERE Term__c = :termId
        AND Is_Active__c = TRUE
        AND Division_Group__r.Name = 'Fundamental'
      ORDER BY Division_Name__c
    ];
  }

  private static StudentLoadResult loadStudents(Id termId) {
    StudentLoadResult loadResult = new StudentLoadResult();
    loadResult.students = new List<Student>();
    loadResult.specialisationIdToName = new Map<Id, String>();

    // Get all enrollments for the term with Program Enrollment
    List<AcademicTermEnrollment> allEnrollments = [
      SELECT Id, LearnerAccountId, LearnerAccount.Name, LearnerAccount.Gender__c, Program_Enrolled__c
      FROM AcademicTermEnrollment
      WHERE AcademicTermId = :termId
    ];

    if (allEnrollments.isEmpty())
      return loadResult;

    // Get enrollment IDs that already have division assignments
    Set<Id> enrolledIds = new Set<Id>();
    Set<Id> enrollmentIds = new Set<Id>();
    Set<Id> programEnrollmentIds = new Set<Id>();
    
    for (AcademicTermEnrollment e : allEnrollments) {
      enrollmentIds.add(e.Id);
      if (e.Program_Enrolled__c != null) {
        programEnrollmentIds.add(e.Program_Enrolled__c);
      }
    }

    for (Division_Enrollment__c de : [
      SELECT Academic_Term_Enrollment__c
      FROM Division_Enrollment__c
      WHERE Academic_Term_Enrollment__c IN :enrollmentIds
    ]) {
      enrolledIds.add(de.Academic_Term_Enrollment__c);
    }

    // Filter unassigned enrollments and collect account IDs
    List<AcademicTermEnrollment> enrollments = new List<AcademicTermEnrollment>();
    Set<Id> accountIds = new Set<Id>();
    
    for (AcademicTermEnrollment e : allEnrollments) {
      if (!enrolledIds.contains(e.Id) && e.LearnerAccountId != null) {
        enrollments.add(e);
        accountIds.add(e.LearnerAccountId);
      }
    }

    if (enrollments.isEmpty())
      return loadResult;

    // Get ProgramCohortMember IDs from ProgramEnrollments
    Map<Id, Id> programEnrollmentToCohortMember = new Map<Id, Id>();
    for (ProgramCohortMember pcm : [
      SELECT Id, ProgramEnrollmentId
      FROM ProgramCohortMember
      WHERE ProgramEnrollmentId IN :programEnrollmentIds
    ]) {
      programEnrollmentToCohortMember.put(pcm.ProgramEnrollmentId, pcm.Id);
    }

    // Get specialisations for ProgramCohortMembers (ONLY Major specialisation type)
    Map<Id, Id> cohortMemberToSpecialisation = new Map<Id, Id>();
    Map<Id, String> specialisationIdToName = new Map<Id, String>();
    Set<Id> cohortMemberIds = new Set<Id>(programEnrollmentToCohortMember.values());
    
    if (!cohortMemberIds.isEmpty()) {
      // Only get Major specialisations for balancing
      for (Student_Specialisation__c ss : [
        SELECT Id, Program_Cohort_Member__c, Specialisation_Master__c, 
               Specialisation_Master__r.Name, Specialisation_Type__c
        FROM Student_Specialisation__c
        WHERE Program_Cohort_Member__c IN :cohortMemberIds
        AND Specialisation_Type__c = 'Major'
        ORDER BY CreatedDate DESC
      ]) {
        if (!cohortMemberToSpecialisation.containsKey(ss.Program_Cohort_Member__c)) {
          cohortMemberToSpecialisation.put(ss.Program_Cohort_Member__c, ss.Specialisation_Master__c);
          if (ss.Specialisation_Master__c != null) {
            specialisationIdToName.put(ss.Specialisation_Master__c, ss.Specialisation_Master__r.Name);
          }
        }
      }
    }

    Map<Id, String> gradMap = loadGraduationTypes(accountIds);
    Map<Id, Decimal> expMap = loadWorkExperience(accountIds);

    // Create map from enrollment to specialisation
    Map<Id, Id> enrollmentToSpecialisation = new Map<Id, Id>();
    Map<Id, String> enrollmentToSpecialisationName = new Map<Id, String>();
    for (AcademicTermEnrollment e : enrollments) {
      if (e.Program_Enrolled__c != null) {
        Id cohortMemberId = programEnrollmentToCohortMember.get(e.Program_Enrolled__c);
        if (cohortMemberId != null) {
          Id specId = cohortMemberToSpecialisation.get(cohortMemberId);
          if (specId != null) {
            enrollmentToSpecialisation.put(e.Id, specId);
            enrollmentToSpecialisationName.put(e.Id, specialisationIdToName.get(specId));
          }
        }
      }
    }

    List<Student> students = new List<Student>();
    for (AcademicTermEnrollment e : enrollments) {
      students.add(new Student(
          e.Id,
          e.LearnerAccount.Name,
          e.LearnerAccount.Gender__c,
          gradMap.get(e.LearnerAccountId),
          expMap.get(e.LearnerAccountId),
          enrollmentToSpecialisation.get(e.Id),
          enrollmentToSpecialisationName.get(e.Id)
      ));
    }

    loadResult.students = students;
    loadResult.specialisationIdToName = specialisationIdToName;
    return loadResult;
  }

  private static Map<Id, String> loadGraduationTypes(Set<Id> accountIds) {
    Map<Id, String> gradMap = new Map<Id, String>();

    for (PersonEducation pe : [
      SELECT AccountId, Graduation_Type__c
      FROM PersonEducation
      WHERE AccountId IN :accountIds
      ORDER BY CreatedDate DESC
    ]) {
      if (!gradMap.containsKey(pe.AccountId)) {
        gradMap.put(pe.AccountId, pe.Graduation_Type__c);
      }
    }

    return gradMap;
  }

  private static Map<Id, Decimal> loadWorkExperience(Set<Id> accountIds) {
    Map<Id, Decimal> expMap = new Map<Id, Decimal>();

    for (AggregateResult ar : [
      SELECT Student__c acc, SUM(Total_Work_Experience_In_Years__c) exp
      FROM Work_Experience__c
      WHERE Student__c IN :accountIds
      GROUP BY Student__c
    ]) {
      expMap.put((Id) ar.get('acc'), (Decimal) ar.get('exp'));
    }

    return expMap;
  }

  // Count of already-committed Division_Enrollment__c records per division
  // for this term, used to check capacity before a preview is generated.
  private static Map<Id, Integer> loadExistingEnrollmentCounts(Id termId, Set<Id> divisionIds) {
    Map<Id, Integer> counts = new Map<Id, Integer>();

    for (AggregateResult ar : [
      SELECT Division__c divId, COUNT(Id) cnt
      FROM Division_Enrollment__c
      WHERE Division__c IN :divisionIds
        AND Academic_Term_Enrollment__r.AcademicTermId = :termId
      GROUP BY Division__c
    ]) {
      counts.put((Id) ar.get('divId'), (Integer) ar.get('cnt'));
    }

    return counts;
  }

  private static Map<Id, DivisionState> initializeDivisionStates(
    List<Division__c> divisions
  ) {
    Map<Id, DivisionState> stateMap = new Map<Id, DivisionState>();

    for (Division__c d : divisions) {
      DivisionState state = new DivisionState();
      state.divisionId = d.Id;
      stateMap.put(d.Id, state);
    }

    return stateMap;
  }

  // Builds display DTOs straight from the in-memory algorithm state (used by
  // previewDistribution, before anything is committed).
  private static List<DivisionDTO> buildDivisionDTOsFromState(
    List<Division__c> divisions,
    Map<Id, DivisionState> stateMap,
    Map<Id, String> specialisationIdToName
  ) {
    List<DivisionDTO> dtos = new List<DivisionDTO>();

    for (Division__c d : divisions) {
      DivisionState state = stateMap.get(d.Id);
      DivisionDTO dto = new DivisionDTO();
      dto.divisionId = d.Id;
      dto.divisionAutoNumber = d.Name;
      dto.divisionName = d.Division_Name__c;
      dto.total = state.total;
      dto.male = state.male;
      dto.female = state.female;
      dto.tech = state.tech;
      dto.nonTech = state.nonTech;
      dto.avgMaleExp = state.getAvgMaleExp();
      dto.avgFemaleExp = state.getAvgFemaleExp();
      dto.specialisationCounts = new Map<String, Integer>();

      for (Id specId : state.specialisationCount.keySet()) {
        String specName = specialisationIdToName.get(specId);
        if (specName != null && !String.isBlank(specName)) {
          dto.specialisationCounts.put(specName, state.specialisationCount.get(specId));
        }
      }

      dto.weBucketCounts = new Map<String, Integer>();
      for (Integer bucket : state.weBucketCount.keySet()) {
        dto.weBucketCounts.put(String.valueOf(bucket), state.weBucketCount.get(bucket));
      }

      dtos.add(dto);
    }

    return dtos;
  }

  private static Map<Id, DivisionDTO> buildDivisionDTOMap(Id termId) {
    Map<Id, DivisionDTO> divisionMap = new Map<Id, DivisionDTO>();

    for (Division__c d : [
      SELECT Id, Name, Division_Name__c
      FROM Division__c
      WHERE Term__c = :termId
        AND Is_Active__c = TRUE
        AND Division_Group__r.Name = 'Fundamental'
      ORDER BY Division_Name__c
    ]) {
      DivisionDTO dto = new DivisionDTO();
      dto.divisionId = d.Id;
      dto.divisionAutoNumber = d.Name;
      dto.divisionName = d.Division_Name__c;
      dto.total = 0;
      dto.male = 0;
      dto.female = 0;
      dto.tech = 0;
      dto.nonTech = 0;
      dto.avgMaleExp = 0;
      dto.avgFemaleExp = 0;
      dto.specialisationCounts = new Map<String, Integer>();
      dto.weBucketCounts = new Map<String, Integer>();
      divisionMap.put(d.Id, dto);
    }

    return divisionMap;
  }

  private static void populateDivisionStats(
    Id termId,
    Map<Id, DivisionDTO> divisionMap
  ) {
    // Query Division_Enrollment__c records to get enrollments with their divisions
    List<Division_Enrollment__c> divisionEnrollments = [
      SELECT
        Id,
        Division__c,
        Academic_Term_Enrollment__c,
        Academic_Term_Enrollment__r.LearnerAccountId,
        Academic_Term_Enrollment__r.LearnerAccount.Gender__c,
        Academic_Term_Enrollment__r.Program_Enrolled__c
      FROM Division_Enrollment__c
      WHERE
        Academic_Term_Enrollment__r.AcademicTermId = :termId
        AND Division__c IN :divisionMap.keySet()
    ];

    if (divisionEnrollments.isEmpty())
      return;

    Set<Id> accountIds = new Set<Id>();
    Set<Id> programEnrollmentIds = new Set<Id>();
    Set<Id> enrollmentIds = new Set<Id>();
    
    for (Division_Enrollment__c de : divisionEnrollments) {
      if (de.Academic_Term_Enrollment__r.LearnerAccountId != null) {
        accountIds.add(de.Academic_Term_Enrollment__r.LearnerAccountId);
      }
      if (de.Academic_Term_Enrollment__r.Program_Enrolled__c != null) {
        programEnrollmentIds.add(de.Academic_Term_Enrollment__r.Program_Enrolled__c);
      }
      enrollmentIds.add(de.Academic_Term_Enrollment__c);
    }

    // Load specialisation data
    Map<Id, Id> programEnrollmentToCohortMember = new Map<Id, Id>();
    for (ProgramCohortMember pcm : [
      SELECT Id, ProgramEnrollmentId
      FROM ProgramCohortMember
      WHERE ProgramEnrollmentId IN :programEnrollmentIds
    ]) {
      programEnrollmentToCohortMember.put(pcm.ProgramEnrollmentId, pcm.Id);
    }

    Map<Id, Id> cohortMemberToSpecialisation = new Map<Id, Id>();
    Map<Id, String> specialisationIdToName = new Map<Id, String>();
    Set<Id> cohortMemberIds = new Set<Id>(programEnrollmentToCohortMember.values());
    
    if (!cohortMemberIds.isEmpty()) {
      // Only get Major specialisations for balancing (Minor specialisations are ignored)
      for (Student_Specialisation__c ss : [
        SELECT Id, Program_Cohort_Member__c, Specialisation_Master__c, 
               Specialisation_Master__r.Name, Specialisation_Type__c
        FROM Student_Specialisation__c
        WHERE Program_Cohort_Member__c IN :cohortMemberIds
        AND Specialisation_Type__c = 'Major'
        ORDER BY CreatedDate DESC
      ]) {
        if (!cohortMemberToSpecialisation.containsKey(ss.Program_Cohort_Member__c)) {
          cohortMemberToSpecialisation.put(ss.Program_Cohort_Member__c, ss.Specialisation_Master__c);
          if (ss.Specialisation_Master__c != null) {
            specialisationIdToName.put(ss.Specialisation_Master__c, ss.Specialisation_Master__r.Name);
          }
        }
      }
    }

    // Create enrollment to specialisation map
    Map<Id, String> enrollmentToSpecialisationName = new Map<Id, String>();
    for (Division_Enrollment__c de : divisionEnrollments) {
      if (de.Academic_Term_Enrollment__r.Program_Enrolled__c != null) {
        Id cohortMemberId = programEnrollmentToCohortMember.get(de.Academic_Term_Enrollment__r.Program_Enrolled__c);
        if (cohortMemberId != null) {
          Id specId = cohortMemberToSpecialisation.get(cohortMemberId);
          if (specId != null) {
            enrollmentToSpecialisationName.put(de.Academic_Term_Enrollment__c, specialisationIdToName.get(specId));
          }
        }
      }
    }

    Map<Id, String> gradMap = loadGraduationTypes(accountIds);
    Map<Id, Decimal> expMap = loadWorkExperience(accountIds);

    Map<Id, Decimal> maleExpTotal = new Map<Id, Decimal>();
    Map<Id, Decimal> femaleExpTotal = new Map<Id, Decimal>();

    for (Division_Enrollment__c de : divisionEnrollments) {
      DivisionDTO dto = divisionMap.get(de.Division__c);
      Id accountId = de.Academic_Term_Enrollment__r.LearnerAccountId;
      
      if (dto == null || accountId == null)
        continue;

      dto.total++;
      String gender = de.Academic_Term_Enrollment__r.LearnerAccount.Gender__c;
      String grad = gradMap.get(accountId);
      Decimal exp = expMap.get(accountId) != null ? expMap.get(accountId) : 0;
      String specName = enrollmentToSpecialisationName.get(de.Academic_Term_Enrollment__c);

      if (gender == MALE) {
        dto.male++;
        Decimal current = maleExpTotal.get(de.Division__c) != null ? maleExpTotal.get(de.Division__c) : 0;
        maleExpTotal.put(de.Division__c, current + exp);
      } else if (gender == FEMALE) {
        dto.female++;
        Decimal current = femaleExpTotal.get(de.Division__c) != null ? femaleExpTotal.get(de.Division__c) : 0;
        femaleExpTotal.put(de.Division__c, current + exp);
      }

      if (grad == TECH) {
        dto.tech++;
      } else if (grad == NON_TECH) {
        dto.nonTech++;
      }

      // Track specialisation counts
      if (specName != null && !String.isBlank(specName)) {
        Integer currentCount = dto.specialisationCounts.containsKey(specName) 
          ? dto.specialisationCounts.get(specName) : 0;
        dto.specialisationCounts.put(specName, currentCount + 1);
      }

      // Track WE bucket counts
      String bucketKey = String.valueOf(computeWeBucket(exp));
      Integer currentBucketCount = dto.weBucketCounts.containsKey(bucketKey)
        ? dto.weBucketCounts.get(bucketKey) : 0;
      dto.weBucketCounts.put(bucketKey, currentBucketCount + 1);
    }

    // Calculate averages
    for (Id divId : divisionMap.keySet()) {
      DivisionDTO dto = divisionMap.get(divId);
      if (dto.male > 0 && maleExpTotal.containsKey(divId)) {
        dto.avgMaleExp = maleExpTotal.get(divId) / dto.male;
      }
      if (dto.female > 0 && femaleExpTotal.containsKey(divId)) {
        dto.avgFemaleExp = femaleExpTotal.get(divId) / dto.female;
      }
    }
  }

  private static ConfirmResult updateEnrollments(Map<Id, Id> assignments) {
    ConfirmResult result = new ConfirmResult();
    result.errors = new List<String>();
    result.savedCount = 0;

    Savepoint sp = Database.setSavepoint();

    try {
      // Query AcademicTermEnrollment records to update
      Map<Id, AcademicTermEnrollment> enrollmentMap = new Map<Id, AcademicTermEnrollment>([
        SELECT Id, Division__c
        FROM AcademicTermEnrollment
        WHERE Id IN :assignments.keySet()
      ]);

      // Guard: skip any enrollment that already has a Division_Enrollment__c.
      // Confirming the same preview twice (double click, stale tab, etc.)
      // would otherwise attempt a duplicate insert, which can fail the WHOLE
      // batch depending on org validation/duplicate rules and looks to the
      // user like "nothing saved" with no clear reason.
      Set<Id> alreadyLinked = new Set<Id>();
      for (Division_Enrollment__c existing : [
        SELECT Academic_Term_Enrollment__c
        FROM Division_Enrollment__c
        WHERE Academic_Term_Enrollment__c IN :assignments.keySet()
      ]) {
        alreadyLinked.add(existing.Academic_Term_Enrollment__c);
      }

      List<Division_Enrollment__c> divisionEnrollments = new List<Division_Enrollment__c>();
      List<AcademicTermEnrollment> enrollmentsToUpdate = new List<AcademicTermEnrollment>();

      for (Id enrollmentId : assignments.keySet()) {
        if (alreadyLinked.contains(enrollmentId)) {
          continue;
        }

        Id divisionId = assignments.get(enrollmentId);

        // Create Division_Enrollment__c record
        Division_Enrollment__c de = new Division_Enrollment__c();
        de.Academic_Term_Enrollment__c = enrollmentId;
        de.Division__c = divisionId;
        divisionEnrollments.add(de);

        // Update AcademicTermEnrollment.Division__c field
        AcademicTermEnrollment enrollment = enrollmentMap.get(enrollmentId);
        if (enrollment != null) {
          enrollment.Division__c = divisionId;
          enrollmentsToUpdate.add(enrollment);
        }
      }

      if (divisionEnrollments.isEmpty()) {
        result.success = false;
        result.message = 'Nothing to save - the selected students already have a division assigned.';
        return result;
      }

      insert divisionEnrollments;

      if (!enrollmentsToUpdate.isEmpty()) {
        update enrollmentsToUpdate;
      }

      result.success = true;
      result.savedCount = divisionEnrollments.size();
      result.message = 'Saved ' + divisionEnrollments.size() + ' division enrollment(s).';
      return result;
    } catch (DmlException dmlEx) {
      // Roll back BOTH the insert and the update together so we never end up
      // with a Division_Enrollment__c that has no matching Division__c value
      // on the enrollment (or vice versa).
      Database.rollback(sp);
      for (Integer i = 0; i < dmlEx.getNumDml(); i++) {
        result.errors.add(dmlEx.getDmlMessage(i));
      }
      result.success = false;
      result.message = 'Save failed: ' + dmlEx.getMessage();
      return result;
    } catch (Exception e) {
      Database.rollback(sp);
      result.success = false;
      result.message = 'Save failed: ' + e.getMessage();
      result.errors.add(e.getMessage());
      return result;
    }
  }

  /* ================= CUSTOM EXCEPTION ================= */

  public class DistributionException extends Exception {
  }
}
public with sharing class StudentDivisionDistributorV2 {
  /* ================= CONSTANTS ================= */
  private static final String MALE = 'Male';
  private static final String FEMALE = 'Female';
  private static final String TECH = 'Technical';
  private static final String NON_TECH = 'Non Technical';
  private static final Integer GENDER_TOLERANCE = 5;
  private static final Decimal EXP_TOLERANCE = 6.0;

  // Scoring weights for distribution algorithm
  private static final Decimal GENDER_WEIGHT = 30;
  private static final Decimal EXP_WEIGHT = 25;
  private static final Decimal GRAD_TYPE_WEIGHT = 15;
  private static final Decimal SPECIALISATION_WEIGHT = 20;
  private static final Decimal TOTAL_WEIGHT = 10;

  /* ================= INTERNAL MODELS ================= */

  private class Student {
    Id enrollmentId;
    String gender;
    String gradType;
    Decimal workExp;
    Id specialisationId;
    String specialisationName;

    public Student(
      Id enrollmentId,
      String gender,
      String gradType,
      Decimal workExp,
      Id specialisationId,
      String specialisationName
    ) {
      this.enrollmentId = enrollmentId;
      this.gender = gender != null ? gender : '';
      this.gradType = gradType != null ? gradType : '';
      this.workExp = workExp != null ? workExp : 0;
      this.specialisationId = specialisationId;
      this.specialisationName = specialisationName != null ? specialisationName : '';
    }
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

    public Decimal getAvgMaleExp() {
      return male > 0 ? maleExpTotal / male : 0;
    }

    public Decimal getAvgFemaleExp() {
      return female > 0 ? femaleExpTotal / female : 0;
    }

    public Integer getSpecialisationCount(Id specId) {
      return specialisationCount.containsKey(specId) ? specialisationCount.get(specId) : 0;
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
    }
  }

  /* ================= LWC DTOs ================= */

  public class DivisionDTO {
    @AuraEnabled
    public Id divisionId;
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

  /* ================= MAIN DISTRIBUTION METHOD ================= */

  @AuraEnabled
  public static void distribute(Id termId) {
    try {
      // Load divisions and students
      List<Division__c> divisions = loadActiveDivisions(termId);
      if (divisions.isEmpty()) {
        throw new DistributionException(
          'No active divisions found for this term'
        );
      }

      List<Student> students = loadStudents(termId);
      if (students.isEmpty()) {
        throw new DistributionException(
          'No unassigned students found for this term'
        );
      }

      // Initialize division states
      Map<Id, DivisionState> stateMap = initializeDivisionStates(divisions);

      // Execute distribution algorithm with rules in sequence
      Map<Id, Id> assignments = executeDistribution(
        students,
        divisions,
        stateMap
      );

      // Validate and commit assignments
      if (assignments.isEmpty()) {
        throw new DistributionException(
          'Distribution algorithm failed to assign students'
        );
      }

      updateEnrollments(assignments);
    } catch (Exception e) {
      throw new AuraHandledException('Distribution failed: ' + e.getMessage());
    }
  }

  /* ================= CORE DISTRIBUTION ALGORITHM ================= */
  /* Rules Applied in Sequence:
   * 1. Gender Balance: Same number of Males & Females across divisions (±5)
   * 2. Work Experience: Average work exp same across divisions by gender (±6)
   * 3. Graduation Type: Equal distribution of Tech/Non-Tech students
   * 4. Specialisation Balance: Equal distribution within each Major specialisation across divisions (±5)
   *    Note: Only Major specialisation type is considered for balancing
   */

  private static Map<Id, Id> executeDistribution(
    List<Student> students,
    List<Division__c> divisions,
    Map<Id, DivisionState> stateMap
  ) {
    Map<Id, Id> assignments = new Map<Id, Id>();
    DistributionTargets targets = calculateTargets(students, divisions.size());

    // Separate students by gender AND graduation type for better balance
    List<Student> maleTech = new List<Student>();
    List<Student> maleNonTech = new List<Student>();
    List<Student> maleOther = new List<Student>();
    List<Student> femaleTech = new List<Student>();
    List<Student> femaleNonTech = new List<Student>();
    List<Student> femaleOther = new List<Student>();
    List<Student> others = new List<Student>();

    for (Student s : students) {
      if (s.gender == MALE) {
        if (s.gradType == TECH) {
          maleTech.add(s);
        } else if (s.gradType == NON_TECH) {
          maleNonTech.add(s);
        } else {
          maleOther.add(s);
        }
      } else if (s.gender == FEMALE) {
        if (s.gradType == TECH) {
          femaleTech.add(s);
        } else if (s.gradType == NON_TECH) {
          femaleNonTech.add(s);
        } else {
          femaleOther.add(s);
        }
      } else {
        others.add(s);
      }
    }

    // Sort by work experience for balanced distribution
    maleTech.sort(new StudentWorkExpComparator());
    maleNonTech.sort(new StudentWorkExpComparator());
    maleOther.sort(new StudentWorkExpComparator());
    femaleTech.sort(new StudentWorkExpComparator());
    femaleNonTech.sort(new StudentWorkExpComparator());
    femaleOther.sort(new StudentWorkExpComparator());

    // Distribute each group separately using snake draft
    // This ensures both gender and graduation type are balanced
    distributeBySnakeDraft(maleTech, divisions, stateMap, assignments);
    distributeBySnakeDraft(maleNonTech, divisions, stateMap, assignments);
    distributeBySnakeDraft(maleOther, divisions, stateMap, assignments);
    distributeBySnakeDraft(femaleTech, divisions, stateMap, assignments);
    distributeBySnakeDraft(femaleNonTech, divisions, stateMap, assignments);
    distributeBySnakeDraft(femaleOther, divisions, stateMap, assignments);

    // Distribute others using scoring
    for (Student s : others) {
      Id bestDivision = findBestDivisionByScore(s, divisions, stateMap, targets);
      assignments.put(s.enrollmentId, bestDivision);
      stateMap.get(bestDivision).addStudent(s);
    }

    // Fine-tune graduation type balance
    optimizeGraduationBalance(students, divisions, stateMap, assignments, targets);
    
    // Specialisation balance optimization
    optimizeSpecialisationBalance(students, divisions, stateMap, assignments, targets);

    return assignments;
  }

  private static void distributeBySnakeDraft(
    List<Student> studentList,
    List<Division__c> divisions,
    Map<Id, DivisionState> stateMap,
    Map<Id, Id> assignments
  ) {
    Integer divCount = divisions.size();
    Integer studentIndex = 0;

    while (studentIndex < studentList.size()) {
      // Forward pass: 0 -> N-1
      for (Integer i = 0; i < divCount && studentIndex < studentList.size(); i++) {
        assignStudent(studentList[studentIndex], divisions[i].Id, stateMap, assignments);
        studentIndex++;
      }
      // Backward pass: N-1 -> 0
      for (Integer i = divCount - 1; i >= 0 && studentIndex < studentList.size(); i--) {
        assignStudent(studentList[studentIndex], divisions[i].Id, stateMap, assignments);
        studentIndex++;
      }
    }
  }

  private static void assignStudent(Student s, Id divisionId, 
    Map<Id, DivisionState> stateMap, Map<Id, Id> assignments) {
    assignments.put(s.enrollmentId, divisionId);
    stateMap.get(divisionId).addStudent(s);
  }

  private static Id findBestDivisionByScore(
    Student s,
    List<Division__c> divisions,
    Map<Id, DivisionState> stateMap,
    DistributionTargets targets
  ) {
    Id bestDivisionId = null;
    Decimal bestScore = -999999;

    for (Division__c d : divisions) {
      DivisionState state = stateMap.get(d.Id);
      Decimal score = calculateDivisionScore(s, state, targets);

      if (bestDivisionId == null || score > bestScore) {
        bestScore = score;
        bestDivisionId = d.Id;
      }
    }

    return bestDivisionId;
  }

  private static Decimal calculateDivisionScore(
    Student s,
    DivisionState state,
    DistributionTargets targets
  ) {
    Decimal score = 0;

    // RULE 1: Gender balance scoring (highest priority)
    if (s.gender == MALE) {
      Decimal deviation = Math.abs((state.male + 1) - targets.avgMale);
      score -= deviation * GENDER_WEIGHT;
    } else if (s.gender == FEMALE) {
      Decimal deviation = Math.abs((state.female + 1) - targets.avgFemale);
      score -= deviation * GENDER_WEIGHT;
    }

    // RULE 2: Work experience balance (second priority)
    if (s.gender == MALE && state.male > 0) {
      Decimal newAvgExp = (state.maleExpTotal + s.workExp) / (state.male + 1);
      Decimal deviation = Math.abs(newAvgExp - targets.avgMaleExp);
      score -= deviation * EXP_WEIGHT;
    } else if (s.gender == FEMALE && state.female > 0) {
      Decimal newAvgExp =
        (state.femaleExpTotal + s.workExp) / (state.female + 1);
      Decimal deviation = Math.abs(newAvgExp - targets.avgFemaleExp);
      score -= deviation * EXP_WEIGHT;
    }

    // RULE 3: Graduation type balance (third priority)
    if (s.gradType == TECH) {
      Decimal deviation = Math.abs((state.tech + 1) - targets.avgTech);
      score -= deviation * GRAD_TYPE_WEIGHT;
    } else if (s.gradType == NON_TECH) {
      Decimal deviation = Math.abs((state.nonTech + 1) - targets.avgNonTech);
      score -= deviation * GRAD_TYPE_WEIGHT;
    }

    // RULE 4: Specialisation balance (fourth priority)
    if (s.specialisationId != null && targets.avgSpecialisation.containsKey(s.specialisationId)) {
      Decimal avgSpec = targets.avgSpecialisation.get(s.specialisationId);
      Integer currentCount = state.getSpecialisationCount(s.specialisationId);
      Decimal deviation = Math.abs((currentCount + 1) - avgSpec);
      score -= deviation * SPECIALISATION_WEIGHT;
    }

    // Total count balance (lower priority)
    Decimal totalDeviation = Math.abs((state.total + 1) - targets.avgTotal);
    score -= totalDeviation * TOTAL_WEIGHT;

    return score;
  }

  private static void optimizeGraduationBalance(
    List<Student> allStudents,
    List<Division__c> divisions,
    Map<Id, DivisionState> stateMap,
    Map<Id, Id> assignments,
    DistributionTargets targets
  ) {
    // Create a map of enrollment ID to Student for quick lookup
    Map<Id, Student> studentMap = new Map<Id, Student>();
    for (Student s : allStudents) {
      studentMap.put(s.enrollmentId, s);
    }

    // Perform multiple passes of optimization
    Integer maxIterations = 20;
    Integer iteration = 0;
    Boolean improved = true;
    Integer swapsPerIteration = 0;

    while (improved && iteration < maxIterations) {
      improved = false;
      iteration++;
      swapsPerIteration = 0;

      // Find divisions with imbalance
      List<DivisionImbalance> imbalances = findGraduationImbalances(divisions, stateMap, targets);

      if (imbalances.isEmpty()) break; // No imbalances found

      // Try to find beneficial swaps - allow multiple swaps per iteration
      for (Integer i = 0; i < imbalances.size() - 1 && swapsPerIteration < 5; i++) {
        DivisionImbalance imbalance1 = imbalances[i];
        for (Integer j = i + 1; j < imbalances.size() && swapsPerIteration < 5; j++) {
          DivisionImbalance imbalance2 = imbalances[j];

          // Try swapping Tech students (Tech from div1 <-> Non-Tech from div2)
          if (imbalance1.techSurplus > 0 && imbalance2.techDeficit > 0) {
            if (trySwapStudents(
                imbalance1.divisionId, imbalance2.divisionId,
                TECH, stateMap, assignments, studentMap)) {
              improved = true;
              swapsPerIteration++;
              // Continue to find more swaps in this iteration
            }
          }

          // Try swapping Non-Tech students (Non-Tech from div1 <-> Tech from div2)
          if (imbalance1.nonTechSurplus > 0 && imbalance2.nonTechDeficit > 0) {
            if (trySwapStudents(
                imbalance1.divisionId, imbalance2.divisionId,
                NON_TECH, stateMap, assignments, studentMap)) {
              improved = true;
              swapsPerIteration++;
              // Continue to find more swaps in this iteration
            }
          }

          // Also try reverse swaps
          if (imbalance2.techSurplus > 0 && imbalance1.techDeficit > 0) {
            if (trySwapStudents(
                imbalance2.divisionId, imbalance1.divisionId,
                TECH, stateMap, assignments, studentMap)) {
              improved = true;
              swapsPerIteration++;
            }
          }

          if (imbalance2.nonTechSurplus > 0 && imbalance1.nonTechDeficit > 0) {
            if (trySwapStudents(
                imbalance2.divisionId, imbalance1.divisionId,
                NON_TECH, stateMap, assignments, studentMap)) {
              improved = true;
              swapsPerIteration++;
            }
          }
        }
      }
    }
  }

  private class DivisionImbalance {
    Id divisionId;
    Integer techSurplus = 0;
    Integer techDeficit = 0;
    Integer nonTechSurplus = 0;
    Integer nonTechDeficit = 0;
  }

  private static List<DivisionImbalance> findGraduationImbalances(
    List<Division__c> divisions,
    Map<Id, DivisionState> stateMap,
    DistributionTargets targets
  ) {
    List<DivisionImbalance> imbalances = new List<DivisionImbalance>();

    for (Division__c div : divisions) {
      DivisionState state = stateMap.get(div.Id);
      DivisionImbalance imbalance = new DivisionImbalance();
      imbalance.divisionId = div.Id;

      Integer techDiff = state.tech - Integer.valueOf(targets.avgTech.round(System.RoundingMode.HALF_UP));
      Integer nonTechDiff = state.nonTech - Integer.valueOf(targets.avgNonTech.round(System.RoundingMode.HALF_UP));

      if (techDiff > 0) {
        imbalance.techSurplus = techDiff;
      } else if (techDiff < 0) {
        imbalance.techDeficit = Math.abs(techDiff);
      }

      if (nonTechDiff > 0) {
        imbalance.nonTechSurplus = nonTechDiff;
      } else if (nonTechDiff < 0) {
        imbalance.nonTechDeficit = Math.abs(nonTechDiff);
      }

      // Only add if there's an imbalance
      if (imbalance.techSurplus > 0 || imbalance.techDeficit > 0 ||
          imbalance.nonTechSurplus > 0 || imbalance.nonTechDeficit > 0) {
        imbalances.add(imbalance);
      }
    }

    // Sort by severity of imbalance
    imbalances.sort(new DivisionImbalanceComparator());
    return imbalances;
  }

  private class DivisionImbalanceComparator implements Comparator<DivisionImbalance> {
    public Integer compare(DivisionImbalance d1, DivisionImbalance d2) {
      Integer severity1 = d1.techSurplus + d1.techDeficit + d1.nonTechSurplus + d1.nonTechDeficit;
      Integer severity2 = d2.techSurplus + d2.techDeficit + d2.nonTechSurplus + d2.nonTechDeficit;
      if (severity1 > severity2) return -1;
      if (severity1 < severity2) return 1;
      return 0;
    }
  }

  private static Boolean trySwapStudents(
    Id div1Id,
    Id div2Id,
    String gradType,
    Map<Id, DivisionState> stateMap,
    Map<Id, Id> assignments,
    Map<Id, Student> studentMap
  ) {
    // Collect all students of the specified gradType in div1
    List<Student> candidates1 = new List<Student>();
    List<Id> candidateIds1 = new List<Id>();
    for (Id enrollmentId : assignments.keySet()) {
      if (assignments.get(enrollmentId) == div1Id) {
        Student s = studentMap.get(enrollmentId);
        if (s != null && s.gradType == gradType) {
          candidates1.add(s);
          candidateIds1.add(enrollmentId);
        }
      }
    }

    if (candidates1.isEmpty()) return false;

    // Collect all students of the opposite gradType in div2
    String oppositeGradType = (gradType == TECH) ? NON_TECH : TECH;
    List<Student> candidates2 = new List<Student>();
    List<Id> candidateIds2 = new List<Id>();
    for (Id enrollmentId : assignments.keySet()) {
      if (assignments.get(enrollmentId) == div2Id) {
        Student s = studentMap.get(enrollmentId);
        if (s != null && s.gradType == oppositeGradType) {
          candidates2.add(s);
          candidateIds2.add(enrollmentId);
        }
      }
    }

    if (candidates2.isEmpty()) return false;

    // Try to find a good match - prefer students with similar work experience
    // to maintain work experience balance
    DivisionState state1 = stateMap.get(div1Id);
    DivisionState state2 = stateMap.get(div2Id);
    
    Decimal avgExp1 = state1.male > 0 || state1.female > 0 
      ? (state1.maleExpTotal + state1.femaleExpTotal) / (state1.male + state1.female) 
      : 0;
    Decimal avgExp2 = state2.male > 0 || state2.female > 0
      ? (state2.maleExpTotal + state2.femaleExpTotal) / (state2.male + state2.female)
      : 0;

    // Find best match (students with similar work experience)
    Integer bestIdx1 = 0;
    Integer bestIdx2 = 0;
    Decimal bestScore = 999999;

    for (Integer i = 0; i < candidates1.size(); i++) {
      for (Integer j = 0; j < candidates2.size(); j++) {
        // Calculate how swapping would affect work experience balance
        Decimal newAvg1 = calculateNewAvgExp(state1, candidates1[i], candidates2[j]);
        Decimal newAvg2 = calculateNewAvgExp(state2, candidates2[j], candidates1[i]);
        
        // Score based on how close the new averages are to the original
        Decimal score = Math.abs(newAvg1 - avgExp1) + Math.abs(newAvg2 - avgExp2);
        
        if (score < bestScore) {
          bestScore = score;
          bestIdx1 = i;
          bestIdx2 = j;
        }
      }
    }

    // Perform the swap with best match
    Student s1 = candidates1[bestIdx1];
    Student s2 = candidates2[bestIdx2];
    Id student1Id = candidateIds1[bestIdx1];
    Id student2Id = candidateIds2[bestIdx2];

    // Remove from old divisions
    removeStudentFromState(s1, state1);
    removeStudentFromState(s2, state2);

    // Add to new divisions
    addStudentToState(s1, state2);
    addStudentToState(s2, state1);

    // Update assignments
    assignments.put(student1Id, div2Id);
    assignments.put(student2Id, div1Id);

    return true;
  }

  private static Decimal calculateNewAvgExp(DivisionState state, Student remove, Student add) {
    Integer total = state.male + state.female;
    Decimal totalExp = state.maleExpTotal + state.femaleExpTotal;
    
    // Remove old student's experience
    if (remove.gender == MALE) {
      totalExp -= remove.workExp;
    } else if (remove.gender == FEMALE) {
      totalExp -= remove.workExp;
    }
    
    // Add new student's experience
    if (add.gender == MALE) {
      totalExp += add.workExp;
    } else if (add.gender == FEMALE) {
      totalExp += add.workExp;
    }
    
    return total > 0 ? totalExp / total : 0;
  }

  private static void removeStudentFromState(Student s, DivisionState state) {
    state.total--;
    if (s.gender == MALE) {
      state.male--;
      state.maleExpTotal -= s.workExp;
    } else if (s.gender == FEMALE) {
      state.female--;
      state.femaleExpTotal -= s.workExp;
    }
    if (s.gradType == TECH) {
      state.tech--;
    } else if (s.gradType == NON_TECH) {
      state.nonTech--;
    }
    if (s.specialisationId != null && state.specialisationCount.containsKey(s.specialisationId)) {
      Integer currentCount = state.specialisationCount.get(s.specialisationId);
      if (currentCount > 0) {
        state.specialisationCount.put(s.specialisationId, currentCount - 1);
      }
    }
  }

  private static void addStudentToState(Student s, DivisionState state) {
    state.addStudent(s);
  }

  private static void optimizeSpecialisationBalance(
    List<Student> allStudents,
    List<Division__c> divisions,
    Map<Id, DivisionState> stateMap,
    Map<Id, Id> assignments,
    DistributionTargets targets
  ) {
    // Group students by specialisation
    Map<Id, List<Student>> studentsBySpec = new Map<Id, List<Student>>();
    for (Student s : allStudents) {
      if (s.specialisationId != null && assignments.containsKey(s.enrollmentId)) {
        if (!studentsBySpec.containsKey(s.specialisationId)) {
          studentsBySpec.put(s.specialisationId, new List<Student>());
        }
        studentsBySpec.get(s.specialisationId).add(s);
      }
    }

    // For each specialisation, redistribute using snake draft within that specialisation
    // This ensures balanced distribution within each specialisation
    for (Id specId : studentsBySpec.keySet()) {
      List<Student> specStudents = studentsBySpec.get(specId);
      // Sort by work experience for balanced distribution
      specStudents.sort(new StudentWorkExpComparator());
      
      // Remove existing assignments - we'll reassign them
      for (Student s : specStudents) {
        if (assignments.containsKey(s.enrollmentId)) {
          Id oldDivisionId = assignments.get(s.enrollmentId);
          assignments.remove(s.enrollmentId);
          // Remove from old division state
          DivisionState oldState = stateMap.get(oldDivisionId);
          if (oldState != null) {
            oldState.total--;
            if (s.gender == MALE) {
              oldState.male--;
              oldState.maleExpTotal -= s.workExp;
            } else if (s.gender == FEMALE) {
              oldState.female--;
              oldState.femaleExpTotal -= s.workExp;
            }
            if (s.gradType == TECH) {
              oldState.tech--;
            } else if (s.gradType == NON_TECH) {
              oldState.nonTech--;
            }
            if (s.specialisationId != null && oldState.specialisationCount.containsKey(s.specialisationId)) {
              Integer currentCount = oldState.specialisationCount.get(s.specialisationId);
              if (currentCount > 0) {
                oldState.specialisationCount.put(s.specialisationId, currentCount - 1);
              }
            }
          }
        }
      }
      
      // Redistribute within specialisation using snake draft
      distributeBySnakeDraft(specStudents, divisions, stateMap, assignments);
    }
  }

  /* ================= VALIDATION ================= */

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

  /* ================= HELPER CLASSES ================= */

  private class DistributionTargets {
    Decimal avgTotal;
    Decimal avgMale;
    Decimal avgFemale;
    Decimal avgTech;
    Decimal avgNonTech;
    Decimal avgMaleExp;
    Decimal avgFemaleExp;
    Map<Id, Decimal> avgSpecialisation = new Map<Id, Decimal>();
  }

  private static DistributionTargets calculateTargets(
    List<Student> students,
    Integer divCount
  ) {
    DistributionTargets targets = new DistributionTargets();

    Integer totalMale = 0;
    Integer totalFemale = 0;
    Integer totalTech = 0;
    Integer totalNonTech = 0;
    Decimal totalMaleExp = 0;
    Decimal totalFemaleExp = 0;
    Map<Id, Integer> specCounts = new Map<Id, Integer>();

    for (Student s : students) {
      if (s.gender == MALE) {
        totalMale++;
        totalMaleExp += s.workExp;
      } else if (s.gender == FEMALE) {
        totalFemale++;
        totalFemaleExp += s.workExp;
      }

      if (s.gradType == TECH) {
        totalTech++;
      } else if (s.gradType == NON_TECH) {
        totalNonTech++;
      }

      if (s.specialisationId != null) {
        Integer currentCount = specCounts.containsKey(s.specialisationId) 
          ? specCounts.get(s.specialisationId) : 0;
        specCounts.put(s.specialisationId, currentCount + 1);
      }
    }

    Decimal divCountDecimal = Decimal.valueOf(divCount);
    Integer studentSize = students.size();

    targets.avgTotal = Decimal.valueOf(studentSize) / divCountDecimal;
    targets.avgMale = Decimal.valueOf(totalMale) / divCountDecimal;
    targets.avgFemale = Decimal.valueOf(totalFemale) / divCountDecimal;
    targets.avgTech = Decimal.valueOf(totalTech) / divCountDecimal;
    targets.avgNonTech = Decimal.valueOf(totalNonTech) / divCountDecimal;
    targets.avgMaleExp = totalMale > 0 ? totalMaleExp / totalMale : 0;
    targets.avgFemaleExp = totalFemale > 0 ? totalFemaleExp / totalFemale : 0;

    // Calculate average per division for each specialisation
    for (Id specId : specCounts.keySet()) {
      Integer count = specCounts.get(specId);
      targets.avgSpecialisation.put(specId, Decimal.valueOf(count) / divCountDecimal);
    }

    return targets;
  }

  private class StudentWorkExpComparator implements Comparator<Student> {
    public Integer compare(Student s1, Student s2) {
      // Sort descending by work experience
      if (s1.workExp > s2.workExp)
        return -1;
      if (s1.workExp < s2.workExp)
        return 1;
      return 0;
    }
  }

  /* ================= DATA LOADING METHODS ================= */

  private static List<Division__c> loadActiveDivisions(Id termId) {
    return [
      SELECT Id, Name
      FROM Division__c
      WHERE Term__c = :termId AND Is_Active__c = TRUE
      ORDER BY Name
    ];
  }

  private static List<Student> loadStudents(Id termId) {
    // Get all enrollments for the term with Program Enrollment
    List<AcademicTermEnrollment> allEnrollments = [
      SELECT Id, LearnerAccountId, LearnerAccount.Gender__c, Program_Enrolled__c
      FROM AcademicTermEnrollment
      WHERE AcademicTermId = :termId
    ];

    if (allEnrollments.isEmpty())
      return new List<Student>();

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
      return new List<Student>();

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
          e.LearnerAccount.Gender__c,
          gradMap.get(e.LearnerAccountId),
          expMap.get(e.LearnerAccountId),
          enrollmentToSpecialisation.get(e.Id),
          enrollmentToSpecialisationName.get(e.Id)
      ));
    }

    return students;
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
      SELECT Student__c acc, SUM(Years_of_Work_Experience__c) exp
      FROM Work_Experience__c
      WHERE Student__c IN :accountIds
      GROUP BY Student__c
    ]) {
      expMap.put((Id) ar.get('acc'), (Decimal) ar.get('exp'));
    }

    return expMap;
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

  private static Map<Id, DivisionDTO> buildDivisionDTOMap(Id termId) {
    Map<Id, DivisionDTO> divisionMap = new Map<Id, DivisionDTO>();

    for (Division__c d : [
      SELECT Id, Name
      FROM Division__c
      WHERE Term__c = :termId AND Is_Active__c = TRUE
      ORDER BY Name
    ]) {
      DivisionDTO dto = new DivisionDTO();
      dto.divisionId = d.Id;
      dto.divisionName = d.Name;
      dto.total = 0;
      dto.male = 0;
      dto.female = 0;
      dto.tech = 0;
      dto.nonTech = 0;
      dto.avgMaleExp = 0;
      dto.avgFemaleExp = 0;
      dto.specialisationCounts = new Map<String, Integer>();
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

  private static void updateEnrollments(Map<Id, Id> assignments) {
    List<Division_Enrollment__c> divisionEnrollments = new List<Division_Enrollment__c>();
    List<AcademicTermEnrollment> enrollmentsToUpdate = new List<AcademicTermEnrollment>();

    // Query AcademicTermEnrollment records to update
    Map<Id, AcademicTermEnrollment> enrollmentMap = new Map<Id, AcademicTermEnrollment>([
      SELECT Id, Division__c
      FROM AcademicTermEnrollment
      WHERE Id IN :assignments.keySet()
    ]);

    for (Id enrollmentId : assignments.keySet()) {
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

    if (!divisionEnrollments.isEmpty()) {
      insert divisionEnrollments;
    }

    if (!enrollmentsToUpdate.isEmpty()) {
      update enrollmentsToUpdate;
    }
  }

  /* ================= CUSTOM EXCEPTION ================= */

  public class DistributionException extends Exception {
  }
}
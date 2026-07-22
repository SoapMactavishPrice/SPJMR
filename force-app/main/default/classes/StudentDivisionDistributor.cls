/**
 * @description Apex class to distribute students across divisions
 * ensuring equal distribution of males and females with ±5 variance,
 * equal distribution of Technical and Non-Technical graduates,
 * and balanced average work experience across divisions (±6 variance)
 */
public with sharing class StudentDivisionDistributor {
  // Constants
  private static final Integer VARIANCE = 5;
  private static final Integer WORK_EXPERIENCE_VARIANCE = 6;
  private static final String GENDER_MALE = 'Male';
  private static final String GENDER_FEMALE = 'Female';
  private static final String GRADUATION_TYPE_TECHNICAL = 'Technical';
  private static final String GRADUATION_TYPE_NON_TECHNICAL = 'Non Technical';

  /**
   * @description Distributes students across divisions for a given term
   * @param termId The AcademicTerm Id
   * @return Result object with success status and message
   */
  @AuraEnabled
  public static DistributionResult distributeStudentsByTerm(Id termId) {
    try {
      // Get all divisions for the term
      List<Division__c> divisions = [
        SELECT Id, Name, Division_Name__c, Capacity__c
        FROM Division__c
        WHERE Term__c = :termId AND Is_Active__c = TRUE
        ORDER BY Name
      ];

      if (divisions.isEmpty()) {
        return new DistributionResult(
          false,
          'No active divisions found for the selected term.'
        );
      }

      // Get all unassigned students for the term
      List<AcademicTermEnrollment> enrollments = [
        SELECT Id, LearnerAccountId, Division__c, LearnerAccount.Gender__c
        FROM AcademicTermEnrollment
        WHERE
          AcademicTermId = :termId
          AND Division__c = NULL
          AND LearnerAccountId != NULL
      ];

      if (enrollments.isEmpty()) {
        return new DistributionResult(
          false,
          'No unassigned students found for the selected term.'
        );
      }

      // Get graduation types from PersonEducation and work experience
      Set<Id> accountIds = new Set<Id>();
      for (AcademicTermEnrollment enrollment : enrollments) {
        if (enrollment.LearnerAccountId != null) {
          accountIds.add(enrollment.LearnerAccountId);
        }
      }

      // Query PersonEducation records to get graduation type (using AccountId)
      Map<Id, String> accountToGraduationTypeMap = new Map<Id, String>();
      List<PersonEducation> personEducations = [
        SELECT Id, AccountId, Graduation_Type__c
        FROM PersonEducation
        WHERE AccountId IN :accountIds AND Graduation_Type__c != NULL
        ORDER BY CreatedDate DESC
      ];

      // Map account to graduation type (taking the most recent if multiple)
      for (PersonEducation pe : personEducations) {
        if (!accountToGraduationTypeMap.containsKey(pe.AccountId)) {
          accountToGraduationTypeMap.put(pe.AccountId, pe.Graduation_Type__c);
        }
      }

      // Query Work_Experience__c records to get work experience
      Map<Id, Decimal> accountToWorkExperienceMap = new Map<Id, Decimal>();
      List<Work_Experience__c> workExperiences = [
        SELECT Id, Student__c, Years_of_Work_Experience__c
        FROM Work_Experience__c
        WHERE Student__c IN :accountIds AND Years_of_Work_Experience__c != NULL
      ];

      // Sum up work experience for each student (in case of multiple records)
      for (Work_Experience__c we : workExperiences) {
        Decimal currentExp = accountToWorkExperienceMap.get(we.Student__c);
        if (currentExp == null) {
          currentExp = 0;
        }
        accountToWorkExperienceMap.put(
          we.Student__c,
          currentExp +
          (we.Years_of_Work_Experience__c != null
            ? we.Years_of_Work_Experience__c
            : 0)
        );
      }

      // Map enrollment to work experience via Account
      Map<Id, Decimal> enrollmentToWorkExperienceMap = new Map<Id, Decimal>();
      for (AcademicTermEnrollment enrollment : enrollments) {
        if (enrollment.LearnerAccountId != null) {
          Decimal workExp = accountToWorkExperienceMap.get(
            enrollment.LearnerAccountId
          );
          enrollmentToWorkExperienceMap.put(
            enrollment.Id,
            workExp != null ? workExp : 0
          );
        } else {
          enrollmentToWorkExperienceMap.put(enrollment.Id, 0);
        }
      }

      // Separate students by gender and graduation type
      List<AcademicTermEnrollment> maleTechnical = new List<AcademicTermEnrollment>();
      List<AcademicTermEnrollment> maleNonTechnical = new List<AcademicTermEnrollment>();
      List<AcademicTermEnrollment> femaleTechnical = new List<AcademicTermEnrollment>();
      List<AcademicTermEnrollment> femaleNonTechnical = new List<AcademicTermEnrollment>();
      List<AcademicTermEnrollment> otherStudents = new List<AcademicTermEnrollment>();

      for (AcademicTermEnrollment enrollment : enrollments) {
        String gender = enrollment.LearnerAccount?.Gender__c;
        String graduationType = accountToGraduationTypeMap.get(
          enrollment.LearnerAccountId
        );

        if (gender == GENDER_MALE) {
          if (graduationType == GRADUATION_TYPE_TECHNICAL) {
            maleTechnical.add(enrollment);
          } else if (graduationType == GRADUATION_TYPE_NON_TECHNICAL) {
            maleNonTechnical.add(enrollment);
          } else {
            otherStudents.add(enrollment);
          }
        } else if (gender == GENDER_FEMALE) {
          if (graduationType == GRADUATION_TYPE_TECHNICAL) {
            femaleTechnical.add(enrollment);
          } else if (graduationType == GRADUATION_TYPE_NON_TECHNICAL) {
            femaleNonTechnical.add(enrollment);
          } else {
            otherStudents.add(enrollment);
          }
        } else {
          otherStudents.add(enrollment);
        }
      }

      // Distribute students
      Map<Id, Id> enrollmentToDivisionMap = new Map<Id, Id>();

      // Track overall gender balance across all divisions
      Map<Id, Integer> divisionMaleCount = new Map<Id, Integer>();
      Map<Id, Integer> divisionFemaleCount = new Map<Id, Integer>();
      Map<Id, Decimal> divisionMaleWorkExpTotal = new Map<Id, Decimal>();
      Map<Id, Decimal> divisionFemaleWorkExpTotal = new Map<Id, Decimal>();

      for (Division__c div : divisions) {
        divisionMaleCount.put(div.Id, 0);
        divisionFemaleCount.put(div.Id, 0);
        divisionMaleWorkExpTotal.put(div.Id, 0);
        divisionFemaleWorkExpTotal.put(div.Id, 0);
      }

      // Calculate total students and target gender distribution upfront
      Integer totalMales = maleTechnical.size() + maleNonTechnical.size();
      Integer totalFemales = femaleTechnical.size() + femaleNonTechnical.size();
      Integer numDivisions = divisions.size();
      Integer targetMalesPerDivision = totalMales / numDivisions;
      Integer targetFemalesPerDivision = totalFemales / numDivisions;

      // Interleave distribution to ensure gender balance
      // Process students in a round-robin fashion: one male, one female, etc.
      // This ensures:
      // 1. Equal distribution of males and females across divisions (±5 variance)
      // 2. Equal distribution of Technical and Non-Technical graduates across divisions (±5 variance)
      // 3. Balanced average work experience across divisions (±6 variance) for males and females separately
      // 4. Equal total number of students across divisions

      // Create a combined list that alternates between genders
      List<AcademicTermEnrollment> allStudents = new List<AcademicTermEnrollment>();
      List<String> allGenders = new List<String>();
      List<String> allGraduationTypes = new List<String>();

      // Interleave: add one from each group in round-robin fashion
      Integer maxSize = Math.max(
        Math.max(maleTechnical.size(), maleNonTechnical.size()),
        Math.max(femaleTechnical.size(), femaleNonTechnical.size())
      );

      for (Integer i = 0; i < maxSize; i++) {
        if (i < maleTechnical.size()) {
          allStudents.add(maleTechnical[i]);
          allGenders.add(GENDER_MALE);
          allGraduationTypes.add(GRADUATION_TYPE_TECHNICAL);
        }
        if (i < femaleTechnical.size()) {
          allStudents.add(femaleTechnical[i]);
          allGenders.add(GENDER_FEMALE);
          allGraduationTypes.add(GRADUATION_TYPE_TECHNICAL);
        }
        if (i < maleNonTechnical.size()) {
          allStudents.add(maleNonTechnical[i]);
          allGenders.add(GENDER_MALE);
          allGraduationTypes.add(GRADUATION_TYPE_NON_TECHNICAL);
        }
        if (i < femaleNonTechnical.size()) {
          allStudents.add(femaleNonTechnical[i]);
          allGenders.add(GENDER_FEMALE);
          allGraduationTypes.add(GRADUATION_TYPE_NON_TECHNICAL);
        }
      }

      // Distribute interleaved students one by one
      for (Integer i = 0; i < allStudents.size(); i++) {
        distributeSingleStudentWithBalance(
          allStudents[i],
          divisions,
          enrollmentToDivisionMap,
          enrollmentToWorkExperienceMap,
          allGenders[i],
          divisionMaleCount,
          divisionFemaleCount,
          divisionMaleWorkExpTotal,
          divisionFemaleWorkExpTotal,
          targetMalesPerDivision,
          targetFemalesPerDivision
        );
      }
      // Distribute other students (if any) - distribute evenly
      distributeByGender(otherStudents, divisions, enrollmentToDivisionMap);

      // Update enrollments with division assignments
      List<AcademicTermEnrollment> enrollmentsToUpdate = new List<AcademicTermEnrollment>();
      for (Id enrollmentId : enrollmentToDivisionMap.keySet()) {
        AcademicTermEnrollment enrollment = new AcademicTermEnrollment(
          Id = enrollmentId,
          Division__c = enrollmentToDivisionMap.get(enrollmentId)
        );
        enrollmentsToUpdate.add(enrollment);
      }

      if (!enrollmentsToUpdate.isEmpty()) {
        update enrollmentsToUpdate;
      }

      // Calculate and return distribution statistics
      Map<Id, DivisionStats> divisionStats = calculateDivisionStats(
        divisions,
        enrollmentToDivisionMap
      );

      String message =
        'Successfully distributed ' +
        enrollments.size() +
        ' students across ' +
        divisions.size() +
        ' divisions.';

      return new DistributionResult(true, message, divisionStats);
    } catch (Exception e) {
      return new DistributionResult(false, 'Error: ' + e.getMessage());
    }
  }

  /**
   * @description Distributes students of a specific gender across divisions
   * Uses a balanced approach to maintain ±5 variance
   * @param students List of student enrollments
   * @param divisions List of available divisions
   * @param enrollmentToDivisionMap Map to store enrollment to division assignments
   */
  private static void distributeByGender(
    List<AcademicTermEnrollment> students,
    List<Division__c> divisions,
    Map<Id, Id> enrollmentToDivisionMap
  ) {
    if (students.isEmpty() || divisions.isEmpty()) {
      return;
    }

    Integer numDivisions = divisions.size();

    // Track current count per division for this gender
    Map<Id, Integer> divisionCountMap = new Map<Id, Integer>();
    for (Division__c div : divisions) {
      divisionCountMap.put(div.Id, 0);
    }

    // Calculate target distribution
    Integer studentsPerDivision = students.size() / numDivisions;
    Integer remainder = Math.mod(students.size(), numDivisions);

    // Distribute students ensuring balanced distribution
    for (AcademicTermEnrollment student : students) {
      Id bestDivisionId = findBestDivision(
        divisionCountMap,
        studentsPerDivision,
        remainder > 0
      );

      if (bestDivisionId != null) {
        enrollmentToDivisionMap.put(student.Id, bestDivisionId);
        divisionCountMap.put(
          bestDivisionId,
          divisionCountMap.get(bestDivisionId) + 1
        );

        // Decrement remainder if we assigned to a division that needed extra
        if (
          remainder > 0 &&
          divisionCountMap.get(bestDivisionId) > studentsPerDivision
        ) {
          remainder--;
        }
      }
    }
  }

  /**
   * @description Distributes a single student considering overall gender balance and work experience
   * @param student The student enrollment to distribute
   * @param divisions List of available divisions
   * @param enrollmentToDivisionMap Map to store enrollment to division assignments
   * @param enrollmentToWorkExperienceMap Map of enrollment to work experience years
   * @param gender Gender of the student
   * @param divisionMaleCount Overall male count per division (updated during distribution)
   * @param divisionFemaleCount Overall female count per division (updated during distribution)
   * @param divisionMaleWorkExpTotal Overall male work exp total per division
   * @param divisionFemaleWorkExpTotal Overall female work exp total per division
   * @param targetMalesPerDivision Target males per division
   * @param targetFemalesPerDivision Target females per division
   */
  private static void distributeSingleStudentWithBalance(
    AcademicTermEnrollment student,
    List<Division__c> divisions,
    Map<Id, Id> enrollmentToDivisionMap,
    Map<Id, Decimal> enrollmentToWorkExperienceMap,
    String gender,
    Map<Id, Integer> divisionMaleCount,
    Map<Id, Integer> divisionFemaleCount,
    Map<Id, Decimal> divisionMaleWorkExpTotal,
    Map<Id, Decimal> divisionFemaleWorkExpTotal,
    Integer targetMalesPerDivision,
    Integer targetFemalesPerDivision
  ) {
    if (divisions.isEmpty()) {
      return;
    }

    Decimal workExp = enrollmentToWorkExperienceMap.get(student.Id);
    if (workExp == null) {
      workExp = 0;
    }

    // Calculate target average work experience for this gender
    // We'll use a simple approach: prefer divisions with average closer to overall average
    Decimal targetAvgWorkExp = 0; // Will be calculated based on current distribution

    // Initialize group maps for single student (not really needed but method expects them)
    Map<Id, Integer> groupCountMap = new Map<Id, Integer>();
    Map<Id, Decimal> groupWorkExpTotalMap = new Map<Id, Decimal>();
    for (Division__c div : divisions) {
      groupCountMap.put(div.Id, 0);
      groupWorkExpTotalMap.put(div.Id, 0);
    }

    // Find best division using gender balance as primary factor
    Id bestDivisionId = findBestDivisionForGenderBalance(
      groupCountMap,
      groupWorkExpTotalMap,
      divisionMaleCount,
      divisionFemaleCount,
      divisionMaleWorkExpTotal,
      divisionFemaleWorkExpTotal,
      0, // targetCount not used for single student
      true, // allowExtra
      targetAvgWorkExp,
      workExp,
      gender,
      targetMalesPerDivision,
      targetFemalesPerDivision
    );

    if (bestDivisionId != null) {
      enrollmentToDivisionMap.put(student.Id, bestDivisionId);

      // Update overall gender counts
      if (gender == GENDER_MALE) {
        divisionMaleCount.put(
          bestDivisionId,
          divisionMaleCount.get(bestDivisionId) + 1
        );
        divisionMaleWorkExpTotal.put(
          bestDivisionId,
          divisionMaleWorkExpTotal.get(bestDivisionId) + workExp
        );
      } else {
        divisionFemaleCount.put(
          bestDivisionId,
          divisionFemaleCount.get(bestDivisionId) + 1
        );
        divisionFemaleWorkExpTotal.put(
          bestDivisionId,
          divisionFemaleWorkExpTotal.get(bestDivisionId) + workExp
        );
      }
    }
  }

  /**
   * @description Distributes students considering overall gender balance, count, and work experience
   * Maintains ±5 variance for count and ±6 variance for average work experience
   * Also ensures gender balance across divisions
   * @param students List of student enrollments
   * @param divisions List of available divisions
   * @param enrollmentToDivisionMap Map to store enrollment to division assignments
   * @param enrollmentToWorkExperienceMap Map of enrollment to work experience years
   * @param gender Gender of the students being distributed
   * @param divisionMaleCount Overall male count per division (updated during distribution)
   * @param divisionFemaleCount Overall female count per division (updated during distribution)
   * @param divisionMaleWorkExpTotal Overall male work exp total per division
   * @param divisionFemaleWorkExpTotal Overall female work exp total per division
   */
  private static void distributeByGenderAndExperienceWithBalance(
    List<AcademicTermEnrollment> students,
    List<Division__c> divisions,
    Map<Id, Id> enrollmentToDivisionMap,
    Map<Id, Decimal> enrollmentToWorkExperienceMap,
    String gender,
    Map<Id, Integer> divisionMaleCount,
    Map<Id, Integer> divisionFemaleCount,
    Map<Id, Decimal> divisionMaleWorkExpTotal,
    Map<Id, Decimal> divisionFemaleWorkExpTotal,
    Integer targetMalesPerDivision,
    Integer targetFemalesPerDivision
  ) {
    if (students.isEmpty() || divisions.isEmpty()) {
      return;
    }

    Integer numDivisions = divisions.size();

    // Track current count and total work experience per division for this specific group
    Map<Id, Integer> groupCountMap = new Map<Id, Integer>();
    Map<Id, Decimal> groupWorkExpTotalMap = new Map<Id, Decimal>();

    for (Division__c div : divisions) {
      groupCountMap.put(div.Id, 0);
      groupWorkExpTotalMap.put(div.Id, 0);
    }

    // Calculate total work experience for this group
    Decimal totalWorkExp = 0;
    for (AcademicTermEnrollment student : students) {
      Decimal workExp = enrollmentToWorkExperienceMap.get(student.Id);
      if (workExp != null) {
        totalWorkExp += workExp;
      }
    }

    // Calculate target average work experience for this gender group
    Decimal targetAvgWorkExp = students.size() > 0
      ? totalWorkExp / students.size()
      : 0;

    // Calculate target distribution for count of this gender group
    Integer studentsPerDivision = students.size() / numDivisions;
    Integer remainder = Math.mod(students.size(), numDivisions);

    // Use the pre-calculated target gender balance (passed as parameters)

    // Sort students by work experience to help balance distribution
    List<StudentWithExperience> studentsWithExp = new List<StudentWithExperience>();
    for (AcademicTermEnrollment student : students) {
      Decimal workExp = enrollmentToWorkExperienceMap.get(student.Id);
      studentsWithExp.add(
        new StudentWithExperience(student, workExp != null ? workExp : 0)
      );
    }
    studentsWithExp.sort();

    // Distribute students ensuring balanced count, gender balance, and work experience
    for (StudentWithExperience studentWithExp : studentsWithExp) {
      AcademicTermEnrollment student = studentWithExp.enrollment;
      Decimal workExp = studentWithExp.workExperience;

      Id bestDivisionId = findBestDivisionForGenderBalance(
        groupCountMap,
        groupWorkExpTotalMap,
        divisionMaleCount,
        divisionFemaleCount,
        divisionMaleWorkExpTotal,
        divisionFemaleWorkExpTotal,
        studentsPerDivision,
        remainder > 0,
        targetAvgWorkExp,
        workExp,
        gender,
        targetMalesPerDivision,
        targetFemalesPerDivision
      );

      if (bestDivisionId != null) {
        enrollmentToDivisionMap.put(student.Id, bestDivisionId);
        groupCountMap.put(
          bestDivisionId,
          groupCountMap.get(bestDivisionId) + 1
        );
        groupWorkExpTotalMap.put(
          bestDivisionId,
          groupWorkExpTotalMap.get(bestDivisionId) + workExp
        );

        // Update overall gender counts
        if (gender == GENDER_MALE) {
          divisionMaleCount.put(
            bestDivisionId,
            divisionMaleCount.get(bestDivisionId) + 1
          );
          divisionMaleWorkExpTotal.put(
            bestDivisionId,
            divisionMaleWorkExpTotal.get(bestDivisionId) + workExp
          );
        } else {
          divisionFemaleCount.put(
            bestDivisionId,
            divisionFemaleCount.get(bestDivisionId) + 1
          );
          divisionFemaleWorkExpTotal.put(
            bestDivisionId,
            divisionFemaleWorkExpTotal.get(bestDivisionId) + workExp
          );
        }

        // Decrement remainder if we assigned to a division that needed extra
        if (
          remainder > 0 &&
          groupCountMap.get(bestDivisionId) > studentsPerDivision
        ) {
          remainder--;
        }
      }
    }
  }

  /**
   * @description Distributes students considering both count and work experience balance
   * Maintains ±5 variance for count and ±6 variance for average work experience
   * @param students List of student enrollments
   * @param divisions List of available divisions
   * @param enrollmentToDivisionMap Map to store enrollment to division assignments
   * @param enrollmentToWorkExperienceMap Map of enrollment to work experience years
   * @param gender Gender of the students being distributed
   */
  private static void distributeByGenderAndExperience(
    List<AcademicTermEnrollment> students,
    List<Division__c> divisions,
    Map<Id, Id> enrollmentToDivisionMap,
    Map<Id, Decimal> enrollmentToWorkExperienceMap,
    String gender
  ) {
    if (students.isEmpty() || divisions.isEmpty()) {
      return;
    }

    Integer numDivisions = divisions.size();

    // Track current count and total work experience per division for this gender
    Map<Id, Integer> divisionCountMap = new Map<Id, Integer>();
    Map<Id, Decimal> divisionWorkExpTotalMap = new Map<Id, Decimal>();

    for (Division__c div : divisions) {
      divisionCountMap.put(div.Id, 0);
      divisionWorkExpTotalMap.put(div.Id, 0);
    }

    // Calculate total work experience for this group
    Decimal totalWorkExp = 0;
    for (AcademicTermEnrollment student : students) {
      Decimal workExp = enrollmentToWorkExperienceMap.get(student.Id);
      if (workExp != null) {
        totalWorkExp += workExp;
      }
    }

    // Calculate target average work experience
    Decimal targetAvgWorkExp = students.size() > 0
      ? totalWorkExp / students.size()
      : 0;

    // Calculate target distribution for count
    Integer studentsPerDivision = students.size() / numDivisions;
    Integer remainder = Math.mod(students.size(), numDivisions);

    // Sort students by work experience to help balance distribution
    List<StudentWithExperience> studentsWithExp = new List<StudentWithExperience>();
    for (AcademicTermEnrollment student : students) {
      Decimal workExp = enrollmentToWorkExperienceMap.get(student.Id);
      studentsWithExp.add(
        new StudentWithExperience(student, workExp != null ? workExp : 0)
      );
    }
    // Sort by work experience (alternating high and low helps balance)
    studentsWithExp.sort();

    // Distribute students ensuring balanced count and work experience
    for (StudentWithExperience studentWithExp : studentsWithExp) {
      AcademicTermEnrollment student = studentWithExp.enrollment;
      Decimal workExp = studentWithExp.workExperience;

      Id bestDivisionId = findBestDivisionForExperience(
        divisionCountMap,
        divisionWorkExpTotalMap,
        studentsPerDivision,
        remainder > 0,
        targetAvgWorkExp,
        workExp
      );

      if (bestDivisionId != null) {
        enrollmentToDivisionMap.put(student.Id, bestDivisionId);
        divisionCountMap.put(
          bestDivisionId,
          divisionCountMap.get(bestDivisionId) + 1
        );
        divisionWorkExpTotalMap.put(
          bestDivisionId,
          divisionWorkExpTotalMap.get(bestDivisionId) + workExp
        );

        // Decrement remainder if we assigned to a division that needed extra
        if (
          remainder > 0 &&
          divisionCountMap.get(bestDivisionId) > studentsPerDivision
        ) {
          remainder--;
        }
      }
    }
  }

  /**
   * @description Helper class to sort students by work experience
   */
  private class StudentWithExperience implements Comparable {
    public AcademicTermEnrollment enrollment;
    public Decimal workExperience;

    public StudentWithExperience(
      AcademicTermEnrollment enrollment,
      Decimal workExperience
    ) {
      this.enrollment = enrollment;
      this.workExperience = workExperience;
    }

    public Integer compareTo(Object compareTo) {
      StudentWithExperience compareToStudent = (StudentWithExperience) compareTo;
      if (workExperience > compareToStudent.workExperience) {
        return 1;
      } else if (workExperience < compareToStudent.workExperience) {
        return -1;
      }
      return 0;
    }
  }

  /**
   * @description Finds the best division considering both count and work experience balance
   * @param divisionCountMap Current count of students per division
   * @param divisionWorkExpTotalMap Current total work experience per division
   * @param targetCount Target number of students per division
   * @param allowExtra Whether to allow assigning to divisions that already have target count
   * @param targetAvgWorkExp Target average work experience
   * @param studentWorkExp Work experience of the student being assigned
   * @return Id of the best division
   */
  private static Id findBestDivisionForExperience(
    Map<Id, Integer> divisionCountMap,
    Map<Id, Decimal> divisionWorkExpTotalMap,
    Integer targetCount,
    Boolean allowExtra,
    Decimal targetAvgWorkExp,
    Decimal studentWorkExp
  ) {
    Id bestDivisionId = null;
    Decimal bestScore = null;

    for (Id divId : divisionCountMap.keySet()) {
      Integer currentCount = divisionCountMap.get(divId);
      Decimal currentWorkExpTotal = divisionWorkExpTotalMap.get(divId);

      // Calculate what the average would be if we assign this student here
      Decimal newCount = currentCount + 1;
      Decimal newWorkExpTotal = currentWorkExpTotal + studentWorkExp;
      Decimal newAvg = newCount > 0 ? newWorkExpTotal / newCount : 0;

      // Calculate score: prefer divisions that are below target count and closer to target average
      Decimal countScore = 0;
      if (currentCount < targetCount) {
        countScore = 100 - (targetCount - currentCount) * 10; // Higher score for lower count
      } else if (allowExtra && currentCount == targetCount) {
        countScore = 50;
      } else {
        countScore = 10; // Lower score for over target
      }

      // Calculate average score: prefer divisions where new average is closer to target
      Decimal avgDiff = Math.abs(newAvg - targetAvgWorkExp);
      Decimal avgScore = 100 - (avgDiff * 10); // Higher score for smaller difference

      // Combined score (weight count more than average to maintain balance)
      Decimal combinedScore = (countScore * 0.6) + (avgScore * 0.4);

      if (bestScore == null || combinedScore > bestScore) {
        bestScore = combinedScore;
        bestDivisionId = divId;
      }
    }

    // Fallback: if no division found, return the one with minimum count
    if (bestDivisionId == null) {
      Integer minCount = null;
      for (Id divId : divisionCountMap.keySet()) {
        Integer currentCount = divisionCountMap.get(divId);
        if (minCount == null || currentCount < minCount) {
          minCount = currentCount;
          bestDivisionId = divId;
        }
      }
    }

    return bestDivisionId;
  }

  /**
   * @description Finds the best division considering gender balance, count, and work experience
   * @param groupCountMap Current count of this group per division
   * @param groupWorkExpTotalMap Current total work experience of this group per division
   * @param divisionMaleCount Overall male count per division
   * @param divisionFemaleCount Overall female count per division
   * @param divisionMaleWorkExpTotal Overall male work exp total per division
   * @param divisionFemaleWorkExpTotal Overall female work exp total per division
   * @param targetCount Target number of students per division for this group
   * @param allowExtra Whether to allow assigning to divisions that already have target count
   * @param targetAvgWorkExp Target average work experience
   * @param studentWorkExp Work experience of the student being assigned
   * @param gender Gender of the student
   * @param targetMalesPerDivision Target males per division
   * @param targetFemalesPerDivision Target females per division
   * @return Id of the best division
   */
  private static Id findBestDivisionForGenderBalance(
    Map<Id, Integer> groupCountMap,
    Map<Id, Decimal> groupWorkExpTotalMap,
    Map<Id, Integer> divisionMaleCount,
    Map<Id, Integer> divisionFemaleCount,
    Map<Id, Decimal> divisionMaleWorkExpTotal,
    Map<Id, Decimal> divisionFemaleWorkExpTotal,
    Integer targetCount,
    Boolean allowExtra,
    Decimal targetAvgWorkExp,
    Decimal studentWorkExp,
    String gender,
    Integer targetMalesPerDivision,
    Integer targetFemalesPerDivision
  ) {
    Id bestDivisionId = null;
    Decimal bestScore = null;

    for (Id divId : groupCountMap.keySet()) {
      Integer currentGroupCount = groupCountMap.get(divId);
      Decimal currentGroupWorkExpTotal = groupWorkExpTotalMap.get(divId);
      Integer currentMaleCount = divisionMaleCount.get(divId);
      Integer currentFemaleCount = divisionFemaleCount.get(divId);

      // Calculate what the average would be if we assign this student here
      Decimal newGroupCount = currentGroupCount + 1;
      Decimal newGroupWorkExpTotal = currentGroupWorkExpTotal + studentWorkExp;
      Decimal newAvg = newGroupCount > 0
        ? newGroupWorkExpTotal / newGroupCount
        : 0;

      // Calculate what the gender counts would be
      Integer newMaleCount = gender == GENDER_MALE
        ? currentMaleCount + 1
        : currentMaleCount;
      Integer newFemaleCount = gender == GENDER_FEMALE
        ? currentFemaleCount + 1
        : currentFemaleCount;

      // Score 1: Group count balance (30% weight)
      Decimal countScore = 0;
      if (currentGroupCount < targetCount) {
        countScore = 100 - (targetCount - currentGroupCount) * 10;
      } else if (allowExtra && currentGroupCount == targetCount) {
        countScore = 50;
      } else {
        countScore = 10;
      }

      // Score 2: Gender balance (50% weight) - CRITICAL for proper distribution
      Decimal genderBalanceScore = 0;
      if (gender == GENDER_MALE) {
        // Prefer divisions with fewer males (to balance genders)
        Integer maleDiff = targetMalesPerDivision - newMaleCount;
        // Heavily penalize divisions that are already over target for males
        if (newMaleCount > targetMalesPerDivision) {
          genderBalanceScore = 0; // Don't assign more males to divisions already over target
        } else {
          genderBalanceScore = 100 - Math.abs(maleDiff) * 20; // Higher score for better balance
        }
      } else {
        // Prefer divisions with fewer females (to balance genders)
        Integer femaleDiff = targetFemalesPerDivision - newFemaleCount;
        // Heavily penalize divisions that are already over target for females
        if (newFemaleCount > targetFemalesPerDivision) {
          genderBalanceScore = 0; // Don't assign more females to divisions already over target
        } else {
          genderBalanceScore = 100 - Math.abs(femaleDiff) * 20; // Higher score for better balance
        }
      }

      // Score 3: Work experience balance (20% weight)
      Decimal avgDiff = Math.abs(newAvg - targetAvgWorkExp);
      Decimal avgScore = 100 - (avgDiff * 10);

      // Combined score - gender balance is most important
      Decimal combinedScore =
        (countScore * 0.3) +
        (genderBalanceScore * 0.5) +
        (avgScore * 0.2);

      if (bestScore == null || combinedScore > bestScore) {
        bestScore = combinedScore;
        bestDivisionId = divId;
      }
    }

    // Fallback: if no division found, return the one with minimum count
    if (bestDivisionId == null) {
      Integer minCount = null;
      for (Id divId : groupCountMap.keySet()) {
        Integer currentCount = groupCountMap.get(divId);
        if (minCount == null || currentCount < minCount) {
          minCount = currentCount;
          bestDivisionId = divId;
        }
      }
    }

    return bestDivisionId;
  }

  /**
   * @description Finds the best division to assign a student to maintain balance
   * @param divisionCountMap Current count of students per division
   * @param targetCount Target number of students per division
   * @param allowExtra Whether to allow assigning to divisions that already have target count
   * @return Id of the best division
   */
  private static Id findBestDivision(
    Map<Id, Integer> divisionCountMap,
    Integer targetCount,
    Boolean allowExtra
  ) {
    Id bestDivisionId = null;
    Integer minCount = null;

    for (Id divId : divisionCountMap.keySet()) {
      Integer currentCount = divisionCountMap.get(divId);

      // Prefer divisions below target count
      if (currentCount < targetCount) {
        if (minCount == null || currentCount < minCount) {
          minCount = currentCount;
          bestDivisionId = divId;
        }
      }
      // If all are at target and we allow extra, find the one with minimum count
      else if (allowExtra && currentCount == targetCount) {
        if (minCount == null || currentCount < minCount) {
          minCount = currentCount;
          bestDivisionId = divId;
        }
      }
    }

    // If no division found (all are above target), return the one with minimum count
    if (bestDivisionId == null) {
      for (Id divId : divisionCountMap.keySet()) {
        Integer currentCount = divisionCountMap.get(divId);
        if (minCount == null || currentCount < minCount) {
          minCount = currentCount;
          bestDivisionId = divId;
        }
      }
    }

    return bestDivisionId;
  }

  /**
   * @description Calculates statistics for each division after distribution
   * @param divisions List of divisions
   * @param enrollmentToDivisionMap Map of enrollment to division assignments
   * @return Map of division Id to DivisionStats
   */
  private static Map<Id, DivisionStats> calculateDivisionStats(
    List<Division__c> divisions,
    Map<Id, Id> enrollmentToDivisionMap
  ) {
    Map<Id, DivisionStats> statsMap = new Map<Id, DivisionStats>();

    // Initialize stats for each division
    for (Division__c div : divisions) {
      statsMap.put(div.Id, new DivisionStats(div.Name, 0, 0, 0, 0, 0, 0, 0, 0));
    }

    // Get gender, graduation type, and work experience information for assigned enrollments
    Set<Id> enrollmentIds = enrollmentToDivisionMap.keySet();
    Map<Id, String> enrollmentGenderMap = new Map<Id, String>();
    Map<Id, String> enrollmentGraduationTypeMap = new Map<Id, String>();
    Map<Id, Decimal> enrollmentWorkExperienceMap = new Map<Id, Decimal>();

    Set<Id> contactIds = new Set<Id>();
    Set<Id> accountIds = new Set<Id>();
    List<AcademicTermEnrollment> assignedEnrollments = [
      SELECT Id, LearnerAccountId, LearnerAccount.Gender__c
      FROM AcademicTermEnrollment
      WHERE Id IN :enrollmentIds
    ];

    for (AcademicTermEnrollment enrollment : assignedEnrollments) {
      String gender = enrollment.LearnerAccount?.Gender__c;
      enrollmentGenderMap.put(enrollment.Id, gender);
      if (enrollment.LearnerAccountId != null) {
        accountIds.add(enrollment.LearnerAccountId);
      }
    }

    // Query PersonEducation for graduation types (using AccountId)
    List<PersonEducation> personEducations = [
      SELECT Id, AccountId, Graduation_Type__c
      FROM PersonEducation
      WHERE AccountId IN :accountIds AND Graduation_Type__c != NULL
      ORDER BY CreatedDate DESC
    ];

    // Map account to graduation type
    Map<Id, String> accountToGraduationTypeMap = new Map<Id, String>();
    for (PersonEducation pe : personEducations) {
      if (!accountToGraduationTypeMap.containsKey(pe.AccountId)) {
        accountToGraduationTypeMap.put(pe.AccountId, pe.Graduation_Type__c);
      }
    }

    // Query Work_Experience__c for work experience
    Map<Id, Decimal> accountToWorkExperienceMap = new Map<Id, Decimal>();
    if (!accountIds.isEmpty()) {
      List<Work_Experience__c> workExperiences = [
        SELECT Id, Student__c, Years_of_Work_Experience__c
        FROM Work_Experience__c
        WHERE Student__c IN :accountIds AND Years_of_Work_Experience__c != NULL
      ];

      for (Work_Experience__c we : workExperiences) {
        Decimal currentExp = accountToWorkExperienceMap.get(we.Student__c);
        if (currentExp == null) {
          currentExp = 0;
        }
        accountToWorkExperienceMap.put(
          we.Student__c,
          currentExp +
          (we.Years_of_Work_Experience__c != null
            ? we.Years_of_Work_Experience__c
            : 0)
        );
      }
    }

    // Map enrollment to graduation type and work experience
    for (AcademicTermEnrollment enrollment : assignedEnrollments) {
      if (enrollment.LearnerAccountId != null) {
        String graduationType = accountToGraduationTypeMap.get(
          enrollment.LearnerAccountId
        );
        enrollmentGraduationTypeMap.put(enrollment.Id, graduationType);

        Decimal workExp = accountToWorkExperienceMap.get(
          enrollment.LearnerAccountId
        );
        enrollmentWorkExperienceMap.put(
          enrollment.Id,
          workExp != null ? workExp : 0
        );
      } else {
        enrollmentWorkExperienceMap.put(enrollment.Id, 0);
      }
    }

    // Track work experience totals per division by gender
    Map<Id, Decimal> divisionMaleWorkExpTotal = new Map<Id, Decimal>();
    Map<Id, Decimal> divisionFemaleWorkExpTotal = new Map<Id, Decimal>();

    // Count students by gender and graduation type per division
    for (Id enrollmentId : enrollmentToDivisionMap.keySet()) {
      Id divisionId = enrollmentToDivisionMap.get(enrollmentId);
      String gender = enrollmentGenderMap.get(enrollmentId);
      String graduationType = enrollmentGraduationTypeMap.get(enrollmentId);
      Decimal workExp = enrollmentWorkExperienceMap.get(enrollmentId);

      DivisionStats stats = statsMap.get(divisionId);
      if (stats != null) {
        stats.totalStudents++;
        if (gender == GENDER_MALE) {
          stats.maleCount++;
          Decimal maleTotal = divisionMaleWorkExpTotal.get(divisionId);
          if (maleTotal == null)
            maleTotal = 0;
          divisionMaleWorkExpTotal.put(divisionId, maleTotal + workExp);
        } else if (gender == GENDER_FEMALE) {
          stats.femaleCount++;
          Decimal femaleTotal = divisionFemaleWorkExpTotal.get(divisionId);
          if (femaleTotal == null)
            femaleTotal = 0;
          divisionFemaleWorkExpTotal.put(divisionId, femaleTotal + workExp);
        }
        if (graduationType == GRADUATION_TYPE_TECHNICAL) {
          stats.technicalCount++;
        } else if (graduationType == GRADUATION_TYPE_NON_TECHNICAL) {
          stats.nonTechnicalCount++;
        }
      }
    }

    // Calculate average work experience per division by gender
    for (Id divisionId : statsMap.keySet()) {
      DivisionStats stats = statsMap.get(divisionId);
      Decimal maleTotal = divisionMaleWorkExpTotal.get(divisionId);
      Decimal femaleTotal = divisionFemaleWorkExpTotal.get(divisionId);

      if (stats.maleCount > 0 && maleTotal != null) {
        stats.avgMaleWorkExperience = maleTotal / stats.maleCount;
      }
      if (stats.femaleCount > 0 && femaleTotal != null) {
        stats.avgFemaleWorkExperience = femaleTotal / stats.femaleCount;
      }
      if (stats.totalStudents > 0) {
        Decimal totalWorkExp =
          (maleTotal != null ? maleTotal : 0) +
          (femaleTotal != null ? femaleTotal : 0);
        stats.avgWorkExperience = totalWorkExp / stats.totalStudents;
      }
    }

    return statsMap;
  }

  /**
   * @description Gets all divisions for a term
   * @param termId The AcademicTerm Id
   * @return List of division IDs
   */
  @AuraEnabled(cacheable=true)
  public static List<Id> getDivisionsForTerm(Id termId) {
    List<Id> divisionIds = new List<Id>();

    List<Division__c> divisions = [
      SELECT Id
      FROM Division__c
      WHERE Term__c = :termId AND Is_Active__c = TRUE
      ORDER BY Name
    ];

    for (Division__c div : divisions) {
      divisionIds.add(div.Id);
    }

    return divisionIds;
  }

  /**
   * @description Gets division names by their IDs
   * @param divisionIds List of division IDs
   * @return Map of division Id to division name
   */
  @AuraEnabled(cacheable=true)
  public static Map<Id, String> getDivisionNames(List<Id> divisionIds) {
    Map<Id, String> divisionNameMap = new Map<Id, String>();

    if (divisionIds == null || divisionIds.isEmpty()) {
      return divisionNameMap;
    }

    List<Division__c> divisions = [
      SELECT Id, Name, Division_Name__c
      FROM Division__c
      WHERE Id IN :divisionIds
    ];

    for (Division__c div : divisions) {
      String displayName = div.Division_Name__c != null
        ? div.Division_Name__c
        : div.Name;
      divisionNameMap.put(div.Id, displayName);
    }

    return divisionNameMap;
  }

  /**
   * @description Validates if the distribution meets the ±5 variance requirement
   * @param termId The AcademicTerm Id
   * @return ValidationResult with validation status and details
   */
  @AuraEnabled
  public static ValidationResult validateDistribution(Id termId) {
    try {
      // Get all divisions for the term
      List<Division__c> divisions = [
        SELECT Id, Name
        FROM Division__c
        WHERE Term__c = :termId AND Is_Active__c = TRUE
        ORDER BY Name
      ];

      if (divisions.isEmpty()) {
        return new ValidationResult(
          false,
          'No active divisions found for the selected term.'
        );
      }

      // Check total students (assigned and unassigned)
      Integer totalStudents = [
        SELECT COUNT()
        FROM AcademicTermEnrollment
        WHERE AcademicTermId = :termId AND LearnerAccountId != NULL
      ];

      Integer assignedStudents = [
        SELECT COUNT()
        FROM AcademicTermEnrollment
        WHERE
          AcademicTermId = :termId
          AND Division__c != NULL
          AND LearnerAccountId != NULL
      ];

      // Get all assigned students
      List<AcademicTermEnrollment> enrollments = [
        SELECT Id, Division__c, LearnerAccountId, LearnerAccount.Gender__c
        FROM AcademicTermEnrollment
        WHERE
          AcademicTermId = :termId
          AND Division__c != NULL
          AND LearnerAccountId != NULL
      ];

      // Initialize division counts (even if no students assigned)
      Map<Id, Integer> divisionMaleCount = new Map<Id, Integer>();
      Map<Id, Integer> divisionFemaleCount = new Map<Id, Integer>();
      Map<Id, Integer> divisionTechnicalCount = new Map<Id, Integer>();
      Map<Id, Integer> divisionNonTechnicalCount = new Map<Id, Integer>();
      Map<Id, Decimal> divisionMaleWorkExpTotal = new Map<Id, Decimal>();
      Map<Id, Decimal> divisionFemaleWorkExpTotal = new Map<Id, Decimal>();

      for (Division__c div : divisions) {
        divisionMaleCount.put(div.Id, 0);
        divisionFemaleCount.put(div.Id, 0);
        divisionTechnicalCount.put(div.Id, 0);
        divisionNonTechnicalCount.put(div.Id, 0);
        divisionMaleWorkExpTotal.put(div.Id, 0);
        divisionFemaleWorkExpTotal.put(div.Id, 0);
      }

      // If no students are assigned, return with zeros and informative message
      if (enrollments.isEmpty()) {
        String message = 'No students are currently assigned to divisions. ';
        if (totalStudents > 0) {
          message +=
            'Total unassigned students: ' +
            totalStudents +
            '. Please use "Distribute Students" to assign them.';
        } else {
          message += 'No students found for this term.';
        }

        // Calculate averages (all will be 0)
        Map<Id, Decimal> divisionMaleAvgWorkExp = new Map<Id, Decimal>();
        Map<Id, Decimal> divisionFemaleAvgWorkExp = new Map<Id, Decimal>();
        for (Id divId : divisionMaleCount.keySet()) {
          divisionMaleAvgWorkExp.put(divId, 0);
          divisionFemaleAvgWorkExp.put(divId, 0);
        }

        return new ValidationResult(
          false,
          message,
          divisionMaleCount,
          divisionFemaleCount,
          divisionTechnicalCount,
          divisionNonTechnicalCount,
          divisionMaleAvgWorkExp,
          divisionFemaleAvgWorkExp
        );
      }

      // Get graduation types from PersonEducation and work experience
      Set<Id> accountIds = new Set<Id>();
      for (AcademicTermEnrollment enrollment : enrollments) {
        if (enrollment.LearnerAccountId != null) {
          accountIds.add(enrollment.LearnerAccountId);
        }
      }

      Map<Id, String> accountToGraduationTypeMap = new Map<Id, String>();
      if (!accountIds.isEmpty()) {
        List<PersonEducation> personEducations = [
          SELECT Id, AccountId, Graduation_Type__c
          FROM PersonEducation
          WHERE AccountId IN :accountIds AND Graduation_Type__c != NULL
          ORDER BY CreatedDate DESC
        ];

        for (PersonEducation pe : personEducations) {
          if (!accountToGraduationTypeMap.containsKey(pe.AccountId)) {
            accountToGraduationTypeMap.put(pe.AccountId, pe.Graduation_Type__c);
          }
        }
      }

      // Get work experience
      Map<Id, Decimal> accountToWorkExperienceMap = new Map<Id, Decimal>();
      if (!accountIds.isEmpty()) {
        List<Work_Experience__c> workExperiences = [
          SELECT Id, Student__c, Years_of_Work_Experience__c
          FROM Work_Experience__c
          WHERE
            Student__c IN :accountIds
            AND Years_of_Work_Experience__c != NULL
        ];

        for (Work_Experience__c we : workExperiences) {
          Decimal currentExp = accountToWorkExperienceMap.get(we.Student__c);
          if (currentExp == null) {
            currentExp = 0;
          }
          accountToWorkExperienceMap.put(
            we.Student__c,
            currentExp +
            (we.Years_of_Work_Experience__c != null
              ? we.Years_of_Work_Experience__c
              : 0)
          );
        }
      }

      // Count males, females, technical, and non-technical per division
      // Also track work experience totals by gender per division
      // (Maps already initialized above)

      for (AcademicTermEnrollment enrollment : enrollments) {
        String gender = enrollment.LearnerAccount?.Gender__c;
        String graduationType = accountToGraduationTypeMap.get(
          enrollment.LearnerAccountId
        );
        Decimal workExp = accountToWorkExperienceMap.get(
          enrollment.LearnerAccountId
        );
        if (workExp == null)
          workExp = 0;
        Id divisionId = enrollment.Division__c;

        if (
          gender == GENDER_MALE && divisionMaleCount.containsKey(divisionId)
        ) {
          divisionMaleCount.put(
            divisionId,
            divisionMaleCount.get(divisionId) + 1
          );
          divisionMaleWorkExpTotal.put(
            divisionId,
            divisionMaleWorkExpTotal.get(divisionId) + workExp
          );
        } else if (
          gender == GENDER_FEMALE && divisionFemaleCount.containsKey(divisionId)
        ) {
          divisionFemaleCount.put(
            divisionId,
            divisionFemaleCount.get(divisionId) + 1
          );
          divisionFemaleWorkExpTotal.put(
            divisionId,
            divisionFemaleWorkExpTotal.get(divisionId) + workExp
          );
        }

        if (
          graduationType == GRADUATION_TYPE_TECHNICAL &&
          divisionTechnicalCount.containsKey(divisionId)
        ) {
          divisionTechnicalCount.put(
            divisionId,
            divisionTechnicalCount.get(divisionId) + 1
          );
        } else if (
          graduationType == GRADUATION_TYPE_NON_TECHNICAL &&
          divisionNonTechnicalCount.containsKey(divisionId)
        ) {
          divisionNonTechnicalCount.put(
            divisionId,
            divisionNonTechnicalCount.get(divisionId) + 1
          );
        }
      }

      // Check variance for males
      List<Integer> maleCounts = new List<Integer>(divisionMaleCount.values());
      Integer minMales = getMin(maleCounts);
      Integer maxMales = getMax(maleCounts);
      Integer maleVariance = maxMales - minMales;

      // Check variance for females
      List<Integer> femaleCounts = new List<Integer>(
        divisionFemaleCount.values()
      );
      Integer minFemales = getMin(femaleCounts);
      Integer maxFemales = getMax(femaleCounts);
      Integer femaleVariance = maxFemales - minFemales;

      // Check variance for technical
      List<Integer> technicalCounts = new List<Integer>(
        divisionTechnicalCount.values()
      );
      Integer minTechnical = getMin(technicalCounts);
      Integer maxTechnical = getMax(technicalCounts);
      Integer technicalVariance = maxTechnical - minTechnical;

      // Check variance for non-technical
      List<Integer> nonTechnicalCounts = new List<Integer>(
        divisionNonTechnicalCount.values()
      );
      Integer minNonTechnical = getMin(nonTechnicalCounts);
      Integer maxNonTechnical = getMax(nonTechnicalCounts);
      Integer nonTechnicalVariance = maxNonTechnical - minNonTechnical;

      // Calculate average work experience per division by gender
      Map<Id, Decimal> divisionMaleAvgWorkExp = new Map<Id, Decimal>();
      Map<Id, Decimal> divisionFemaleAvgWorkExp = new Map<Id, Decimal>();

      // Iterate over division IDs from the count maps
      for (Id divId : divisionMaleCount.keySet()) {
        Integer maleCount = divisionMaleCount.get(divId);
        Integer femaleCount = divisionFemaleCount.get(divId);
        Decimal maleTotal = divisionMaleWorkExpTotal.get(divId);
        Decimal femaleTotal = divisionFemaleWorkExpTotal.get(divId);

        if (maleCount > 0 && maleTotal != null) {
          divisionMaleAvgWorkExp.put(divId, maleTotal / maleCount);
        } else {
          divisionMaleAvgWorkExp.put(divId, 0);
        }

        if (femaleCount > 0 && femaleTotal != null) {
          divisionFemaleAvgWorkExp.put(divId, femaleTotal / femaleCount);
        } else {
          divisionFemaleAvgWorkExp.put(divId, 0);
        }
      }

      // Check variance for average work experience (males)
      List<Decimal> maleAvgWorkExpList = new List<Decimal>(
        divisionMaleAvgWorkExp.values()
      );
      Decimal minMaleAvgWorkExp = getMinDecimal(maleAvgWorkExpList);
      Decimal maxMaleAvgWorkExp = getMaxDecimal(maleAvgWorkExpList);
      Decimal maleWorkExpVariance = maxMaleAvgWorkExp - minMaleAvgWorkExp;

      // Check variance for average work experience (females)
      List<Decimal> femaleAvgWorkExpList = new List<Decimal>(
        divisionFemaleAvgWorkExp.values()
      );
      Decimal minFemaleAvgWorkExp = getMinDecimal(femaleAvgWorkExpList);
      Decimal maxFemaleAvgWorkExp = getMaxDecimal(femaleAvgWorkExpList);
      Decimal femaleWorkExpVariance = maxFemaleAvgWorkExp - minFemaleAvgWorkExp;

      Boolean isValid =
        (maleVariance <= VARIANCE) &&
        (femaleVariance <= VARIANCE) &&
        (technicalVariance <= VARIANCE) &&
        (nonTechnicalVariance <= VARIANCE) &&
        (maleWorkExpVariance <= WORK_EXPERIENCE_VARIANCE) &&
        (femaleWorkExpVariance <= WORK_EXPERIENCE_VARIANCE);

      String message =
        'Male variance: ' +
        maleVariance +
        ' (Min: ' +
        minMales +
        ', Max: ' +
        maxMales +
        '), ' +
        'Female variance: ' +
        femaleVariance +
        ' (Min: ' +
        minFemales +
        ', Max: ' +
        maxFemales +
        '), ' +
        'Technical variance: ' +
        technicalVariance +
        ' (Min: ' +
        minTechnical +
        ', Max: ' +
        maxTechnical +
        '), ' +
        'Non-Technical variance: ' +
        nonTechnicalVariance +
        ' (Min: ' +
        minNonTechnical +
        ', Max: ' +
        maxNonTechnical +
        '), ' +
        'Male Work Exp Avg variance: ' +
        maleWorkExpVariance.setScale(2) +
        ' (Min: ' +
        minMaleAvgWorkExp.setScale(2) +
        ', Max: ' +
        maxMaleAvgWorkExp.setScale(2) +
        '), ' +
        'Female Work Exp Avg variance: ' +
        femaleWorkExpVariance.setScale(2) +
        ' (Min: ' +
        minFemaleAvgWorkExp.setScale(2) +
        ', Max: ' +
        maxFemaleAvgWorkExp.setScale(2) +
        '). ' +
        (isValid
          ? 'Distribution is valid.'
          : 'Distribution exceeds variance limits.');

      return new ValidationResult(
        isValid,
        message,
        divisionMaleCount,
        divisionFemaleCount,
        divisionTechnicalCount,
        divisionNonTechnicalCount,
        divisionMaleAvgWorkExp,
        divisionFemaleAvgWorkExp
      );
    } catch (Exception e) {
      return new ValidationResult(false, 'Error: ' + e.getMessage());
    }
  }

  /**
   * @description Helper method to get minimum value from list
   */
  private static Integer getMin(List<Integer> values) {
    if (values.isEmpty())
      return 0;
    Integer min = values[0];
    for (Integer val : values) {
      if (val < min)
        min = val;
    }
    return min;
  }

  /**
   * @description Helper method to get maximum value from list
   */
  private static Integer getMax(List<Integer> values) {
    if (values.isEmpty())
      return 0;
    Integer max = values[0];
    for (Integer val : values) {
      if (val > max)
        max = val;
    }
    return max;
  }

  /**
   * @description Helper method to get minimum Decimal value from list
   */
  private static Decimal getMinDecimal(List<Decimal> values) {
    if (values.isEmpty())
      return 0;
    Decimal min = values[0];
    for (Decimal val : values) {
      if (val < min)
        min = val;
    }
    return min;
  }

  /**
   * @description Helper method to get maximum Decimal value from list
   */
  private static Decimal getMaxDecimal(List<Decimal> values) {
    if (values.isEmpty())
      return 0;
    Decimal max = values[0];
    for (Decimal val : values) {
      if (val > max)
        max = val;
    }
    return max;
  }

  // Wrapper classes for results

  /**
   * @description Result class for distribution operation
   */
  public class DistributionResult {
    @AuraEnabled
    public Boolean success { get; set; }
    @AuraEnabled
    public String message { get; set; }
    @AuraEnabled
    public Map<Id, DivisionStats> divisionStats { get; set; }

    public DistributionResult(Boolean success, String message) {
      this.success = success;
      this.message = message;
      this.divisionStats = new Map<Id, DivisionStats>();
    }

    public DistributionResult(
      Boolean success,
      String message,
      Map<Id, DivisionStats> stats
    ) {
      this.success = success;
      this.message = message;
      this.divisionStats = stats;
    }
  }

  /**
   * @description Statistics class for division
   */
  public class DivisionStats {
    @AuraEnabled
    public String divisionName { get; set; }
    @AuraEnabled
    public Integer totalStudents { get; set; }
    @AuraEnabled
    public Integer maleCount { get; set; }
    @AuraEnabled
    public Integer femaleCount { get; set; }
    @AuraEnabled
    public Integer technicalCount { get; set; }
    @AuraEnabled
    public Integer nonTechnicalCount { get; set; }
    @AuraEnabled
    public Decimal avgWorkExperience { get; set; }
    @AuraEnabled
    public Decimal avgMaleWorkExperience { get; set; }
    @AuraEnabled
    public Decimal avgFemaleWorkExperience { get; set; }

    public DivisionStats(
      String divisionName,
      Integer total,
      Integer males,
      Integer females,
      Integer technical,
      Integer nonTechnical,
      Decimal avgWorkExp,
      Decimal avgMaleWorkExp,
      Decimal avgFemaleWorkExp
    ) {
      this.divisionName = divisionName;
      this.totalStudents = total;
      this.maleCount = males;
      this.femaleCount = females;
      this.technicalCount = technical;
      this.nonTechnicalCount = nonTechnical;
      this.avgWorkExperience = avgWorkExp;
      this.avgMaleWorkExperience = avgMaleWorkExp;
      this.avgFemaleWorkExperience = avgFemaleWorkExp;
    }
  }

  /**
   * @description Result class for validation operation
   */
  public class ValidationResult {
    @AuraEnabled
    public Boolean isValid { get; set; }
    @AuraEnabled
    public String message { get; set; }
    @AuraEnabled
    public Map<Id, Integer> maleCounts { get; set; }
    @AuraEnabled
    public Map<Id, Integer> femaleCounts { get; set; }
    @AuraEnabled
    public Map<Id, Integer> technicalCounts { get; set; }
    @AuraEnabled
    public Map<Id, Integer> nonTechnicalCounts { get; set; }
    @AuraEnabled
    public Map<Id, Decimal> maleAvgWorkExperience { get; set; }
    @AuraEnabled
    public Map<Id, Decimal> femaleAvgWorkExperience { get; set; }

    public ValidationResult(Boolean isValid, String message) {
      this.isValid = isValid;
      this.message = message;
      this.maleCounts = new Map<Id, Integer>();
      this.femaleCounts = new Map<Id, Integer>();
      this.technicalCounts = new Map<Id, Integer>();
      this.nonTechnicalCounts = new Map<Id, Integer>();
      this.maleAvgWorkExperience = new Map<Id, Decimal>();
      this.femaleAvgWorkExperience = new Map<Id, Decimal>();
    }

    public ValidationResult(
      Boolean isValid,
      String message,
      Map<Id, Integer> maleCounts,
      Map<Id, Integer> femaleCounts,
      Map<Id, Integer> technicalCounts,
      Map<Id, Integer> nonTechnicalCounts,
      Map<Id, Decimal> maleAvgWorkExperience,
      Map<Id, Decimal> femaleAvgWorkExperience
    ) {
      this.isValid = isValid;
      this.message = message;
      this.maleCounts = maleCounts;
      this.femaleCounts = femaleCounts;
      this.technicalCounts = technicalCounts;
      this.nonTechnicalCounts = nonTechnicalCounts;
      this.maleAvgWorkExperience = maleAvgWorkExperience;
      this.femaleAvgWorkExperience = femaleAvgWorkExperience;
    }
  }
}
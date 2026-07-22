/**
 * @description Apex class to generate Student_Specialisation__c records
 * for ProgramCohortMember records with random distribution rules:
 * 
 * Rules:
 * 1. Only one Student_Specialisation__c can be Major per ProgramCohortMember
 * 2. Randomly create 2 records (one Minor, one Major) OR 1 record (either Minor or Major)
 * 3. Some records should have only 1 record (either Minor or Major)
 */
public class StudentSpecialisationGenerator {
  
  // Specialisation Master IDs
  private static final String SPECIALISATION_MASTER_1 = 'a10C1000009pSDBIA2';
  private static final String SPECIALISATION_MASTER_2 = 'a10C100000EqRNRIA3';
  
  // Specialisation Type values
  private static final String TYPE_MAJOR = 'Major';
  private static final String TYPE_MINOR = 'Minor';
  
  /**
   * Generate Student_Specialisation__c records for all ProgramCohortMembers
   * in the specified ProgramCohort
   * @param programCohortId The ProgramCohort ID (19sC10000000V8fIAE or custom)
   * @return Map of created record types and their IDs
   */
  public static Map<String, List<Id>> generateStudentSpecialisations(Id programCohortId) {
    return generateStudentSpecialisations(programCohortId, null);
  }
  
  /**
   * Generate Student_Specialisation__c records for ProgramCohortMembers
   * @param programCohortId The ProgramCohort ID (can be null to process all)
   * @param programCohortMemberIds Optional list of specific ProgramCohortMember IDs to process
   * @return Map of created record types and their IDs
   */
  public static Map<String, List<Id>> generateStudentSpecialisations(
    Id programCohortId,
    List<Id> programCohortMemberIds
  ) {
    Map<String, List<Id>> createdRecords = new Map<String, List<Id>>();
    List<Id> specialisationIds = new List<Id>();
    
    System.debug('=== STARTING STUDENT SPECIALISATION GENERATION ===');
    System.debug('ProgramCohort ID: ' + programCohortId);
    
    // Query ProgramCohortMembers
    List<ProgramCohortMember> cohortMembers = new List<ProgramCohortMember>();
    
    if (programCohortMemberIds != null && !programCohortMemberIds.isEmpty()) {
      // Query specific members
      cohortMembers = [
        SELECT Id, Name, ProgramCohortId
        FROM ProgramCohortMember
        WHERE Id IN :programCohortMemberIds
      ];
    } else if (programCohortId != null) {
      // Query all members for the specified cohort
      cohortMembers = [
        SELECT Id, Name, ProgramCohortId
        FROM ProgramCohortMember
        WHERE ProgramCohortId = :programCohortId
      ];
    } else {
      // Query all members (use with caution)
      cohortMembers = [
        SELECT Id, Name, ProgramCohortId
        FROM ProgramCohortMember
        LIMIT 10000
      ];
    }
    
    if (cohortMembers.isEmpty()) {
      System.debug('No ProgramCohortMembers found');
      return createdRecords;
    }
    
    System.debug('Found ' + cohortMembers.size() + ' ProgramCohortMembers to process');
    
    // Generate Student_Specialisation__c records
    List<Student_Specialisation__c> specialisations = new List<Student_Specialisation__c>();
    
    for (ProgramCohortMember member : cohortMembers) {
      List<Student_Specialisation__c> memberSpecialisations = 
        generateSpecialisationsForMember(member.Id);
      specialisations.addAll(memberSpecialisations);
    }
    
    // Insert in batches to avoid governor limits
    Integer batchSize = 200;
    for (Integer i = 0; i < specialisations.size(); i += batchSize) {
      List<Student_Specialisation__c> batch = new List<Student_Specialisation__c>();
      for (Integer j = i; j < Math.min(i + batchSize, specialisations.size()); j++) {
        batch.add(specialisations[j]);
      }
      insert batch;
      for (Student_Specialisation__c ss : batch) {
        specialisationIds.add(ss.Id);
      }
    }
    
    createdRecords.put('Student_Specialisation__c', specialisationIds);
    
    System.debug('=== STUDENT SPECIALISATION GENERATION COMPLETE ===');
    System.debug('Total ProgramCohortMembers processed: ' + cohortMembers.size());
    System.debug('Total Student_Specialisation__c records created: ' + specialisationIds.size());
    
    return createdRecords;
  }
  
  /**
   * Generate Student_Specialisation__c records for a single ProgramCohortMember
   * Rules:
   * - Randomly create 1 or 2 records
   * - If 2 records: One Major, one Minor
   * - If 1 record: Randomly choose Major or Minor
   * - Only one Major allowed per member
   * @param programCohortMemberId The ProgramCohortMember ID
   * @return List of Student_Specialisation__c records (not inserted)
   */
  private static List<Student_Specialisation__c> generateSpecialisationsForMember(
    Id programCohortMemberId
  ) {
    List<Student_Specialisation__c> specialisations = new List<Student_Specialisation__c>();
    
    // Randomly decide: 1 or 2 records (50% chance for each)
    Integer recordCount = (Math.random() < 0.5) ? 1 : 2;
    
    if (recordCount == 2) {
      // Create 2 records: One Major, one Minor
      // Randomly assign Specialisation_Master__c to each (can be same or different)
      
      // Major record - randomly assign a master
      String majorMaster = (Math.random() < 0.5) 
        ? SPECIALISATION_MASTER_1 
        : SPECIALISATION_MASTER_2;
      
      specialisations.add(new Student_Specialisation__c(
        Program_Cohort_Member__c = programCohortMemberId,
        Specialisation_Type__c = TYPE_MAJOR,
        Specialisation_Master__c = majorMaster
      ));
      
      // Minor record - randomly assign a master (can be same or different)
      String minorMaster = (Math.random() < 0.5) 
        ? SPECIALISATION_MASTER_1 
        : SPECIALISATION_MASTER_2;
      
      specialisations.add(new Student_Specialisation__c(
        Program_Cohort_Member__c = programCohortMemberId,
        Specialisation_Type__c = TYPE_MINOR,
        Specialisation_Master__c = minorMaster
      ));
      
    } else {
      // Create 1 record: Randomly choose Major or Minor
      String specialisationType = (Math.random() < 0.5) ? TYPE_MAJOR : TYPE_MINOR;
      String masterId = (Math.random() < 0.5) 
        ? SPECIALISATION_MASTER_1 
        : SPECIALISATION_MASTER_2;
      
      specialisations.add(new Student_Specialisation__c(
        Program_Cohort_Member__c = programCohortMemberId,
        Specialisation_Type__c = specialisationType,
        Specialisation_Master__c = masterId
      ));
    }
    
    return specialisations;
  }
}
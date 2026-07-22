/**
 * @description Apex class to generate robust sample data for
 * Program Enrollment testing
 *
 * Creates diverse student enrollments with:
 * - Gender skew (70% Male / 30% Female / 5% NULL)
 * - Graduation skew (60% Technical / 40% Non-Technical)
 * - Missing graduation (~15%)
 * - Multiple PersonEducation records (~20%) where latest wins
 * - Varied work experience (0-10 years with randomness)
 */
public class ProgramEnrollmentDataGenerator {
  
  /**
   * Generate program enrollment data with default values
   * @param programId The Program ID to enroll students in
   * @return Map of created record types and their IDs
   */
  public static Map<String, List<Id>> generateProgramEnrollments(Id programId) {
    return generateProgramEnrollments(programId, 80, 'Applied');
  }

  /**
   * Generate program enrollment data with custom parameters
   * @param programId The Program ID to enroll students in
   * @param studentCount Number of students to create
   * @param enrollmentStatus Status value for ProgramEnrollment (can be null if not required)
   * @return Map of created record types and their IDs
   */
  public static Map<String, List<Id>> generateProgramEnrollments(
    Id programId,
    Integer studentCount,
    String enrollmentStatus
  ) {
    Map<String, List<Id>> createdRecords = new Map<String, List<Id>>();

    System.debug('=== STARTING PROGRAM ENROLLMENT DATA GENERATION ===');
    System.debug('Program ID: ' + programId);
    System.debug('Student Count: ' + studentCount);
    System.debug('Enrollment Status: ' + enrollmentStatus);

    // 1. Get Person Account Record Type
    Id personRT = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsPersonType = TRUE
      LIMIT 1
    ].Id;

    // 2. Create Students (Person Accounts) with diverse genders
    List<Account> accounts = new List<Account>();

    for (Integer i = 0; i < studentCount; i++) {
      String gender;
      Decimal r = Math.random();

      // 5% NULL gender, 70% Male, 25% Female
      if (r < 0.05) {
        gender = null; // 5% NULL gender
      } else if (r < 0.75) {
        gender = 'Male'; // 70% Male
      } else {
        gender = 'Female'; // 25% Female
      }

      accounts.add(
        new Account(
          RecordTypeId = personRT,
          FirstName = 'Program',
          LastName = 'Student ' + String.valueOf(i + 1).leftPad(3, '0'),
          PersonEmail = 'program.student' + i + '@example.com',
          Gender__c = gender
        )
      );
    }

    // Insert in batches to avoid governor limits
    List<Id> accountIds = new List<Id>();
    Integer batchSize = 200;
    for (Integer i = 0; i < accounts.size(); i += batchSize) {
      List<Account> batch = new List<Account>();
      for (Integer j = i; j < Math.min(i + batchSize, accounts.size()); j++) {
        batch.add(accounts[j]);
      }
      insert batch;
      for (Account acc : batch) {
        accountIds.add(acc.Id);
      }
    }

    createdRecords.put('Account', accountIds);
    System.debug('Created ' + accountIds.size() + ' Person Accounts');

    // 3. Get Contacts (auto-created from Person Accounts)
    Map<Id, Id> accountToContact = new Map<Id, Id>();
    for (Contact c : [
      SELECT Id, AccountId
      FROM Contact
      WHERE AccountId IN :accountIds
    ]) {
      accountToContact.put(c.AccountId, c.Id);
    }
    createdRecords.put('Contact', new List<Id>(accountToContact.values()));
    System.debug('Retrieved ' + accountToContact.size() + ' Contacts');

    // 4. Create PersonEducation records (Graduation Data)
    List<PersonEducation> educations = new List<PersonEducation>();

    for (Integer i = 0; i < accounts.size(); i++) {
      // 15% missing graduation data
      if (Math.random() < 0.15) {
        continue;
      }

      // 60% Technical, 40% Non-Technical
      String graduationType = (Math.random() < 0.6)
        ? 'Technical'
        : 'Non Technical';

      Id accId = accounts[i].Id;
      Id conId = accountToContact.get(accId);

      if (conId == null) {
        continue; // Skip if no contact found
      }

      // 20% multiple education records (older one first)
      if (Math.random() < 0.2) {
        educations.add(
          new PersonEducation(
            AccountId = accId,
            ContactId = conId,
            Graduation_Type__c = graduationType == 'Technical'
              ? 'Non Technical'
              : 'Technical',
            EducationLevel = 'Bachelor',
            IsActive = false,
            Name = 'Old Degree'
          )
        );
      }

      // Latest education (should win)
      educations.add(
        new PersonEducation(
          AccountId = accId,
          ContactId = conId,
          Graduation_Type__c = graduationType,
          EducationLevel = 'Bachelor',
          IsActive = true,
          Name = 'Latest Degree'
        )
      );
    }

    // Insert in batches
    List<Id> educationIds = new List<Id>();
    for (Integer i = 0; i < educations.size(); i += batchSize) {
      List<PersonEducation> batch = new List<PersonEducation>();
      for (Integer j = i; j < Math.min(i + batchSize, educations.size()); j++) {
        batch.add(educations[j]);
      }
      insert batch;
      for (PersonEducation pe : batch) {
        educationIds.add(pe.Id);
      }
    }

    createdRecords.put('PersonEducation', educationIds);
    System.debug('Created ' + educationIds.size() + ' PersonEducation records');

    // 5. Create Work Experience Records with varied experience
    List<Work_Experience__c> workExperiences = new List<Work_Experience__c>();

    for (Integer i = 0; i < accounts.size(); i++) {
      Account acc = accounts[i];

      // Vary work experience between 0-10 years
      // Use modulo for distribution, but add some randomness for more diversity
      Decimal yearsOfExperience = Math.mod(i, 11); // 0 to 10 years
      
      // Add some randomness: 30% chance to have 0-2 more years
      if (Math.random() < 0.3 && yearsOfExperience < 9) {
        yearsOfExperience += Math.mod(Integer.valueOf(Math.random() * 3), 3);
      }

      Work_Experience__c we = new Work_Experience__c();
      we.Student__c = acc.Id;
      we.Years_of_Work_Experience__c = yearsOfExperience;

      // Set dates for calculation (if fields exist)
      if (yearsOfExperience > 0) {
        we.WE_From_Date__c = Date.today()
          .addYears(-Integer.valueOf(yearsOfExperience) - 1);
        we.WE_To_Date__c = Date.today().addMonths(-6);
        we.Current_Company__c = false;
      }

      // Set work experience flag (if field exists)
      we.Do_You_Have_Any_Work_Experience__c = yearsOfExperience > 0
        ? 'Yes'
        : 'No';

      workExperiences.add(we);
    }

    // Insert in batches
    List<Id> workExpIds = new List<Id>();
    for (Integer i = 0; i < workExperiences.size(); i += batchSize) {
      List<Work_Experience__c> batch = new List<Work_Experience__c>();
      for (Integer j = i; j < Math.min(i + batchSize, workExperiences.size()); j++) {
        batch.add(workExperiences[j]);
      }
      insert batch;
      for (Work_Experience__c we : batch) {
        workExpIds.add(we.Id);
      }
    }

    createdRecords.put('Work_Experience__c', workExpIds);
    System.debug('Created ' + workExpIds.size() + ' Work Experience records');

    // 6. Create ProgramEnrollment records
    List<ProgramEnrollment> programEnrollments = new List<ProgramEnrollment>();

    for (Integer i = 0; i < accounts.size(); i++) {
      Account acc = accounts[i];
      Id contactId = accountToContact.get(acc.Id);
      
      if (contactId == null) {
        continue; // Skip if no contact found
      }

      ProgramEnrollment pe = new ProgramEnrollment();
      pe.ProgramId = programId;
      pe.AccountId = acc.Id;
      //pe.ContactId = contactId;
      pe.IsActive = true;
      
      // Set Status if provided
      if (enrollmentStatus != null && enrollmentStatus != '') {
        pe.Status = enrollmentStatus;
      }
      
      // Set dates if needed
      pe.StartDate = Date.today();
      pe.ApplicationDate = Date.today().addDays(-30); // Applied 30 days ago
      
      programEnrollments.add(pe);
    }

    // Insert in batches
    List<Id> enrollmentIds = new List<Id>();
    for (Integer i = 0; i < programEnrollments.size(); i += batchSize) {
      List<ProgramEnrollment> batch = new List<ProgramEnrollment>();
      for (Integer j = i; j < Math.min(i + batchSize, programEnrollments.size()); j++) {
        batch.add(programEnrollments[j]);
      }
      insert batch;
      for (ProgramEnrollment pe : batch) {
        enrollmentIds.add(pe.Id);
      }
    }

    createdRecords.put('ProgramEnrollment', enrollmentIds);
    System.debug('Created ' + enrollmentIds.size() + ' ProgramEnrollment records');

    // ================= SUMMARY =================
    System.debug('=== PROGRAM ENROLLMENT DATA GENERATION COMPLETE ===');
    System.debug('Program ID: ' + programId);
    System.debug('Number of Students (Accounts): ' + createdRecords.get('Account').size());
    System.debug('Number of Contacts: ' + createdRecords.get('Contact').size());
    System.debug('Number of PersonEducation records: ' + createdRecords.get('PersonEducation').size());
    System.debug('Number of Work Experience records: ' + createdRecords.get('Work_Experience__c').size());
    System.debug('Number of ProgramEnrollments: ' + createdRecords.get('ProgramEnrollment').size());

    // Print first few enrollment IDs for verification
    if (!enrollmentIds.isEmpty()) {
      System.debug('=== SAMPLE ENROLLMENT IDs ===');
      for (Integer i = 0; i < Math.min(5, enrollmentIds.size()); i++) {
        System.debug('Enrollment ' + (i + 1) + ': ' + enrollmentIds[i]);
      }
    }

    System.debug('=== DATA GENERATION SUCCESSFUL ===');

    return createdRecords;
  }
}
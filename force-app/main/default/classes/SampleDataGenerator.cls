/**
 * @description Apex class to generate robust sample data for
 * testing Student Division Distribution algorithm
 *
 * Enhancements:
 * - Gender skew (70% Male / 30% Female)
 * - NULL gender (~5%)
 * - Graduation skew (60% Technical / 40% Non-Technical)
 * - Missing graduation (~15%)
 * - Multiple PersonEducation records (~20%) where latest wins
 */
public class SampleDataGenerator {
  public static Map<String, List<Id>> generateSampleData() {
    return generateSampleData(50);
  }

  public static Map<String, List<Id>> generateSampleData(Integer studentCount) {
    Map<String, List<Id>> createdRecords = new Map<String, List<Id>>();

    // 1. Academic Term
    AcademicTerm term = new AcademicTerm(
      Name = 'Test Term - Distribution',
      StartDate = Date.today().addDays(10),
      EndDate = Date.today().addMonths(4),
      IsActive = true
    );
    insert term;
    createdRecords.put('AcademicTerm', new List<Id>{ term.Id });

    // 2. Divisions
    List<Division__c> divisions = new List<Division__c>();
    for (Integer i = 1; i <= 4; i++) {
      divisions.add(
        new Division__c(
          Term__c = term.Id,
          Division_Name__c = 'DIV' + i,
          Capacity__c = 30,
          Is_Active__c = true
        )
      );
    }
    insert divisions;
    createdRecords.put(
      'Division__c',
      new List<Id>(new Map<Id, Division__c>(divisions).keySet())
    );

    // 3. Create Students (Person Accounts)
    Id personRT = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsPersonType = TRUE
      LIMIT 1
    ]
    .Id;

    List<Account> accounts = new List<Account>();

    for (Integer i = 0; i < studentCount; i++) {
      String gender;
      Decimal r = Math.random();

      if (r < 0.05) {
        gender = null; // 5% NULL gender
      } else if (i < studentCount * 0.7) {
        gender = 'Male'; // 70%
      } else {
        gender = 'Female'; // 30%
      }

      accounts.add(
        new Account(
          RecordTypeId = personRT,
          FirstName = 'Student',
          LastName = 'Test ' + i,
          PersonEmail = 'student' + i + '@example.com',
          Gender__c = gender
        )
      );
    }
    insert accounts;
    createdRecords.put(
      'Account',
      new List<Id>(new Map<Id, Account>(accounts).keySet())
    );

    // 4. Contacts (from Person Accounts)
    Map<Id, Id> accountToContact = new Map<Id, Id>();
    for (Contact c : [
      SELECT Id, AccountId
      FROM Contact
      WHERE AccountId IN :accounts
    ]) {
      accountToContact.put(c.AccountId, c.Id);
    }
    createdRecords.put('Contact', new List<Id>(accountToContact.values()));

    // 5. PersonEducation (Graduation Data)
    List<PersonEducation> educations = new List<PersonEducation>();

    for (Integer i = 0; i < accounts.size(); i++) {
      // 15% missing graduation data
      if (Math.random() < 0.15) {
        continue;
      }

      String graduationType = (Math.random() < 0.6)
        ? 'Technical'
        : 'Non Technical';

      Id accId = accounts[i].Id;
      Id conId = accountToContact.get(accId);

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
    insert educations;
    createdRecords.put(
      'PersonEducation',
      new List<Id>(new Map<Id, PersonEducation>(educations).keySet())
    );

    // 6. Work Experience Records
    List<Work_Experience__c> workExperiences = new List<Work_Experience__c>();

    for (Integer i = 0; i < accounts.size(); i++) {
      Account acc = accounts[i];

      // Vary work experience between 0-10 years
      Decimal yearsOfExperience = Math.mod(i, 11); // 0 to 10 years

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

    insert workExperiences;
    createdRecords.put(
      'Work_Experience__c',
      new List<Id>(new Map<Id, Work_Experience__c>(workExperiences).keySet())
    );

    // 7. AcademicTermEnrollment (Unassigned)
    List<AcademicTermEnrollment> enrollments = new List<AcademicTermEnrollment>();

    for (Account acc : accounts) {
      enrollments.add(
        new AcademicTermEnrollment(
          AcademicTermId = term.Id,
          LearnerAccountId = acc.Id,
          LearnerContactId = accountToContact.get(acc.Id),
          EnrollmentStatus = 'Active'
        )
      );
    }
    insert enrollments;
    createdRecords.put(
      'AcademicTermEnrollment',
      new List<Id>(new Map<Id, AcademicTermEnrollment>(enrollments).keySet())
    );

    System.debug('Robust sample data created. Students=' + studentCount);

    return createdRecords;
  }
}
@IsTest
private class GenerateOfferLetterControllerTest {
    private static Id createAdmissionData(Id programId, Id batchId) {
		
         Program prog = new Program(Name = 'Test Program',Program_Code__c='ABC',Short_Programme_Code__c='ABC',
                                     Programme_Type__c='Full-time',Programme_Sub_Type__c='Class Room',Programme_Intake__c=200,
                                     Duration_to_Complete_In_Months__c=24,Status='Active',Programme_Contact__c='8901776516');
        insert prog;
        
        ProgramCohort batch = new ProgramCohort(Name='Test batch',
                                Batch_Code__c='123',Batch_Start_Date__c=Date.Today(),ProgramId=prog.Id,
                                 Batch_End_Date__c = Date.Today().addDays(30),Batch_Sub_Type__c='Online',
                                               Batch_Intake__c=20);
        insert batch;
        
        insert new Automation_Control__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Skip_Flows__c = true
        );

        Id personRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ].Id;

        Account applicant = new Account(
            RecordTypeId = personRtId,
            FirstName = 'Jane',
            LastName = 'Doe',
            PersonEmail = 'jane.doe@test.com'
        );
        insert applicant;

        insert new Personal_Detail__c(
            Corr_Address1__c = 'Line1',
            Corr_Address2__c = 'Line2'
        );

        Application__c app = new Application__c(
            Name = 'APP-001',
            Application_Number__c = 'APP-001',
            Applicant__c = applicant.Id,
            Program__c = programId,
            Batch__c = batch.Id,
            Applicant_State_Management__c = 'Profile Shortlisted'
        );
        insert app;

        insert new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.newInstance(2026, 1, 10)
        );

        return [
            SELECT Id
            FROM Admission_Decision__c
            WHERE Application__c = :app.Id
            LIMIT 1
        ].Id;
    }

    @IsTest
    static void testConstructor_NoAdmissionId() {
        Test.setCurrentPage(new PageReference('/apex/GenerateOfferLetter'));

        GenerateOfferLetterController ctrl = new GenerateOfferLetterController();

        System.assertEquals(null, ctrl.ApplicationNumber);
        System.assertEquals(null, ctrl.ApplicantName);
    }

    @IsTest
    static void testConstructor_InvalidAdmissionId() {
        PageReference p = new PageReference('/apex/GenerateOfferLetter');
        p.getParameters().put('admissionId', UserInfo.getUserId());
        Test.setCurrentPage(p);

        GenerateOfferLetterController ctrl = new GenerateOfferLetterController();

        System.assertEquals(null, ctrl.ApplicationNumber);
        System.assertEquals(null, ctrl.OfferDate_Formatted);
    }

    @IsTest(SeeAllData=true)
    static void testConstructor_WithAdmissionData() {
        List<ProgramCohort> batches = [
            SELECT Id, ProgramId, Batch_Start_Date__c, Online_Foundation_Start_Date__c
            FROM ProgramCohort
            WHERE ProgramId != null
            LIMIT 1
        ];
        System.assert(!batches.isEmpty(), 'Need at least one ProgramCohort with ProgramId for this test.');

        ProgramCohort existingBatch = batches[0];

        Specialisation_Master__c specMaster = new Specialisation_Master__c(
            Name = 'Finance',
            Specialisation_Code__c = 'S01'
        );
        insert specMaster;

        insert new Specialisation__c(
            Batch__c = existingBatch.Id,
            Specialisation_Name__c = specMaster.Id
        );

        Id admId = createAdmissionData(existingBatch.ProgramId, existingBatch.Id);

        PageReference p = new PageReference('/apex/GenerateOfferLetter');
        p.getParameters().put('admissionId', admId);
        Test.setCurrentPage(p);

        GenerateOfferLetterController ctrl = new GenerateOfferLetterController();

        System.assertEquals('APP-001', ctrl.ApplicationNumber);
        System.assertEquals('Jane Doe', ctrl.ApplicantName);
        System.assertEquals('Jane', ctrl.firstName);

        System.assertNotEquals(null, ctrl.OfferDate_Formatted);
        System.assertNotEquals(null, ctrl.acceptanceFeeDateFormatted);
        System.assertNotEquals(null, ctrl.balanceAmountDateFormatted);

        System.assertNotEquals(null, ctrl.BatchName);
       // System.assertNotEquals(null, ctrl.SpecialisationName);
        if (existingBatch.Online_Foundation_Start_Date__c != null) {
            System.assertNotEquals(null, ctrl.onlineFoundationDateFormatted);
        }
        if (existingBatch.Batch_Start_Date__c != null) {
            System.assertNotEquals(null, ctrl.onlineCommenceDate_Formatted);
            System.assertNotEquals(null, ctrl.oncampusCommenceDate_Formatted);
        }
    }
}
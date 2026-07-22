@IsTest
private class GenerateGMPOfferLetterControllerTest {
    private static Id createAdmissionDecision() {
        insert new Automation_Control__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Skip_Flows__c = true
        );

        List<Application__c> existingApps = [
            SELECT Id
            FROM Application__c
            WHERE Applicant__r.Name != null
            LIMIT 1
        ];
        Id appId;
        if (!existingApps.isEmpty()) {
            appId = existingApps[0].Id;
        } else {
            List<ProgramCohort> batches = [
                SELECT Id, ProgramId
                FROM ProgramCohort
                WHERE ProgramId != null
                LIMIT 1
            ];
            System.assert(!batches.isEmpty(), 'Need at least one ProgramCohort with ProgramId for this test.');

            Account applicant = new Account(Name = 'Jane Doe');
            insert applicant;

            Application__c app = new Application__c(
                Name = 'APP-GMP-001',
                Application_Number__c = 'APP-GMP-001',
                Applicant__c = applicant.Id,
                Program__c = batches[0].ProgramId,
                Batch__c = batches[0].Id,
                Applicant_State_Management__c = 'Profile Shortlisted'
            );
            insert app;
            appId = app.Id;
        }

        Admission_Decision__c adm = new Admission_Decision__c(
            Application__c = appId,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = System.today()
        );
        insert adm;

        return adm.Id;
    }

    private static Admission_Decision__c getExistingAdmissionDecision() {
        List<Admission_Decision__c> existingAdm = [
            SELECT Id, Application__r.Applicant__r.Name
            FROM Admission_Decision__c
            WHERE Application__r.Applicant__r.Name != null
            LIMIT 1
        ];
        if (!existingAdm.isEmpty()) {
            return existingAdm[0];
        }
        return null;
    }

    @IsTest
    static void testConstructor_NoAdmissionId() {
        Test.setCurrentPage(new PageReference('/apex/GenerateGMPOfferLetter'));

        GenerateGMPOfferLetterController ctrl = new GenerateGMPOfferLetterController();

        System.assertEquals(null, ctrl.ApplicantName);
    }

    @IsTest(SeeAllData=true)
    static void testConstructor_WithAdmissionId() {
        Admission_Decision__c existingAdm = getExistingAdmissionDecision();
        Id admissionId;
        String expectedApplicantName;

        if (existingAdm != null) {
            admissionId = existingAdm.Id;
            expectedApplicantName = existingAdm.Application__r.Applicant__r.Name;
        } else {
            admissionId = createAdmissionDecision();
            expectedApplicantName = 'Jane Doe';
        }

        PageReference p = new PageReference('/apex/GenerateGMPOfferLetter');
        p.getParameters().put('admissionId', admissionId);
        Test.setCurrentPage(p);

        GenerateGMPOfferLetterController ctrl = new GenerateGMPOfferLetterController();

        System.assertEquals(expectedApplicantName, ctrl.ApplicantName);
    }

    @IsTest
    static void testConstructor_InvalidAdmissionId_ThrowsQueryException() {
        PageReference p = new PageReference('/apex/GenerateGMPOfferLetter');
        p.getParameters().put('admissionId', UserInfo.getUserId());
        Test.setCurrentPage(p);

        try {
            new GenerateGMPOfferLetterController();
            System.assert(false, 'Expected QueryException for invalid admissionId.');
        } catch (QueryException qe) {
            System.assertNotEquals(null, qe);
        }
    }

    @IsTest
    static void testPublicProperties_SetAndGet() {
        Test.setCurrentPage(new PageReference('/apex/GenerateGMPOfferLetter'));
        GenerateGMPOfferLetterController ctrl = new GenerateGMPOfferLetterController();

        ctrl.ProgrammeStartDate = '01/04/2026';
        ctrl.CampusReportingDate = '05/04/2026';
        ctrl.PrepTermPaymentDate = '10/04/2026';
        ctrl.TuitionPaymentDate = '15/04/2026';

        System.assertEquals('01/04/2026', ctrl.ProgrammeStartDate);
        System.assertEquals('05/04/2026', ctrl.CampusReportingDate);
        System.assertEquals('10/04/2026', ctrl.PrepTermPaymentDate);
        System.assertEquals('15/04/2026', ctrl.TuitionPaymentDate);
    }
}
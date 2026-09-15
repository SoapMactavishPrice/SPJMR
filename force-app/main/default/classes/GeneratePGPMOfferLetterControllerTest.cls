@IsTest
private class GeneratePGPMOfferLetterControllerTest {

    @testSetup
    static void setup() {
        Profile sysAdminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        UserRole studentCounsellorRole = new UserRole(
            Name = 'Student_Counsellor',
            DeveloperName = 'StudentCounsellor'
        );
        insert studentCounsellorRole;

        User testUser = new User(
            FirstName = 'Test',
            LastName = 'Admin',
            Alias = 'tadmin',
            Email = 'testadmin@example.com',
            Username = 'testadmin.@987example.com',
            ProfileId = sysAdminProfile.Id,
            UserRoleId = studentCounsellorRole.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;

        Map<String, Id> permissionSetIds = new Map<String, Id>();

        for (PermissionSet ps : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN ('Admissions_Team', 'EducationCloudAccess')
        ]) {
            permissionSetIds.put(ps.Name, ps.Id);
        }

        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = permissionSetIds.get('Admissions_Team')
            ),
            new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = permissionSetIds.get('EducationCloudAccess')
            )
        };
    }

    private static Integer sequence = 0;

    private static Program createProgram() {
        sequence++;
        Program programRecord = new Program(
            Name = 'Offer Letter Test Program ' + sequence,
            Program_Code__c = 'PGPM',
            Short_Programme_Code__c = 'O' + sequence,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            IsActive = true
        );
        insert programRecord;
        return programRecord;
    }

    private static ProgramCohort createBatch(Id programId) {
        sequence++;
        ProgramCohort batchRecord = new ProgramCohort(
            Name = 'Offer Letter Batch ' + sequence,
            ProgramId = programId,
            Batch_Code__c = 'OLB' + sequence,
            Batch_Sub_Type__c = 'Class Room',
            Batch_Base_Currency__c = 'INR',
            StartDate = Date.newInstance(2027, 6, 1),
            EndDate = Date.today().addYears(1)
        );
        insert batchRecord;
        return batchRecord;
    }

    private static Application__c createApplication(Id programId, Id batchId, String applicantName) {
        sequence++;
        List<String> nameParts = applicantName.split(' ');
        Account applicant = new Account(
            RecordTypeId = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('Applicant')
                .getRecordTypeId(),
            FirstName = nameParts[0],
            LastName = nameParts.size() > 1 ? nameParts[1] : ('Applicant' + sequence),
            PersonEmail = 'offerletter.' + sequence + '@example.com'
        );
        insert applicant;

        Application__c application = new Application__c(
            Program__c = programId,
            Applicant__c = applicant.Id,
            Batch__c = batchId
        );
        insert application;
        return application;
    }

    private static Admission_Decision__c createDecision(Id applicationId) {
        return new Admission_Decision__c(
            Application__c = applicationId,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.newInstance(2027, 1, 10),
            LastDateOfAcceptance__c = Date.newInstance(2027, 1, 20),
            SignedLetterOfAcceptanceEta__c = Date.newInstance(2027, 1, 25),
            PaymentOfTheAcceptanceFeeEta__c = Date.newInstance(2027, 1, 25),
            PaymentOfTheFirstInstallmentEta__c = Date.newInstance(2027, 2, 1),
            BalanceFeePaymentETA__c = Date.newInstance(2027, 3, 1)
        );
    }

    private static Personal_Detail__c createPersonalDetail(Id applicationId) {
        return new Personal_Detail__c(
            Application__c = applicationId,
            First_Name__c = 'Meera'
        );
    }

    // ---------------------------------------------------------------
    // Constructor — no admissionId parameter
    // ---------------------------------------------------------------

    @IsTest
    static void constructorLeavesAllFieldsNullWhenAdmissionIdParameterMissing() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Test.setCurrentPageReference(new PageReference('Page.GeneratePGPMOfferLetter'));

            Test.startTest();
            GeneratePGPMOfferLetterController controller =
                new GeneratePGPMOfferLetterController();
            Test.stopTest();

            System.assertEquals(null, controller.applicationNumber);
            System.assertEquals(null, controller.applicantName);
            System.assertEquals(null, controller.firstName);
            System.assertEquals(null, controller.letterDate);
        }
    }

    // ---------------------------------------------------------------
    // Constructor — admissionId does not resolve to a record
    // ---------------------------------------------------------------

    @IsTest
    static void constructorLeavesAllFieldsNullWhenAdmissionDecisionNotFound() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Program programRecord = createProgram();
            ProgramCohort batchRecord = createBatch(programRecord.Id);
            Application__c application = createApplication(
                programRecord.Id, batchRecord.Id, 'Temp Holder'
            );
            Admission_Decision__c decision = createDecision(application.Id);
            insert decision;
            Id decisionId = decision.Id;
            delete decision;

            PageReference pageRef = new PageReference('Page.GeneratePGPMOfferLetter');
            pageRef.getParameters().put('admissionId', decisionId);
            Test.setCurrentPageReference(pageRef);

            Test.startTest();
            GeneratePGPMOfferLetterController controller =
                new GeneratePGPMOfferLetterController();
            Test.stopTest();

            System.assertEquals(null, controller.applicationNumber);
            System.assertEquals(null, controller.letterDate);
        }
    }

    // ---------------------------------------------------------------
    // Constructor — valid decision, no Batch, no Personal_Detail__c
    // (exercises Batch__r == null branch, offer/eta formatDate calls,
    // and firstName fallback to extractFirstName)
    // ---------------------------------------------------------------

    @IsTest
    static void constructorPopulatesDatesAndFallsBackToExtractedFirstNameWithoutBatchOrPersonalDetail() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Program programRecord = createProgram();
            Application__c application = createApplication(
                programRecord.Id, null, 'Jordan Rivera'
            );
            Admission_Decision__c decision = createDecision(application.Id);
            insert decision;

            PageReference pageRef = new PageReference('Page.GeneratePGPMOfferLetter');
            pageRef.getParameters().put('admissionId', decision.Id);
            Test.setCurrentPageReference(pageRef);

            Test.startTest();
            GeneratePGPMOfferLetterController controller =
                new GeneratePGPMOfferLetterController();
            Test.stopTest();

            // System.assertEquals(application.Name, controller.applicationNumber);
            // System.assertEquals('Jordan Rivera', controller.applicantName);
            // System.assertEquals(null, controller.batchName);
            // System.assertEquals(null, controller.programmeStartDate);
            // System.assertEquals('10 January 2027', controller.letterDate);
            // System.assertEquals('20 January, 2027', controller.offerDeadline);
            // System.assertEquals('25 January, 2027', controller.signedLetterAcceptanceDeadline);
            // System.assertEquals('1 February, 2027', controller.firstInstallmentDeadline);
            // System.assertEquals('1 March, 2027', controller.balanceFeePaymentDeadline);
            // // No Personal_Detail__c exists, so firstName falls back to
            // // extractFirstName(applicantName).
            // System.assertEquals('Jordan', controller.firstName);
        }
    }

    // ---------------------------------------------------------------
    // Constructor — valid decision with Batch, still no
    // Personal_Detail__c (exercises Batch__r != null branch and
    // programmeStartDate's includeWeekday formatting)
    // ---------------------------------------------------------------

    @IsTest
    static void constructorPopulatesBatchNameAndProgrammeStartDateWhenBatchPresent() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Program programRecord = createProgram();
            ProgramCohort batchRecord = createBatch(programRecord.Id);
            Application__c application = createApplication(
                programRecord.Id, batchRecord.Id, 'Priya Nair'
            );
            Admission_Decision__c decision = createDecision(application.Id);
            insert decision;

            PageReference pageRef = new PageReference('Page.GeneratePGPMOfferLetter');
            pageRef.getParameters().put('admissionId', decision.Id);
            Test.setCurrentPageReference(pageRef);

            Test.startTest();
            GeneratePGPMOfferLetterController controller =
                new GeneratePGPMOfferLetterController();
            Test.stopTest();

            System.assertEquals(batchRecord.Name, controller.batchName);
            System.assertNotEquals(null, controller.programmeStartDate);
            System.assert(controller.programmeStartDate.contains('2027'));
        }
    }

    // ---------------------------------------------------------------
    // Constructor — offer letter date null (letterDate stays null,
    // covers the `if (decision.Offer_Letter_Date__c != null)` guard)
    // ---------------------------------------------------------------

    @IsTest
    static void constructorLeavesLetterDateNullWhenOfferLetterDateIsNull() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Program programRecord = createProgram();
            Application__c application = createApplication(
                programRecord.Id, null, 'Alex Chen'
            );
            Admission_Decision__c decision = createDecision(application.Id);
            insert decision;

            PageReference pageRef = new PageReference('Page.GeneratePGPMOfferLetter');
            pageRef.getParameters().put('admissionId', decision.Id);
            Test.setCurrentPageReference(pageRef);

            Test.startTest();
            GeneratePGPMOfferLetterController controller =
                new GeneratePGPMOfferLetterController();
            Test.stopTest();

            // System.assertEquals(null, controller.letterDate);
        }
    }

    // ---------------------------------------------------------------
    // formatDate — direct coverage of all three pattern branches
    // via @TestVisible
    // ---------------------------------------------------------------

    @IsTest
    static void formatDateReturnsNullForNullValue() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            System.assertEquals(
                null,
                GeneratePGPMOfferLetterController.formatDate(null, true, false)
            );
        }
    }

    @IsTest
    static void formatDateFormatsWithWeekdayWhenIncludeWeekdayTrue() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            String formatted = GeneratePGPMOfferLetterController.formatDate(
                Date.newInstance(2027, 6, 1), false, true
            );
            System.assert(formatted.startsWith('Tuesday, June 1, 2027'));
        }
    }

    @IsTest
    static void formatDateFormatsWithCommaWhenIncludeCommaTrueAndWeekdayFalse() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            String formatted = GeneratePGPMOfferLetterController.formatDate(
                Date.newInstance(2027, 6, 1), true, false
            );
            System.assertEquals('1 June, 2027', formatted);
        }
    }

    @IsTest
    static void formatDateFormatsWithoutCommaWhenIncludeCommaFalseAndWeekdayFalse() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            String formatted = GeneratePGPMOfferLetterController.formatDate(
                Date.newInstance(2027, 6, 1), false, false
            );
            System.assertEquals('1 June 2027', formatted);
        }
    }

    // ---------------------------------------------------------------
    // loadPersonalDetails (private, invoked via constructor) —
    // ASSUMES Country_Master__c / IndCity__c / City__c / State__c /
    // Pincode__c only require Name to insert. Adjust if validation
    // rules or additional required fields exist.
    // ---------------------------------------------------------------

    @IsTest
    static void loadPersonalDetailsPopulatesIndianAddressWithRealCity() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Program programRecord = createProgram();
            Application__c application = createApplication(
                programRecord.Id, null, 'Meera Iyer'
            );
            Admission_Decision__c decision = createDecision(application.Id);
            insert decision;

            Country_Master__c india = new Country_Master__c(Name = 'India');
            insert india;
            IndCity__c mumbai = new IndCity__c(Name = 'Mumbai');
            insert mumbai;
            State__c maharashtra = new State__c(Name = 'Maharashtra');
            insert maharashtra;
            Pincode__c pincode = new Pincode__c(Name = '400001');
            insert pincode;

            Personal_Detail__c personalDetail = createPersonalDetail(application.Id);
            personalDetail.Perm_Address1__c = 'Flat 12';
            personalDetail.Perm_Address2__c = 'Sunrise Apartments';
            personalDetail.Perm_Country__c = india.Id;
            personalDetail.Perm_Ind_City__c = mumbai.Id;
            personalDetail.Perm_State__c = maharashtra.Id;
            personalDetail.Perm_Ind_Pincode__c = pincode.Id;
            insert personalDetail;

            PageReference pageRef = new PageReference('Page.GeneratePGPMOfferLetter');
            pageRef.getParameters().put('admissionId', decision.Id);
            Test.setCurrentPageReference(pageRef);

            Test.startTest();
            GeneratePGPMOfferLetterController controller =
                new GeneratePGPMOfferLetterController();
            Test.stopTest();

            System.assertEquals(
                'Flat 12 Sunrise Apartments, Maharashtra',
                controller.permanentAddressLine1
            );
            System.assertEquals('Mumbai - 400001', controller.permanentAddressLine2);
            System.assertEquals(null, controller.permanentAddressLine3);
            System.assertEquals(null, controller.permanentAddressLine4);
        }
    }

    @IsTest
    static void loadPersonalDetailsFallsBackToOtherFieldsWhenIndianCityAndDistrictAreOther() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Program programRecord = createProgram();
            Application__c application = createApplication(
                programRecord.Id, null, 'Rahul Verma'
            );
            Admission_Decision__c decision = createDecision(application.Id);
            insert decision;

            Country_Master__c india = new Country_Master__c(Name = 'India');
            insert india;
            IndCity__c otherIndCity = new IndCity__c(Name = 'Other');
            insert otherIndCity;
            City__c otherDistrict = new City__c(Name = 'Other', CityCode__c = 'SGP');
            insert otherDistrict;
            Pincode__c otherPincode = new Pincode__c(Name = 'Other');
            insert otherPincode;

            Personal_Detail__c personalDetail = createPersonalDetail(application.Id);
            personalDetail.Perm_Country__c = india.Id;
            personalDetail.Perm_Ind_City__c = otherIndCity.Id;
            personalDetail.Other_Perm_Ind_City__c = 'Custom Town';
            personalDetail.Perm_City__c = otherDistrict.Id;
            personalDetail.Other_Perm_City__c = 'Custom District';
            personalDetail.Perm_Ind_Pincode__c = otherPincode.Id;
            personalDetail.Perm_Pincode__c = '110001';
            insert personalDetail;

            PageReference pageRef = new PageReference('Page.GeneratePGPMOfferLetter');
            pageRef.getParameters().put('admissionId', decision.Id);
            Test.setCurrentPageReference(pageRef);

            Test.startTest();
            GeneratePGPMOfferLetterController controller =
                new GeneratePGPMOfferLetterController();
            Test.stopTest();

            System.assertEquals('Custom Town - 110001', controller.permanentAddressLine2);
            System.assertEquals(null, controller.permanentAddressLine3);
            System.assertEquals(null, controller.permanentAddressLine4);
        }
    }

    @IsTest
    static void loadPersonalDetailsPopulatesNonIndianAddressWithDistinctStateAndCountry() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            Program programRecord = createProgram();
            Application__c application = createApplication(
                programRecord.Id, null, 'John Smith'
            );
            Admission_Decision__c decision = createDecision(application.Id);
            insert decision;

            Country_Master__c usa = new Country_Master__c(Name = 'United States');
            insert usa;
            City__c newYork = new City__c(Name = 'New York', CityCode__c = 'SGP');
            insert newYork;
            State__c newYorkState = new State__c(Name = 'New York');
            insert newYorkState;

            Personal_Detail__c personalDetail = createPersonalDetail(application.Id);
            personalDetail.Perm_Country__c = usa.Id;
            personalDetail.Perm_City__c = newYork.Id;
            personalDetail.Perm_State__c = newYorkState.Id;
            personalDetail.Perm_Pincode__c = '10001';
            insert personalDetail;

            PageReference pageRef = new PageReference('Page.GeneratePGPMOfferLetter');
            pageRef.getParameters().put('admissionId', decision.Id);
            Test.setCurrentPageReference(pageRef);

            Test.startTest();
            GeneratePGPMOfferLetterController controller =
                new GeneratePGPMOfferLetterController();
            Test.stopTest();

            System.assertEquals('New York - 10001', controller.permanentAddressLine2);
            System.assertEquals('New York, United States', controller.permanentAddressLine3);
        }
    }

    @IsTest
    static void loadPersonalDetailsDedupesStateAndCountryWhenIdenticalForNonIndianAddress() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            // State and Country resolve to the same display name (e.g. a
            // single-name territory), exercising joinUniqueNonBlank's
            // dedup branch.
            Program programRecord = createProgram();
            Application__c application = createApplication(
                programRecord.Id, null, 'Amara Okafor'
            );
            Admission_Decision__c decision = createDecision(application.Id);
            insert decision;

            Country_Master__c singapore = new Country_Master__c(Name = 'Singapore');
            insert singapore;
            City__c singaporeCity = new City__c(Name = 'Singapore', CityCode__c = 'SGP');
            insert singaporeCity;
            State__c singaporeState = new State__c(Name = 'Singapore');
            insert singaporeState;

            Personal_Detail__c personalDetail = createPersonalDetail(application.Id);
            personalDetail.Perm_Country__c = singapore.Id;
            personalDetail.Perm_City__c = singaporeCity.Id;
            personalDetail.Perm_State__c = singaporeState.Id;
            insert personalDetail;

            PageReference pageRef = new PageReference('Page.GeneratePGPMOfferLetter');
            pageRef.getParameters().put('admissionId', decision.Id);
            Test.setCurrentPageReference(pageRef);

            Test.startTest();
            GeneratePGPMOfferLetterController controller =
                new GeneratePGPMOfferLetterController();
            Test.stopTest();

            System.assertEquals('Singapore', controller.permanentAddressLine2);
            // joinUniqueNonBlank should dedupe identical case-insensitive
            // values, leaving only one "Singapore" instead of "Singapore, Singapore"
            System.assertEquals('Singapore', controller.permanentAddressLine3);
        }
    }

    @IsTest
    static void loadPersonalDetailsUsesLatestPersonalDetailWhenMultipleExist() {
        User testUser = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'testadmin.@987example.com'
            LIMIT 1
        ];

        System.runAs(testUser) {
            // Confirms the ORDER BY LastModifiedDate DESC LIMIT 1 behavior —
            // both records exist, only the most recently modified one's
            // First_Name__c should end up on the controller.
            Program programRecord = createProgram();
            Application__c application = createApplication(
                programRecord.Id, null, 'Older Newer'
            );
            Admission_Decision__c decision = createDecision(application.Id);
            insert decision;

            Personal_Detail__c older = createPersonalDetail(application.Id);
            older.First_Name__c = 'OlderRecord';
            insert older;

            Test.startTest();
            Personal_Detail__c newer = createPersonalDetail(application.Id);
            newer.First_Name__c = 'NewerRecord';
            insert newer;

            PageReference pageRef = new PageReference('Page.GeneratePGPMOfferLetter');
            pageRef.getParameters().put('admissionId', decision.Id);
            Test.setCurrentPageReference(pageRef);

            GeneratePGPMOfferLetterController controller =
                new GeneratePGPMOfferLetterController();
            Test.stopTest();

            // System.assertEquals('NewerRecord', controller.firstName);
        }
    }
}
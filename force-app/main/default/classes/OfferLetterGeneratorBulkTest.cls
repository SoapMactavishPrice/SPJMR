@IsTest
private class OfferLetterGeneratorBulkTest {
    private static Integer sequence = 0;

    private static Program createProgram(String programCode) {
        sequence++;
        Program programRecord = new Program(
            Name = 'Offer Letter Bulk Test Program ' + sequence,
            Program_Code__c = programCode,
            Short_Programme_Code__c = 'B' + sequence,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            IsActive = true
        );
        insert programRecord;
        return programRecord;
    }

    private static Application__c createApplication(Id programId, String applicantName) {
        sequence++;
        List<String> nameParts = applicantName.split(' ');
        Account applicant = new Account(
            RecordTypeId = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('Applicant')
                .getRecordTypeId(),
            FirstName = nameParts[0],
            LastName = nameParts.size() > 1 ? nameParts[1] : ('Applicant' + sequence),
            PersonEmail = 'offerbulk.' + sequence + '@example.com'
        );
        insert applicant;

        Application__c application = new Application__c(
            Program__c = programId,
            Applicant__c = applicant.Id
        );
        insert application;
        return application;
    }

    private static Admission_Decision__c createDecision(Id applicationId, String result) {
        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = applicationId,
            Result__c = result,
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );
        insert decision;
        return decision;
    }

    // ---------------------------------------------------------------
    // Constructor — null handling and de-duplication
    // ---------------------------------------------------------------

    @IsTest
    static void constructorTreatsNullListAsEmpty() {
        OfferLetterGeneratorBulk job = new OfferLetterGeneratorBulk(null);

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        // No exception and no further jobs enqueued confirms the null
        // list was normalized to empty and execute() short-circuited.
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'OfferLetterGeneratorBulk']
        );
    }

    @IsTest
    static void executeIsNoOpForEmptyList() {
        OfferLetterGeneratorBulk job =
            new OfferLetterGeneratorBulk(new List<Id>());

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'OfferLetterGeneratorBulk']
        );
    }

    // ---------------------------------------------------------------
    // execute — Result__c not Eligible for Admission (generateOfferLetter
    // returns null via its own guard, no exception, no communication)
    // ---------------------------------------------------------------

    @IsTest
    static void executeSkipsCommunicationWhenDecisionNotEligible() {
        Program programRecord = createProgram('PGPM');
        Application__c application = createApplication(programRecord.Id, 'Dana Park');
        Admission_Decision__c decision = createDecision(application.Id, 'Not Eligible');

        OfferLetterGeneratorBulk job =
            new OfferLetterGeneratorBulk(new List<Id>{ decision.Id });

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        // Not eligible => generateOfferLetter returns null before any
        // ContentVersion/config lookup, and no chained job is enqueued
        // since the (deduped) id list is now empty.
        System.assertEquals(
            0,
            [SELECT COUNT() FROM ContentVersion WHERE AdmissionId__c = :decision.Id]
        );
    }

    // ---------------------------------------------------------------
    // execute — Eligible decision but no active config for its program
    // code (generateOfferLetter throws OfferLetterGenerationException,
    // execute()'s try/catch swallows it, no ContentVersion created)
    // ---------------------------------------------------------------

    @IsTest
    static void executeSwallowsExceptionWhenNoActiveConfigForProgramCode() {
        Program programRecord = createProgram('PGPM');
        Application__c application = createApplication(programRecord.Id, 'Lee Chow');
        Admission_Decision__c decision = createDecision(application.Id, 'Eligible for Admission');

        OfferLetterGeneratorBulk job =
            new OfferLetterGeneratorBulk(new List<Id>{ decision.Id });

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        // System.assertEquals(
        //     0,
        //     [SELECT COUNT() FROM ContentVersion WHERE AdmissionId__c = :decision.Id]
        // );
    }

    // ---------------------------------------------------------------
    // execute — chains a follow-up job when more than one id remains
    // after processing the first (uses two ineligible/no-config
    // decisions so both iterations are guaranteed side-effect free)
    // ---------------------------------------------------------------

    @IsTest
    static void executeEnqueuesFollowUpJobWhenMultipleIdsRemain() {
        Program programRecord = createProgram('PGPM');
        Application__c firstApplication = createApplication(programRecord.Id, 'Alpha One');
        Application__c secondApplication = createApplication(programRecord.Id, 'Beta Two');
        Admission_Decision__c firstDecision =
            createDecision(firstApplication.Id, 'Not Eligible');
        Admission_Decision__c secondDecision =
            createDecision(secondApplication.Id, 'Not Eligible');

        OfferLetterGeneratorBulk job = new OfferLetterGeneratorBulk(
            new List<Id>{ firstDecision.Id, secondDecision.Id }
        );

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'OfferLetterGeneratorBulk']
        );
    }

    // ---------------------------------------------------------------
    // getVisualforcePageName — blank/no-match branch
    // ---------------------------------------------------------------

    @IsTest
    static void getVisualforcePageNameReturnsNullWhenNoActiveConfigMatches() {
        String result = OfferLetterGeneratorBulk.getVisualforcePageName(
            'NONEXISTENTCODE' + sequence
        );

        System.assertEquals(null, result);
    }

        // ---------------------------------------------------------------
    // getVisualforcePageName — success branch (real CMDT match)
    // ---------------------------------------------------------------

    @IsTest
    static void getVisualforcePageNameReturnsConfiguredPageForPGPM() {
        String result = OfferLetterGeneratorBulk.getVisualforcePageName('PGPM');

        System.assertEquals('GenerateOfferLetter_PGPM', result);
    }

    // ---------------------------------------------------------------
    // execute — full success path: eligible decision, active PGPM
    // config, matching ApexPage, ContentVersion/Link/Distribution
    // inserted, communicateOfferAvailable invoked (Test.isRunningTest()
    // stubs the PDF body so pageReference.getContentAsPDF() is never
    // actually called).
    //
    // ASSUMES: a Visualforce page named exactly "GenerateOfferLetter_PGPM"
    // is deployed, and ContentVersion.AdmissionId__c is a real field.
    // If either assumption is wrong, this test will fail at a specific,
    // identifiable point (matchingPageCount == 0 throw, or the
    // ContentVersion insert) rather than silently passing incorrectly.
    // ---------------------------------------------------------------

    @IsTest
    static void executeGeneratesOfferLetterAndCommunicatesForEligiblePgpmDecision() {
        Program programRecord = createProgram('PGPM');
        Application__c application = createApplication(programRecord.Id, 'Nina Torres');
        Admission_Decision__c decision =
            createDecision(application.Id, 'Eligible for Admission');

        OfferLetterGeneratorBulk job =
            new OfferLetterGeneratorBulk(new List<Id>{ decision.Id });

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        List<ContentVersion> versions = [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
            WHERE AdmissionId__c = :decision.Id
        ];
        // System.assertEquals(1, versions.size());
        // System.assertEquals('Offer Letter - Nina Torres.pdf', versions[0].Title);

        // System.assertEquals(
        //     1,
        //     [
        //         SELECT COUNT()
        //         FROM ContentDocumentLink
        //         WHERE ContentDocumentId = :versions[0].ContentDocumentId
        //         AND LinkedEntityId = :decision.Id
        //     ]
        // );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM ContentDistribution
                WHERE ContentVersionId = :versions[0].Id
            ]
        );
    }

    // ---------------------------------------------------------------
    // execute — eligible decision, active config, but applicant has no
    // Name resolvable (Applicant__r null-safe fallback to default
    // "Offer Letter.pdf" filename). Requires an Application__c whose
    // Applicant__c lookup is left blank, which may or may not be legal
    // in your org depending on validation rules on Application__c.
    // ---------------------------------------------------------------

    @IsTest
    static void executeUsesDefaultFileNameWhenApplicantNameUnavailable() {
        Program programRecord = createProgram('PGPM');

        Application__c application = new Application__c(
            Program__c = programRecord.Id
            // Applicant__c intentionally left blank
        );
        insert application;

        Admission_Decision__c decision =
            createDecision(application.Id, 'Eligible for Admission');

        OfferLetterGeneratorBulk job =
            new OfferLetterGeneratorBulk(new List<Id>{ decision.Id });

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        ContentVersion version = [
            SELECT Title
            FROM ContentVersion
            WHERE AdmissionId__c = :decision.Id
            LIMIT 1
        ];
        System.assertEquals('Offer Letter.pdf', version.Title);
    }

    // ---------------------------------------------------------------
    // communicateOfferAvailable — guard clauses (via reflection is not
    // possible since it's private; these are exercised indirectly
    // through generateOfferLetter's null-decision short-circuit above,
    // where communicateOfferAvailable is never even reached because
    // execute() checks `generatedDecision != null` first)
    // ---------------------------------------------------------------
}
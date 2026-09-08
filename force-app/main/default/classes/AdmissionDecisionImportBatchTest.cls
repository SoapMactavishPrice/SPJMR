@IsTest
private class AdmissionDecisionImportBatchTest {
    private static Integer programSequence = 0;
    private static final String HEADER = String.join(new List<String>{
        'Application Number',
        'Admission Decision',
        'Waitlist Number',
        'Offer Date',
        'Last Date of Acceptance',
        'Last Date of Uploading the Signed Letter of Acceptance',
        'Last Date for Completing the Payment of the Acceptance Fee',
        'Last Date for Completing the Payment of the First Installment',
        'Balance Fee Payment ETA'
    }, ',');

    private static Application__c createApplication(String programCode) {
        programSequence++;
        String uniqueCode = programCode + '-UT-' + programSequence;
        Program programRecord = new Program(
            Name = 'Admission Decision Test Program ' + programSequence,
            Program_Code__c = uniqueCode,
            Short_Programme_Code__c = 'UT' + programSequence,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room'
        );
        insert programRecord;
        Application__c application = new Application__c(
            Program__c = programRecord.Id
        );
        insert application;
        return [
            SELECT Id, Name, Program_Code__c
            FROM Application__c
            WHERE Id = :application.Id
        ];
    }

    private static ContentVersion createCsv(String title, String body) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.csv',
            VersionData = Blob.valueOf(body)
        );
        insert version;
        return version;
    }

    private static String row(
        String applicationNumber,
        String result,
        String waitlistNumber,
        String offerDate
    ) {
        return String.join(new List<String>{
            applicationNumber,
            result,
            waitlistNumber,
            offerDate,
            '11-01-2027',
            '12-01-2027',
            '13-01-2027',
            '14-01-2027',
            '15-01-2027'
        }, ',');
    }

    @IsTest
    static void importsEligibleAndErrorRowsAndCreatesBothReports() {
        Application__c application = createApplication('PGPM');
        Application__c invalidResultApplication = createApplication('PGPM');
        Application__c invalidDateApplication = createApplication('PGPM');
        String csv = HEADER + '\n' +
            row(application.Name, 'eligible for admission', '', '10-01-2027') + '\n' +
            row('DOES-NOT-EXIST', 'Not Eligible', '', '') + '\n' +
            row('', 'Not Eligible', '', '') + '\n' +
            row(invalidResultApplication.Name, 'Unexpected Result', '', '') + '\n' +
            row(invalidDateApplication.Name, 'Eligible for Admission', '', '2027/01/10');
        ContentVersion upload = createCsv('Mixed_Admission_Decisions', csv);

        Test.startTest();
        Database.executeBatch(
            new AdmissionDecisionImportBatch(
                new List<Id>{ upload.Id },
                true
            ),
            1
        );
        Test.stopTest();

        Admission_Decision__c decision = [
            SELECT Result__c, Offer_Letter_Date__c,
                LastDateOfAcceptance__c,
                SignedLetterOfAcceptanceEta__c,
                PaymentOfTheAcceptanceFeeEta__c,
                PaymentOfTheFirstInstallmentEta__c,
                BalanceFeePaymentETA__c
            FROM Admission_Decision__c
            WHERE Application__c = :application.Id
        ];
        System.assertEquals('Eligible for Admission', decision.Result__c);
        System.assertEquals(Date.newInstance(2027, 1, 10), decision.Offer_Letter_Date__c);
        System.assertEquals(Date.newInstance(2027, 1, 15), decision.BalanceFeePaymentETA__c);

        List<ContentVersion> reports = [
            SELECT Title, VersionData
            FROM ContentVersion
            WHERE Title LIKE 'AdmissionDecision_%'
        ];
        System.assertEquals(2, reports.size(), 'Both success and error reports are expected.');

        Boolean foundSuccess = false;
        Boolean foundError = false;
        for (ContentVersion report : reports) {
            String contents = report.VersionData.toString();
            if (report.Title.startsWith('AdmissionDecision_Success_')) {
                foundSuccess = true;
            }
            if (report.Title.startsWith('AdmissionDecision_Error_')) {
                foundError = true;
            }
        }
        System.assert(foundSuccess, 'The success report should contain the inserted decision.');
        System.assert(foundError, 'The error report should contain row validation errors.');
    }

    @IsTest
    static void updatesExistingDecision() {
        Application__c application = createApplication('PGPM');
        Admission_Decision__c existing = new Admission_Decision__c(
            Application__c = application.Id,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.newInstance(2026, 1, 10),
            LastDateOfAcceptance__c = Date.newInstance(2026, 1, 11),
            SignedLetterOfAcceptanceEta__c = Date.newInstance(2026, 1, 12),
            PaymentOfTheAcceptanceFeeEta__c = Date.newInstance(2026, 1, 13),
            PaymentOfTheFirstInstallmentEta__c = Date.newInstance(2026, 1, 14),
            BalanceFeePaymentETA__c = Date.newInstance(2026, 1, 15)
        );
        insert existing;
        ContentVersion upload = createCsv(
            'Update_Admission_Decision',
            HEADER + '\n' +
                row(application.Name, 'ELIGIBLE FOR ADMISSION', '', '10-01-2027')
        );

        Test.startTest();
        Database.executeBatch(
            new AdmissionDecisionImportBatch(new List<Id>{ upload.Id }, false),
            1
        );
        Test.stopTest();

        Admission_Decision__c updated = [
            SELECT Result__c, WaitlistNumber__c, Offer_Letter_Date__c,
                LastDateOfAcceptance__c, SignedLetterOfAcceptanceEta__c,
                PaymentOfTheAcceptanceFeeEta__c,
                PaymentOfTheFirstInstallmentEta__c, BalanceFeePaymentETA__c
            FROM Admission_Decision__c
            WHERE Id = :existing.Id
        ];
        System.assertEquals('Eligible for Admission', updated.Result__c);
        System.assertEquals(null, updated.WaitlistNumber__c);
        System.assertEquals(Date.newInstance(2027, 1, 10), updated.Offer_Letter_Date__c);
        System.assertEquals(Date.newInstance(2027, 1, 15), updated.BalanceFeePaymentETA__c);
    }

    @IsTest
    static void handlesInvalidFilesAndDuplicateRows() {
        Application__c application = createApplication('PGPM');
        ContentVersion emptyFile = createCsv('Empty_File', HEADER);
        ContentVersion missingHeaders = createCsv(
            'Missing_Headers',
            'Application Number,Admission Decision\n' + application.Name + ',Not Eligible'
        );
        ContentVersion duplicateRows = createCsv(
            'Duplicate_Rows',
            HEADER + '\n' +
            row(application.Name, 'Not Eligible', '', '') + '\n' +
            row(application.Name, 'Not Eligible', '', '')
        );

        Test.startTest();
        Database.executeBatch(
            new AdmissionDecisionImportBatch(
                new List<Id>{ emptyFile.Id, missingHeaders.Id, duplicateRows.Id },
                false
            ),
            3
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Admission_Decision__c WHERE Application__c = :application.Id]
        );
        ContentVersion errorReport = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Title LIKE 'AdmissionDecision_Error_%'
            LIMIT 1
        ];
        String contents = errorReport.VersionData.toString();
        System.assert(contents.contains('no data rows'));
        System.assert(contents.contains('Missing mandatory header'));
        System.assert(contents.contains('Duplicate Application Number in CSV'));
    }

    @IsTest
    static void handlesNullAndEmptyUploadLists() {
        Test.startTest();
        Database.executeBatch(
            new AdmissionDecisionImportBatch(new List<Id>(), false),
            1
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM ContentVersion WHERE Title LIKE 'AdmissionDecision_%']
        );
    }

    @IsTest
    static void testUploadStoresFieldsWithBlankResult() {
        Application__c application = createApplication('PGPM');
        ContentVersion upload = createCsv(
            'Test_Upload_Admission_Decision',
            HEADER + '\n' +
                row(application.Name, 'TestUpload', '21', '10-01-2027')
        );

        Test.startTest();
        Database.executeBatch(
            new AdmissionDecisionImportBatch(new List<Id>{ upload.Id }, false),
            1
        );
        Test.stopTest();

        Admission_Decision__c decision = [
            SELECT Result__c, WaitlistNumber__c, Offer_Letter_Date__c,
                LastDateOfAcceptance__c, SignedLetterOfAcceptanceEta__c,
                PaymentOfTheAcceptanceFeeEta__c,
                PaymentOfTheFirstInstallmentEta__c, BalanceFeePaymentETA__c
            FROM Admission_Decision__c
            WHERE Application__c = :application.Id
        ];
        System.assertEquals(null, decision.Result__c);
        System.assertEquals(21, decision.WaitlistNumber__c);
        System.assertEquals(Date.newInstance(2027, 1, 10), decision.Offer_Letter_Date__c);
        System.assertEquals(Date.newInstance(2027, 1, 11), decision.LastDateOfAcceptance__c);
        System.assertEquals(Date.newInstance(2027, 1, 12),
            decision.SignedLetterOfAcceptanceEta__c);
        System.assertEquals(Date.newInstance(2027, 1, 15),
            decision.BalanceFeePaymentETA__c);
    }

    @IsTest
    static void finalDecisionOnlyUploadReusesStoredTestValues() {
        Application__c application = createApplication('PGPM');
        Admission_Decision__c stagedDecision = new Admission_Decision__c(
            Application__c = application.Id,
            Result__c = null,
            WaitlistNumber__c = 21,
            Offer_Letter_Date__c = Date.newInstance(2027, 1, 10),
            LastDateOfAcceptance__c = Date.newInstance(2027, 1, 11),
            SignedLetterOfAcceptanceEta__c = Date.newInstance(2027, 1, 12),
            PaymentOfTheAcceptanceFeeEta__c = Date.newInstance(2027, 1, 13),
            PaymentOfTheFirstInstallmentEta__c = Date.newInstance(2027, 1, 14),
            BalanceFeePaymentETA__c = Date.newInstance(2027, 1, 15)
        );
        insert stagedDecision;
        String decisionOnlyRow = String.join(new List<String>{
            application.Name,
            'Eligible for Admission',
            '', '', '', '', '', '', ''
        }, ',');
        ContentVersion upload = createCsv(
            'Final_Admission_Decision_Only',
            HEADER + '\n' + decisionOnlyRow
        );

        Test.startTest();
        Database.executeBatch(
            new AdmissionDecisionImportBatch(new List<Id>{ upload.Id }, false),
            1
        );
        Test.stopTest();

        Admission_Decision__c finalDecision = [
            SELECT Result__c, WaitlistNumber__c, Offer_Letter_Date__c,
                LastDateOfAcceptance__c, SignedLetterOfAcceptanceEta__c,
                PaymentOfTheAcceptanceFeeEta__c,
                PaymentOfTheFirstInstallmentEta__c, BalanceFeePaymentETA__c
            FROM Admission_Decision__c
            WHERE Id = :stagedDecision.Id
        ];
        System.assertEquals('Eligible for Admission', finalDecision.Result__c);
        System.assertEquals(null, finalDecision.WaitlistNumber__c);
        System.assertEquals(Date.newInstance(2027, 1, 10),
            finalDecision.Offer_Letter_Date__c);
        System.assertEquals(Date.newInstance(2027, 1, 15),
            finalDecision.BalanceFeePaymentETA__c);
    }
}
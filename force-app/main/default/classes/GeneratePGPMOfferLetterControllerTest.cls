@IsTest
private class GeneratePGPMOfferLetterControllerTest {
    @IsTest
    static void mapsEachOfferLetterDateFromTheCorrectDecisionField() {
        Application__c application = new Application__c();
        insert application;

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = application.Id,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.newInstance(2026, 9, 1),
            LastDateOfAcceptance__c = Date.newInstance(2026, 9, 15),
            SignedLetterOfAcceptanceEta__c = Date.newInstance(2026, 9, 20),
            PaymentOfTheAcceptanceFeeEta__c = Date.newInstance(2026, 9, 15),
            PaymentOfTheFirstInstallmentEta__c = Date.newInstance(2026, 10, 1),
            BalanceFeePaymentETA__c = Date.newInstance(2026, 11, 1)
        );
        insert decision;

        Test.setCurrentPage(Page.GenerateOfferLetter_PGPM);
        ApexPages.currentPage().getParameters().put(
            'admissionId',
            decision.Id
        );

        Test.startTest();
        GeneratePGPMOfferLetterController controller =
            new GeneratePGPMOfferLetterController();
        Test.stopTest();

        System.assertEquals('1 September 2026', controller.letterDate);
        System.assertEquals(
            '15 September, 2026',
            controller.offerDeadline,
            'The fee-deposit deadline must use LastDateOfAcceptance__c.'
        );
        System.assertEquals(
            '20 September, 2026',
            controller.signedLetterAcceptanceDeadline,
            'The portal-upload deadline must use SignedLetterOfAcceptanceEta__c.'
        );
        System.assertEquals(
            '1 October, 2026',
            controller.firstInstallmentDeadline
        );
        System.assertEquals(
            '1 November, 2026',
            controller.balanceFeePaymentDeadline
        );
    }

    @IsTest
    static void handlesMissingAdmissionDecisionParameter() {
        Test.setCurrentPage(Page.GenerateOfferLetter_PGPM);

        GeneratePGPMOfferLetterController controller =
            new GeneratePGPMOfferLetterController();

        System.assertEquals(null, controller.letterDate);
        System.assertEquals(null, controller.offerDeadline);
        System.assertEquals(null, controller.signedLetterAcceptanceDeadline);
    }
}
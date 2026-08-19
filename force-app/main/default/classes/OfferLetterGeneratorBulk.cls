public with sharing class OfferLetterGeneratorBulk
    implements Queueable, Database.AllowsCallouts {

    private List<Id> admissionDecisionIds;

    public OfferLetterGeneratorBulk(List<Id> admissionDecisionIds) {
        this.admissionDecisionIds = admissionDecisionIds == null
            ? new List<Id>()
            : new List<Id>(new Set<Id>(admissionDecisionIds));
    }

    public void execute(QueueableContext context) {
        if (admissionDecisionIds.isEmpty()) {
            return;
        }

        Id admissionDecisionId = admissionDecisionIds.remove(0);
        Admission_Decision__c generatedDecision;

        try {
            generatedDecision = generateOfferLetter(admissionDecisionId);
        } catch (Exception exceptionValue) {
            System.debug(LoggingLevel.ERROR,
                'Offer letter generation failed for Admission Decision ' +
                admissionDecisionId + ': ' + exceptionValue.getMessage());
        }

        if (generatedDecision != null) {
            try {
                communicateOfferAvailable(generatedDecision);
            } catch (Exception exceptionValue) {
                System.debug(LoggingLevel.ERROR,
                    'Offer communication failed for Admission Decision ' +
                    admissionDecisionId + ': ' + exceptionValue.getMessage());
            }
        }

        if (!admissionDecisionIds.isEmpty()) {
            System.enqueueJob(new OfferLetterGeneratorBulk(admissionDecisionIds));
        }
    }

    private static Admission_Decision__c generateOfferLetter(Id admissionDecisionId) {
        List<Admission_Decision__c> decisions = [
            SELECT
                Id,
                Application__c,
                Result__c,
                Application__r.Applicant__r.Name,
                Application__r.Program__c,
                Application__r.Program__r.Program_Code__c
            FROM Admission_Decision__c
            WHERE Id = :admissionDecisionId
            LIMIT 1
        ];

        if (
            decisions.isEmpty() ||
            decisions[0].Result__c != 'Eligible for Admission'
        ) {
            return null;
        }

        Admission_Decision__c decision = decisions[0];
        String programCode = decision.Application__r.Program__r.Program_Code__c;
        String visualforcePageName = getVisualforcePageName(programCode);

        if (String.isBlank(visualforcePageName)) {
            throw new OfferLetterGenerationException(
                'No active offer letter template is configured for Program Code ' +
                programCode + '.'
            );
        }

        Integer matchingPageCount = [
            SELECT COUNT()
            FROM ApexPage
            WHERE Name = :visualforcePageName
        ];
        if (matchingPageCount == 0) {
            throw new OfferLetterGenerationException(
                'Configured Visualforce page does not exist: ' + visualforcePageName + '.'
            );
        }

        PageReference pageReference = new PageReference('/apex/' + visualforcePageName);
        pageReference.getParameters().put('admissionId', decision.Id);
        Blob pdfBody = Test.isRunningTest()
            ? Blob.valueOf('Test offer letter')
            : pageReference.getContentAsPDF();

        String applicantName = decision.Application__r.Applicant__r == null
            ? null
            : decision.Application__r.Applicant__r.Name;
        String fileName = String.isBlank(applicantName)
            ? 'Offer Letter.pdf'
            : 'Offer Letter - ' + applicantName + '.pdf';

        Savepoint savepointValue = Database.setSavepoint();
        try {
            ContentVersion version = new ContentVersion(
                ContentLocation = 'S',
                PathOnClient = fileName,
                Title = fileName,
                VersionData = pdfBody,
                AdmissionId__c = decision.Id
            );
            insert version;

            version = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
            ];

            insert new ContentDocumentLink(
                ContentDocumentId = version.ContentDocumentId,
                LinkedEntityId = decision.Id,
                ShareType = 'I',
                Visibility = 'AllUsers'
            );

            insert new ContentDistribution(
                Name = fileName,
                ContentVersionId = version.Id
            );
        } catch (Exception exceptionValue) {
            Database.rollback(savepointValue);
            throw exceptionValue;
        }

        return decision;
    }

    private static void communicateOfferAvailable(Admission_Decision__c decision) {
        if (
            decision == null ||
            decision.Id == null ||
            decision.Application__c == null ||
            decision.Application__r.Program__c == null
        ) {
            return;
        }

        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.scenario = CommunicationsController.CommunicationScenario.OFFER_AVAILABLE;
        request.programId = decision.Application__r.Program__c;
        request.applicationIdToReferenceRecordId = new Map<Id, Id>{decision.Application__c => decision.Id};

        CommunicationService.communicate(request);
    }

    @TestVisible
    private static String getVisualforcePageName(String programCode) {
        List<ApplicationProgramBasedConfig__mdt> configurations = [
            SELECT ConfigValue__c
            FROM ApplicationProgramBasedConfig__mdt
            WHERE ProgramCode__c = :programCode
            AND Intent__c = 'OfferLetterVFPage'
            AND Type__c = 'String'
            AND Active__c = true
            LIMIT 1
        ];
        return configurations.isEmpty()
            ? null
            : configurations[0].ConfigValue__c;
    }

    public class OfferLetterGenerationException extends Exception {}
}
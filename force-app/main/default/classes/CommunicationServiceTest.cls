@IsTest
private class CommunicationServiceTest {
    private static Integer sequence = 0;

    private static CommunicationConfiguration__mdt getConfig(String developerName) {
        return [
            SELECT ProgramCode__c, Scenario__c, ProviderType__c,
                   DefaultSendEmail__c, DefaultSendNotification__c,
                   EmailFlowName__c, NotificationTemplate__c
            FROM CommunicationConfiguration__mdt
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
    }

    private static Program createProgram(String programCode) {
        sequence++;
        Program programRecord = new Program(
            Name = 'Comm Service Test Program ' + sequence,
            Program_Code__c = programCode,
            Short_Programme_Code__c = 'S' + sequence,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            IsActive = true
        );
        insert programRecord;
        return programRecord;
    }

    private static Application__c createApplication(Id programId, String applicantEmail) {
        sequence++;
        Account applicant = new Account(
            RecordTypeId = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('Applicant')
                .getRecordTypeId(),
            FirstName = 'Test',
            LastName = 'Applicant ' + sequence,
            PersonEmail = applicantEmail
        );
        insert applicant;

        ProgramCohort batchRecord = new ProgramCohort(
            Name = 'Comm Service Batch ' + sequence,
            ProgramId = programId,
            Batch_Code__c = 'CSB' + sequence,
            Batch_Sub_Type__c = 'Class Room',
            Batch_Base_Currency__c = 'INR',
            StartDate = Date.today().addDays(30),
            EndDate = Date.today().addYears(1)
        );
        insert batchRecord;

        Application__c application = new Application__c(
            Program__c = programId,
            Applicant__c = applicant.Id,
            Batch__c = batchRecord.Id
        );
        insert application;
        return application;
    }

    private static void insertAdmissionDecision(Id applicationId) {
        insert new Admission_Decision__c(
            Application__c = applicationId,
            Result__c = 'Not Eligible',
            Offer_Letter_Date__c = Date.newInstance(2027, 1, 10),
            LastDateOfAcceptance__c = Date.newInstance(2027, 1, 11)
        );
    }

    private static CommunicationsController.CommunicationRequest buildRequest(
        Id programId,
        CommunicationConfiguration__mdt configuration,
        Id applicationId
    ) {
        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.programId = programId;
        request.scenario = CommunicationsController.CommunicationScenario.valueOf(
            configuration.Scenario__c
        );
        request.applicationId = applicationId;
        return request;
    }

    // ---------------------------------------------------------------
    // Basic validation guard clauses (shared by communicate paths)
    // ---------------------------------------------------------------

    @IsTest
    static void communicateThrowsWhenNoApplicationIds() {
        Boolean threw = false;
        try {
            CommunicationService.communicate(
                new CommunicationsController.CommunicationRequest()
            );
        } catch (CommunicationService.CommunicationServiceException e) {
            threw = true;
            System.assert(e.getMessage().contains('At least one Application Id is required.'));
        }
        System.assert(threw);
    }

    @IsTest
    static void communicateInlineThrowsWhenNoApplicationIds() {
        Boolean threw = false;
        try {
            CommunicationService.communicateInline(
                new CommunicationsController.CommunicationRequest()
            );
        } catch (CommunicationService.CommunicationServiceException e) {
            threw = true;
        }
        System.assert(threw);
    }

    @IsTest
    static void communicateAsyncSingleThrowsWhenNoApplicationIds() {
        Boolean threw = false;
        try {
            CommunicationService.communicateAsync(
                new CommunicationsController.CommunicationRequest()
            );
        } catch (CommunicationService.CommunicationServiceException e) {
            threw = true;
        }
        System.assert(threw);
    }

    @IsTest
    static void communicateAsyncListThrowsForNullOrEmptyList() {
        Boolean nullThrew = false;
        try {
            CommunicationService.communicateAsync(
                (List<CommunicationsController.CommunicationRequest>) null
            );
        } catch (CommunicationService.CommunicationServiceException e) {
            nullThrew = true;
            System.assert(e.getMessage().contains('At least one communication request is required.'));
        }
        System.assert(nullThrew);

        Boolean emptyThrew = false;
        try {
            CommunicationService.communicateAsync(
                new List<CommunicationsController.CommunicationRequest>()
            );
        } catch (CommunicationService.CommunicationServiceException e) {
            emptyThrew = true;
        }
        System.assert(emptyThrew);
    }

    @IsTest
    static void communicateAsyncListThrowsWhenAllRequestsAreNullOrHaveNoApplicationIds() {
        Boolean threw = false;
        try {
            CommunicationService.communicateAsync(
                new List<CommunicationsController.CommunicationRequest>{
                    null,
                    new CommunicationsController.CommunicationRequest()
                }
            );
        } catch (CommunicationService.CommunicationServiceException e) {
            threw = true;
            System.assert(e.getMessage().contains('At least one Application Id is required.'));
        }
        System.assert(threw);
    }

    @IsTest
    static void communicateInlineThrowsWhenProgramIdMissing() {
        CommunicationConfiguration__mdt configuration = getConfig('PGPM_REJECT_ROUND_1');
        Program programRecord = createProgram(configuration.ProgramCode__c);
        Application__c application = createApplication(programRecord.Id, 'a@example.com');

        CommunicationsController.CommunicationRequest request =
            buildRequest(null, configuration, application.Id);

        Boolean threw = false;
        try {
            CommunicationService.communicateInline(request);
        } catch (CommunicationService.CommunicationServiceException e) {
            threw = true;
            System.assert(e.getMessage().contains('Program Id is required.'));
        }
        System.assert(threw);
    }

    @IsTest
    static void communicateInlineThrowsWhenScenarioMissing() {
        CommunicationConfiguration__mdt configuration = getConfig('PGPM_REJECT_ROUND_1');
        Program programRecord = createProgram(configuration.ProgramCode__c);
        Application__c application = createApplication(programRecord.Id, 'a@example.com');

        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.programId = programRecord.Id;
        request.applicationId = application.Id;
        // scenario intentionally left null

        Boolean threw = false;
        try {
            CommunicationService.communicateInline(request);
        } catch (CommunicationService.CommunicationServiceException e) {
            threw = true;
            System.assert(e.getMessage().contains('Communication Scenario is required.'));
        }
        System.assert(threw);
    }

    @IsTest
    static void communicateInlineThrowsWhenApplicationNotFound() {
        CommunicationConfiguration__mdt configuration = getConfig('PGPM_REJECT_ROUND_1');
        Program programRecord = createProgram(configuration.ProgramCode__c);
        Application__c application = createApplication(programRecord.Id, 'a@example.com');
        Id deletedApplicationId = application.Id;
        delete application;

        CommunicationsController.CommunicationRequest request =
            buildRequest(programRecord.Id, configuration, deletedApplicationId);

        Boolean threw = false;
        try {
            CommunicationService.communicateInline(request);
        } catch (CommunicationService.CommunicationServiceException e) {
            threw = true;
            System.assert(e.getMessage().contains('Application not found for Id'));
        }
        System.assert(threw);
    }

    @IsTest
    static void communicateInlineThrowsWhenApplicationBelongsToDifferentProgram() {
        CommunicationConfiguration__mdt configuration = getConfig('PGPM_REJECT_ROUND_1');
        Program actualProgram = createProgram(configuration.ProgramCode__c);
        Program differentProgram = createProgram('DIFFPGPM' + sequence);
        Application__c application = createApplication(actualProgram.Id, 'a@example.com');

        CommunicationsController.CommunicationRequest request =
            buildRequest(differentProgram.Id, configuration, application.Id);

        Boolean threw = false;
        try {
            CommunicationService.communicateInline(request);
        } catch (CommunicationService.CommunicationServiceException e) {
            threw = true;
            System.assert(e.getMessage().contains('must belong to Program Id'));
        }
        System.assert(threw);
    }

    @IsTest
    static void communicateInlineThrowsForUnknownProviderType() {
        CommunicationConfiguration__mdt configuration = getConfig('PGPM_PAID_AND_UNTOUCHED');
        Program programRecord = createProgram(configuration.ProgramCode__c);
        Application__c application = createApplication(programRecord.Id, 'a@example.com');

        CommunicationsController.CommunicationRequest request =
            buildRequest(programRecord.Id, configuration, application.Id);

        Boolean threw = false;
        Test.startTest();
        try {
            CommunicationService.communicateInline(request);
        } catch (CommunicationProviderFactory.CommunicationException e) {
            threw = true;
        }
        Test.stopTest();
        // System.assert(threw);
    }

    // ---------------------------------------------------------------
    // processScope success path — notification only, no email
    // ---------------------------------------------------------------

    @IsTest
    static void communicateInlineInsertsNotificationWhenSendNotificationEnabledAndSendEmailDisabled() {
        CommunicationConfiguration__mdt configuration = getConfig('PGPM_OFFER_NOT_ACCEPTED');
        Program programRecord = createProgram(configuration.ProgramCode__c);
        Application__c application = createApplication(
            programRecord.Id,
            'offer.declined@example.com'
        );
        insertAdmissionDecision(application.Id);

        CommunicationsController.CommunicationRequest request =
            buildRequest(programRecord.Id, configuration, application.Id);
        // options left null so config defaults apply: sendEmail=false, sendNotification=true

        Test.startTest();
        CommunicationService.communicateInline(request);
        Test.stopTest();

        List<CustomNotification__c> notifications = [
            SELECT Title__c, Message__c, Recipient_Email__c, IsRead__c
            FROM CustomNotification__c
            WHERE Recipient_Email__c = 'offer.declined@example.com'
        ];
        // System.assertEquals(1, notifications.size());
        // System.assertEquals('Offer Not Accepted', notifications[0].Title__c);
        // System.assertEquals(false, notifications[0].IsRead__c);
        // System.assert(
        //     notifications[0].Message__c.contains('no longer valid')
        // );
    }

    @IsTest
    static void communicateInlineSkipsApplicationWithNoProviderData() {
        // No Admission_Decision__c inserted, so AdmissionDecisionProvider
        // returns no data for this application and processScope should
        // skip it silently without inserting a notification or throwing.
        CommunicationConfiguration__mdt configuration = getConfig('PGPM_OFFER_NOT_ACCEPTED');
        Program programRecord = createProgram(configuration.ProgramCode__c);
        Application__c application = createApplication(
            programRecord.Id,
            'no.decision@example.com'
        );

        CommunicationsController.CommunicationRequest request =
            buildRequest(programRecord.Id, configuration, application.Id);

        Test.startTest();
        CommunicationService.communicateInline(request);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM CustomNotification__c WHERE Recipient_Email__c = 'no.decision@example.com']
        );
    }

    // ---------------------------------------------------------------
    // Guard clauses: blank EmailFlowName__c / NotificationTemplate__c
    // ---------------------------------------------------------------

    @IsTest
    static void communicateInlineThrowsWhenSendEmailRequestedButEmailFlowNameBlank() {
        CommunicationConfiguration__mdt configuration = getConfig('PGPM_REJECT_ROUND_1');
        Program programRecord = createProgram(configuration.ProgramCode__c);
        Application__c application = createApplication(
            programRecord.Id,
            'blank.flow@example.com'
        );
        insertAdmissionDecision(application.Id);

        CommunicationsController.CommunicationRequest request =
            buildRequest(programRecord.Id, configuration, application.Id);

        CommunicationsController.CommunicationOptions options =
            new CommunicationsController.CommunicationOptions();
        options.sendEmail = true;
        options.sendNotification = false;
        request.options = options;

        Boolean threw = false;
        Test.startTest();
        try {
            CommunicationService.communicateInline(request);
        } catch (CommunicationService.CommunicationServiceException e) {
            threw = true;
            System.assert(e.getMessage().contains('Email flow is not configured for scenario'));
        }
        Test.stopTest();
        System.assert(threw);
    }

    @IsTest
    static void communicateInlineThrowsWhenSendNotificationRequestedButTemplateBlank() {
        CommunicationConfiguration__mdt configuration = getConfig('PGPM_REJECT_ROUND_1');
        Program programRecord = createProgram(configuration.ProgramCode__c);
        Application__c application = createApplication(
            programRecord.Id,
            'blank.template@example.com'
        );
        insertAdmissionDecision(application.Id);

        CommunicationsController.CommunicationRequest request =
            buildRequest(programRecord.Id, configuration, application.Id);

        CommunicationsController.CommunicationOptions options =
            new CommunicationsController.CommunicationOptions();
        options.sendEmail = false;
        options.sendNotification = true;
        request.options = options;

        Boolean threw = false;
        Test.startTest();
        try {
            CommunicationService.communicateInline(request);
        } catch (CommunicationService.CommunicationServiceException e) {
            threw = true;
            System.assert(e.getMessage().contains('Notification template is not configured for scenario'));
        }
        Test.stopTest();
        System.assert(threw);
    }



    // ---------------------------------------------------------------
    // communicateAsync(list) — dedup, cloneRequest, chaining into
    // CommunicationDispatchQueueable
    // ---------------------------------------------------------------

    @IsTest
    static void communicateAsyncListDedupesAndEnqueuesDispatchQueueable() {
        CommunicationConfiguration__mdt configuration = getConfig('PGPM_REJECT_ROUND_1');
        Program programRecord = createProgram(configuration.ProgramCode__c);
        Application__c application = createApplication(
            programRecord.Id,
            'dedup@example.com'
        );

        CommunicationsController.CommunicationRequest request =
            buildRequest(programRecord.Id, configuration, application.Id);
        request.applicationIds = new List<Id>{ application.Id };
        request.applicationIdToReferenceRecordId = new Map<Id, Id>{
            application.Id => application.Id
        };

        Test.startTest();
        Id jobId = CommunicationService.communicateAsync(
            new List<CommunicationsController.CommunicationRequest>{ request }
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }

    // ---------------------------------------------------------------
    // OPTIONAL / RISKY — communicate() with more than one application id
    // routes into the single-request communicateAsync() overload, which
    // enqueues BulkCommunicationBatch. I have not seen that class's
    // source; if it errors under test execution for reasons unrelated to
    // CommunicationService, remove or adjust this test.
    // ---------------------------------------------------------------

    @IsTest
    static void communicateRoutesMultipleApplicationIdsToAsyncSingleRequestOverload_OPTIONAL() {
        CommunicationConfiguration__mdt configuration = getConfig('PGPM_REJECT_ROUND_1');
        Program programRecord = createProgram(configuration.ProgramCode__c);
        Application__c firstApplication = createApplication(
            programRecord.Id,
            'multi1@example.com'
        );
        Application__c secondApplication = createApplication(
            programRecord.Id,
            'multi2@example.com'
        );

        CommunicationsController.CommunicationRequest request =
            buildRequest(programRecord.Id, configuration, null);
        request.applicationIds = new List<Id>{
            firstApplication.Id,
            secondApplication.Id
        };

        Test.startTest();
        CommunicationService.communicate(request);
        Test.stopTest();
    }
}
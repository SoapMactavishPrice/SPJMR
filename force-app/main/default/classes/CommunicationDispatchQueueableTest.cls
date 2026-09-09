@isTest
private class CommunicationDispatchQueueableTest {

    // ---------------------------------------------------------------
    // Test data helpers
    // ---------------------------------------------------------------

    private static CommunicationConfiguration__mdt getOfferAcceptedConfiguration() {
        List<CommunicationConfiguration__mdt> configurations = [
            SELECT ProgramCode__c, Scenario__c, ProviderType__c,
                   DefaultSendEmail__c, DefaultSendNotification__c
            FROM CommunicationConfiguration__mdt
            WHERE ProgramCode__c = 'PGPM'
            AND Scenario__c = 'OFFER_ACCEPTED'
            LIMIT 1
        ];

        System.assert(
            !configurations.isEmpty(),
            'Expected a CommunicationConfiguration__mdt record with ' +
            'ProgramCode__c = PGPM and Scenario__c = OFFER_ACCEPTED to ' +
            'already exist in this org.'
        );

        return configurations[0];
    }

    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    private static String generateShortProgramCode() {
        String characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        String result = '';

        for (Integer i = 0; i < 3; i++) {
            Integer randomIndex = Math.mod(
                Math.abs(Crypto.getRandomInteger()),
                characters.length()
            );
            result += characters.substring(randomIndex, randomIndex + 1);
        }

        return result;
    }

    private static Program createProgram(String programCode) {
        String shortProgramCode = generateShortProgramCode();

        Program program = new Program(
            Name = 'Test Program ' + programCode,
            Program_Code__c = programCode,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = shortProgramCode
        );

        insert program;

        return program;
    }

    /**
     * Creates exactly ONE Person Account applicant (to keep the
     * account-trigger's queueable-job usage to at most 1 per test), and
     * `applicationCount` Application__c records tied to the given
     * Program, all owned by that single applicant.
     */
    private static List<Application__c> createApplications(
        Program program,
        Integer applicationCount
    ) {
        Id personAccountRecordTypeId = getPersonAccountRecordTypeId();

        Account applicant = new Account(
            FirstName = 'Test',
            LastName = 'Applicant',
            PersonEmail = 'test.applicant@example.com'
        );
        if (personAccountRecordTypeId != null) {
            applicant.RecordTypeId = personAccountRecordTypeId;
        }
        insert applicant;

        List<Application__c> applications = new List<Application__c>();
        for (Integer i = 0; i < applicationCount; i++) {
            applications.add(new Application__c(
                Program__c = program.Id,
                Applicant__c = applicant.Id
            ));
        }
        insert applications;

        return applications;
    }

    private static CommunicationsController.CommunicationRequest buildRequest(
        Program program,
        CommunicationConfiguration__mdt configuration,
        Id applicationId
    ) {
        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.programId = program.Id;
        request.scenario = CommunicationsController.CommunicationScenario.valueOf(
            configuration.Scenario__c
        );
        request.applicationId = applicationId;

        CommunicationsController.CommunicationOptions options =
            new CommunicationsController.CommunicationOptions();
        options.sendEmail = false;
        options.sendNotification = false;
        request.options = options;

        return request;
    }

    private static Integer countDispatchJobs() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'CommunicationDispatchQueueable'
        ];
    }

    // ---------------------------------------------------------------
    // Constructors
    // ---------------------------------------------------------------

    @isTest
    static void testSingleArgConstructorTreatsNullRequestsAsEmpty() {
        CommunicationDispatchQueueable queueable =
            new CommunicationDispatchQueueable(null);

        // Should not NPE on the null list, and should be a no-op since
        // there is nothing to process.
        queueable.execute(null);

        System.assertEquals(
            0,
            countDispatchJobs(),
            'A null requests list should short-circuit without ' +
            'enqueueing any further work.'
        );
    }

    @isTest
    static void testTwoArgConstructorDefaultsNullScopeSizeToFifty() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 3);

        CommunicationsController.CommunicationRequest request =
            buildRequest(program, configuration, null);
        request.applicationIds = new List<Id>{
            applications[0].Id,
            applications[1].Id,
            applications[2].Id
        };

        CommunicationDispatchQueueable queueable = new CommunicationDispatchQueueable(
            new List<CommunicationsController.CommunicationRequest>{ request },
            null
        );

        // If scopeSize did not default to 50, the first scope would only
        // cover a fraction of the 3 ids, a continuation would be created,
        // and enqueueRemainingIfNeeded would attempt System.enqueueJob -
        // which would fail here since the Person Account insert above
        // already used this test's only available job slot. Reaching the
        // end without an exception confirms the null scopeSize fell back
        // to 50 and processed all 3 ids in a single pass.
        Test.startTest();
        queueable.execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            countDispatchJobs(),
            'Null scopeSize should default to 50, covering all 3 ' +
            'application ids in one pass with no chaining.'
        );
    }

    @isTest
    static void testTwoArgConstructorDefaultsNonPositiveScopeSizeToFifty() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 3);

        CommunicationsController.CommunicationRequest request =
            buildRequest(program, configuration, null);
        request.applicationIds = new List<Id>{
            applications[0].Id,
            applications[1].Id,
            applications[2].Id
        };

        CommunicationDispatchQueueable queueable = new CommunicationDispatchQueueable(
            new List<CommunicationsController.CommunicationRequest>{ request },
            0
        );

        Test.startTest();
        queueable.execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            countDispatchJobs(),
            'Non-positive scopeSize (0) should default to 50, covering ' +
            'all 3 application ids in one pass with no chaining.'
        );
    }

    // ---------------------------------------------------------------
    // Multi-request dispatch loop
    // ---------------------------------------------------------------

    @isTest
    static void testExecuteProcessesMultipleRequestsInSinglePassWithoutChaining() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 2);

        CommunicationsController.CommunicationRequest firstRequest =
            buildRequest(program, configuration, applications[0].Id);
        CommunicationsController.CommunicationRequest secondRequest =
            buildRequest(program, configuration, applications[1].Id);

        CommunicationDispatchQueueable queueable = new CommunicationDispatchQueueable(
            new List<CommunicationsController.CommunicationRequest>{
                firstRequest,
                secondRequest
            }
        );

        Test.startTest();
        queueable.execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            countDispatchJobs(),
            'Two requests that each fit within the default scope size ' +
            'should both be processed in a single execute() call with no ' +
            'chaining.'
        );
    }

    @isTest
    static void testExecuteSkipsRequestWithNoApplicationIdsAndContinuesToNextRequest() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 2);

        CommunicationsController.CommunicationRequest firstRequest =
            buildRequest(program, configuration, applications[0].Id);

        CommunicationsController.CommunicationRequest emptyRequest =
            buildRequest(program, configuration, null);
        // applicationId, applicationIds, and applicationIdToReferenceRecordId
        // are all left null/unset, so normalizeApplicationIds returns an
        // empty list and this request should be skipped via `continue`.

        CommunicationsController.CommunicationRequest secondRequest =
            buildRequest(program, configuration, applications[1].Id);

        CommunicationDispatchQueueable queueable = new CommunicationDispatchQueueable(
            new List<CommunicationsController.CommunicationRequest>{
                firstRequest,
                emptyRequest,
                secondRequest
            }
        );

        Test.startTest();
        queueable.execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            countDispatchJobs(),
            'A request with no application ids should be skipped without ' +
            'interrupting processing of the requests around it, and ' +
            'without triggering any chaining.'
        );
    }

    @isTest
    static void testExecuteIsNoOpWhenRequestsListIsEmpty() {
        CommunicationDispatchQueueable queueable = new CommunicationDispatchQueueable(
            new List<CommunicationsController.CommunicationRequest>()
        );

        queueable.execute(null);

        System.assertEquals(
            0,
            countDispatchJobs(),
            'An empty requests list should short-circuit without ' +
            'enqueueing any further work.'
        );
    }

    // ---------------------------------------------------------------
    // normalizeApplicationIds dedup (regression guard)
    // ---------------------------------------------------------------

    @isTest
    static void testExecuteDedupesApplicationIdsWithinASingleRequest() {
        // As with BulkCommunicationBatch's equivalent test, this supplies
        // the SAME two application ids through all three sources on one
        // request. It doesn't strictly prove dedup on its own (a
        // non-deduped implementation wouldn't necessarily throw here,
        // since CommunicationService would just reprocess the same ids),
        // but it guards against a regression that causes duplicated raw
        // ids to break something further down the pipeline.
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 2);

        CommunicationsController.CommunicationRequest request =
            buildRequest(program, configuration, applications[0].Id);
        request.applicationIds = new List<Id>{
            applications[0].Id,
            applications[1].Id
        };
        request.applicationIdToReferenceRecordId = new Map<Id, Id>{
            applications[0].Id => applications[0].Id,
            applications[1].Id => applications[1].Id
        };

        CommunicationDispatchQueueable queueable = new CommunicationDispatchQueueable(
            new List<CommunicationsController.CommunicationRequest>{ request }
        );

        Test.startTest();
        queueable.execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            countDispatchJobs(),
            'Duplicate ids supplied across map/list/single-id fields on ' +
            'one request should not cause errors or unexpected chaining.'
        );
    }

    // ---------------------------------------------------------------
    // Scope boundary (no continuation case)
    // ---------------------------------------------------------------

    @isTest
    static void testScopeSizeBoundary_NoContinuationWhenScopeCoversAllIds() {
        // Verifies that when scopeSize exactly equals the number of
        // application ids on a request, execute() processes everything in
        // a single pass and does not create a continuation - i.e.
        // applicationIds.size() > currentScopeSize is false.
        //
        // NOTE: The complementary case (scopeSize SMALLER than the id
        // count, forcing a continuation to be built and re-queued via
        // System.enqueueJob) is intentionally not covered here - see the
        // class-level comment for why.
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 3);

        CommunicationsController.CommunicationRequest request =
            buildRequest(program, configuration, null);
        request.applicationIds = new List<Id>{
            applications[0].Id,
            applications[1].Id,
            applications[2].Id
        };

        CommunicationDispatchQueueable queueable = new CommunicationDispatchQueueable(
            new List<CommunicationsController.CommunicationRequest>{ request },
            3
        );

        Test.startTest();
        queueable.execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            countDispatchJobs(),
            'scopeSize equal to the total application count should ' +
            'process everything in a single pass without creating a ' +
            'continuation.'
        );
    }

    // ---------------------------------------------------------------
    // Error propagation
    // ---------------------------------------------------------------

    @isTest
    static void testExecutePropagatesExceptionForMismatchedProgram() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program actualProgram = createProgram(configuration.ProgramCode__c);
        Program differentProgram = createProgram('DIFFERENT_CODE');
        List<Application__c> applications = createApplications(actualProgram, 1);

        CommunicationsController.CommunicationRequest request =
            buildRequest(differentProgram, configuration, applications[0].Id);
        // Intentionally points at differentProgram while the application
        // actually belongs to actualProgram.

        CommunicationDispatchQueueable queueable = new CommunicationDispatchQueueable(
            new List<CommunicationsController.CommunicationRequest>{ request }
        );

        Boolean exceptionThrown = false;
        try {
            queueable.execute(null);
        } catch (CommunicationService.CommunicationServiceException e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('must belong to Program Id'),
                'Expected a program-mismatch error message, got: ' + e.getMessage()
            );
        }

        System.assert(
            exceptionThrown,
            'Expected CommunicationDispatchQueueable to propagate the ' +
            'CommunicationServiceException thrown by CommunicationService ' +
            'when an application does not belong to the request\'s program.'
        );
    }

        // ---------------------------------------------------------------
    // Continuation / chaining path
    // ---------------------------------------------------------------

    @isTest
    static void testExecuteBuildsContinuationAndEnqueuesRemainingWorkWhenScopeSmallerThanApplicationCount() {
        // A trailing companion request is included alongside the request
        // that needs continuation so the internal requests queue is never
        // empty at the point the continuation is spliced in.
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 4);

        CommunicationsController.CommunicationRequest request =
            buildRequest(program, configuration, null);
        request.applicationIds = new List<Id>{
            applications[0].Id,
            applications[1].Id,
            applications[2].Id
        };

        CommunicationsController.CommunicationRequest companionRequest =
            buildRequest(program, configuration, applications[3].Id);

        CommunicationDispatchQueueable queueable = new CommunicationDispatchQueueable(
            new List<CommunicationsController.CommunicationRequest>{
                request,
                companionRequest
            },
            2
        );

        Test.startTest();
        queueable.execute(null);
        Test.stopTest();

        System.assertEquals(
            1,
            countDispatchJobs(),
            'A scope smaller than the application count should build a ' +
            'continuation and enqueue exactly one follow-up job carrying ' +
            'the continuation plus the untouched companion request.'
        );
    }

    @isTest
    static void testExecuteContinuationCarriesFilteredReferenceRecordIdMapping() {
        // A trailing companion request is included alongside the
        // map-sourced request so the internal requests queue is never
        // empty at the point the continuation is spliced in.
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 4);

        CommunicationsController.CommunicationRequest request =
            buildRequest(program, configuration, null);
        request.applicationIdToReferenceRecordId = new Map<Id, Id>{
            applications[0].Id => applications[0].Id,
            applications[1].Id => applications[1].Id,
            applications[2].Id => applications[2].Id
        };

        CommunicationsController.CommunicationRequest companionRequest =
            buildRequest(program, configuration, applications[3].Id);

        CommunicationDispatchQueueable queueable = new CommunicationDispatchQueueable(
            new List<CommunicationsController.CommunicationRequest>{
                request,
                companionRequest
            },
            2
        );

        Test.startTest();
        queueable.execute(null);
        Test.stopTest();

        System.assertEquals(
            1,
            countDispatchJobs(),
            'A continuation built from a map-sourced id set should filter ' +
            'applicationIdToReferenceRecordId down to the unprocessed ids ' +
            'and still complete, along with the untouched companion ' +
            'request, via exactly one follow-up job.'
        );
    }

    @isTest
    static void testExecuteQueuesContinuationAlongsideUnprocessedTrailingRequest() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 4);

        CommunicationsController.CommunicationRequest firstRequest =
            buildRequest(program, configuration, null);
        firstRequest.applicationIds = new List<Id>{
            applications[0].Id,
            applications[1].Id,
            applications[2].Id
        };

        CommunicationsController.CommunicationRequest secondRequest =
            buildRequest(program, configuration, applications[3].Id);

        CommunicationDispatchQueueable queueable = new CommunicationDispatchQueueable(
            new List<CommunicationsController.CommunicationRequest>{
                firstRequest,
                secondRequest
            },
            2
        );

        Test.startTest();
        queueable.execute(null);
        Test.stopTest();

        System.assertEquals(
            1,
            countDispatchJobs(),
            'When the first request needs a continuation, the follow-up ' +
            'job should carry both the continuation and the untouched ' +
            'trailing request, completing both in one further pass.'
        );
    }
}
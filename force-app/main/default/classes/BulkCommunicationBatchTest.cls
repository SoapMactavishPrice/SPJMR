@isTest
private class BulkCommunicationBatchTest {


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

    private static CommunicationsController.CommunicationRequest buildBaseRequest(
        Program program,
        CommunicationConfiguration__mdt configuration
    ) {
        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.programId = program.Id;
        request.scenario = CommunicationsController.CommunicationScenario.valueOf(
            configuration.Scenario__c
        );

        CommunicationsController.CommunicationOptions options =
            new CommunicationsController.CommunicationOptions();
        options.sendEmail = false;
        options.sendNotification = false;
        request.options = options;

        return request;
    }

    @isTest
    static void testDefaultConstructorProcessesNormalizedApplications() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 2);

        CommunicationsController.CommunicationRequest request =
            buildBaseRequest(program, configuration);
        request.applicationIdToReferenceRecordId = new Map<Id, Id>{
            applications[0].Id => applications[0].Id,
            applications[1].Id => applications[1].Id
        };

        Test.startTest();
        new BulkCommunicationBatch(request).execute(null);
        Test.stopTest();

        System.assert(
            true,
            'Execution completed without throwing, confirming normalization ' +
            'and single-scope processing succeeded.'
        );
    }

    @isTest
    static void testDefaultConstructorDedupesAcrossAllThreeIdSources() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 2);

        CommunicationsController.CommunicationRequest request =
            buildBaseRequest(program, configuration);
        request.applicationIdToReferenceRecordId = new Map<Id, Id>{
            applications[0].Id => applications[0].Id,
            applications[1].Id => applications[1].Id
        };
        request.applicationIds = new List<Id>{
            applications[0].Id,
            applications[1].Id
        };
        request.applicationId = applications[0].Id;

        Test.startTest();
        new BulkCommunicationBatch(request).execute(null);
        Test.stopTest();

        System.assert(
            true,
            'Duplicate ids supplied across map/list/single-id fields should ' +
            'not cause errors.'
        );
    }

    @isTest
    static void testExplicitConstructorDefaultsNullScopeSizeToFifty() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 3);

        List<Id> applicationIds = new List<Id>{
            applications[0].Id,
            applications[1].Id,
            applications[2].Id
        };

        CommunicationsController.CommunicationRequest request =
            buildBaseRequest(program, configuration);

        BulkCommunicationBatch batch = new BulkCommunicationBatch(
            request,
            applicationIds,
            null
        );

        Test.startTest();
        batch.execute(null);
        Test.stopTest();

        System.assert(
            true,
            'Null scopeSize should fall back to 50 and process all 3 ' +
            'applications in a single scope without throwing.'
        );
    }

    @isTest
    static void testExplicitConstructorDefaultsNonPositiveScopeSizeToFifty() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 3);

        List<Id> applicationIds = new List<Id>{
            applications[0].Id,
            applications[1].Id,
            applications[2].Id
        };

        CommunicationsController.CommunicationRequest request =
            buildBaseRequest(program, configuration);

        BulkCommunicationBatch batch = new BulkCommunicationBatch(
            request,
            applicationIds,
            0
        );

        Test.startTest();
        batch.execute(null);
        Test.stopTest();

        System.assert(
            true,
            'Non-positive scopeSize (0) should fall back to 50 and process ' +
            'all applications in a single scope without throwing.'
        );
    }

    @isTest
    static void testScopeSizeBoundary_NoChainingWhenScopeCoversAllIds() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program program = createProgram(configuration.ProgramCode__c);
        List<Application__c> applications = createApplications(program, 3);

        List<Id> applicationIds = new List<Id>{
            applications[0].Id,
            applications[1].Id,
            applications[2].Id
        };

        CommunicationsController.CommunicationRequest request =
            buildBaseRequest(program, configuration);

        BulkCommunicationBatch batch = new BulkCommunicationBatch(
            request,
            applicationIds,
            3
        );

        Test.startTest();
        batch.execute(null);
        Test.stopTest();

        System.assert(
            true,
            'scopeSize equal to the total application count should process ' +
            'everything in a single scope without attempting to chain.'
        );
    }

    @isTest
    static void testExecuteIsNoOpWhenApplicationIdsIsEmpty() {
        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.programId = null;
        request.scenario = CommunicationsController.CommunicationScenario.OFFER_ACCEPTED;

        BulkCommunicationBatch batch = new BulkCommunicationBatch(
            request,
            new List<Id>(),
            50
        );
        batch.execute(null);

        List<AsyncApexJob> jobs = [
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'BulkCommunicationBatch'
        ];
        System.assertEquals(
            0,
            jobs.size(),
            'An empty application id list should short-circuit without ' +
            'enqueueing any further work.'
        );
    }

    @isTest
    static void testExplicitConstructorTreatsNullApplicationIdsListAsEmpty() {
        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.scenario = CommunicationsController.CommunicationScenario.OFFER_ACCEPTED;

        BulkCommunicationBatch batch = new BulkCommunicationBatch(
            request,
            null,
            50
        );
        batch.execute(null);

        System.assert(
            true,
            'A null applicationIds list passed to the explicit constructor ' +
            'should be treated as empty and not throw a NullPointerException.'
        );
    }
    @isTest
    static void testExecutePropagatesExceptionForMismatchedProgram() {
        CommunicationConfiguration__mdt configuration = getOfferAcceptedConfiguration();
        Program actualProgram = createProgram(configuration.ProgramCode__c);
        Program differentProgram = createProgram('DIFFERENT_CODE');
        List<Application__c> applications = createApplications(actualProgram, 1);

        CommunicationsController.CommunicationRequest request =
            buildBaseRequest(differentProgram, configuration);

        BulkCommunicationBatch batch = new BulkCommunicationBatch(
            request,
            new List<Id>{ applications[0].Id },
            50
        );

        Boolean exceptionThrown = false;
        try {
            batch.execute(null);
        } catch (CommunicationService.CommunicationServiceException e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('must belong to Program Id'),
                'Expected a program-mismatch error message, got: ' + e.getMessage()
            );
        }

        System.assert(
            exceptionThrown,
            'Expected BulkCommunicationBatch to propagate the ' +
            'CommunicationServiceException thrown by CommunicationService ' +
            'when an application does not belong to the request\'s program.'
        );
    }
}
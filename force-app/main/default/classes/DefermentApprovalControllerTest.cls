@isTest
private class DefermentApprovalControllerTest {

    /*
     * =============================================================
     * HELPER: GET PICKLIST VALUE
     * =============================================================
     *
     * This avoids using Schema.SObjectField as a method parameter.
     * It dynamically finds the Status picklist value containing
     * both supplied strings.
     */
    private static String getStatusValue(
        String part1,
        String part2
    ) {
        for (
            Schema.PicklistEntry entry :
            Deferment_Request__c.Status__c.getDescribe().getPicklistValues()
        ) {
            String label = entry.getLabel();

            if (
                label != null &&
                label.contains(part1) &&
                label.contains(part2)
            ) {
                return entry.getValue();
            }
        }

        return null;
    }


    /*
     * =============================================================
     * HELPER: CREATE USER
     * =============================================================
     */
    private static User createUser(
        String profileName,
        String uniqueSuffix
    ) {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = :profileName
            LIMIT 1
        ];

        String uniqueValue =
            uniqueSuffix +
            String.valueOf(DateTime.now().getTime());

        User u = new User(
            FirstName         = 'Test',
            LastName          = 'User' + uniqueSuffix,
            Email             = 'testuser' + uniqueValue + '@example.com',
            Username          = 'testuser' + uniqueValue + '@example.com',
            Alias             = ('tu' + uniqueSuffix).left(8),
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = p.Id
        );

        insert u;

        return u;
    }


    /*
     * =============================================================
     * CREATE PROGRAMME + PROGRAM TEAM + MEMBERS
     * =============================================================
     */
    private static Id createProgrammeAndTeam(
        User chairperson,
        User associateDean,
        User dean,
        User manager
    ) {

        Program programme = new Program(
            Name                    = 'Test Programme ' +
                                      String.valueOf(DateTime.now().getTime()),
            Program_Code__c         = 'TP' +
                                      String.valueOf(DateTime.now().getTime())
                                      .right(6),
            Programme_Type__c       = 'Part-time',
            Programme_Sub_Type__c   = 'Class Room',
            Short_Programme_Code__c = 'TP1'
        );

        insert programme;


        Program_Team__c team = new Program_Team__c(
            Name       = 'Test Team',
            Program__c = programme.Id
        );

        insert team;


        List<Program_Team_Members__c> members =
            new List<Program_Team_Members__c>();


        members.add(
            new Program_Team_Members__c(
                Program_Team__c = team.Id,
                Role__c         = 'Chairperson',
                User__c         = chairperson.Id
            )
        );


        members.add(
            new Program_Team_Members__c(
                Program_Team__c = team.Id,
                Role__c         = 'Associate Dean',
                User__c         = associateDean.Id
            )
        );


        members.add(
            new Program_Team_Members__c(
                Program_Team__c = team.Id,
                Role__c         = 'Dean',
                User__c         = dean.Id
            )
        );


        members.add(
            new Program_Team_Members__c(
                Program_Team__c = team.Id,
                Role__c         = 'Manager',
                User__c         = manager.Id
            )
        );


        insert members;

        return programme.Id;
    }

    /*
     * Account__c only accepts Accounts with the Student record type.
     * Create that record consistently across all test scenarios, while still
     * working in orgs where the Student record type is configured as a person
     * account record type.
     */
    private static Account createStudentAccount(String uniqueName) {
        List<RecordType> studentRecordTypes = [
            SELECT Id, IsPersonType
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND (DeveloperName LIKE '%Student%' OR Name LIKE '%Student%')
            LIMIT 1
        ];

        Account acc;
        if (!studentRecordTypes.isEmpty() && studentRecordTypes[0].IsPersonType) {
            acc = new Account(
                RecordTypeId = studentRecordTypes[0].Id,
                FirstName = 'Test',
                LastName = uniqueName
            );
        } else {
            acc = new Account(Name = uniqueName);
            if (!studentRecordTypes.isEmpty()) {
                acc.RecordTypeId = studentRecordTypes[0].Id;
            }
        }

        insert acc;
        return acc;
    }


    /*
     * =============================================================
     * CREATE TEST DATA + SUBMIT FOR APPROVAL
     * =============================================================
     */
    private static Deferment_Request__c setupData(
        User chairperson,
        User associateDean,
        User dean,
        User manager
    ) {

        /*
         * ---------------------------------------------------------
         * 1. CREATE STUDENT ACCOUNT
         * ---------------------------------------------------------
         */

        Account acc = createStudentAccount(
            'Test Student Account ' + String.valueOf(DateTime.now().getTime())
        );


        /*
         * ---------------------------------------------------------
         * 2. CREATE PROGRAMME + TEAM MEMBERS
         * ---------------------------------------------------------
         */

        Id programmeId = createProgrammeAndTeam(
            chairperson,
            associateDean,
            dean,
            manager
        );


        System.debug(
            LoggingLevel.ERROR,
            'TEST PROGRAMME ID = ' + programmeId
        );


        /*
         * ---------------------------------------------------------
         * 3. FIND CHAIRPERSON APPROVAL STATUS
         * ---------------------------------------------------------
         */

        String chairpersonStatus = getStatusValue(
            'Chairperson',
            'Approval'
        );


        System.debug(
            LoggingLevel.ERROR,
            'RESOLVED CHAIRPERSON STATUS = [' +
            chairpersonStatus +
            ']'
        );


        /*
         * IMPORTANT:
         * If this fails, your Status picklist does not contain a
         * value with both "Chairperson" and "Approval".
         */
        System.assertNotEquals(
            null,
            chairpersonStatus,
            'Could not find a Status__c value containing both "Chairperson" and "Approval".'
        );


        /*
         * ---------------------------------------------------------
         * 4. CREATE DEFERMENT REQUEST
         * ---------------------------------------------------------
         */

        Deferment_Request__c req = new Deferment_Request__c(
            OwnerId                  = manager.Id,
            Programme__c             = programmeId,
            Account__c               = acc.Id,
            Status__c                = chairpersonStatus,
            Approval_Status__c       = 'Pending',
            Current_Role__c          = 'Chairperson',
            Current_Approver_User__c = chairperson.Id,
            Current_Approver_Ids__c  = String.valueOf(chairperson.Id)
        );

        insert req;


        /*
         * ---------------------------------------------------------
         * 5. REQUERY RECORD
         * ---------------------------------------------------------
         */

        Deferment_Request__c reqBeforeSubmit = [
            SELECT
                Id,
                OwnerId,
                Status__c,
                Approval_Status__c,
                Current_Role__c,
                Current_Approver_User__c,
                Current_Approver_Ids__c,
                Programme__c,
                Account__c
            FROM Deferment_Request__c
            WHERE Id = :req.Id
            LIMIT 1
        ];


        System.debug(
            LoggingLevel.ERROR,
            '================================================='
        );

        System.debug(
            LoggingLevel.ERROR,
            'BEFORE APPROVAL SUBMISSION'
        );

        System.debug(
            LoggingLevel.ERROR,
            'Request Id = ' +
            reqBeforeSubmit.Id
        );

        System.debug(
            LoggingLevel.ERROR,
            'Owner Id = ' +
            reqBeforeSubmit.OwnerId
        );

        System.debug(
            LoggingLevel.ERROR,
            'Status = ' +
            reqBeforeSubmit.Status__c
        );

        System.debug(
            LoggingLevel.ERROR,
            'Approval Status = ' +
            reqBeforeSubmit.Approval_Status__c
        );

        System.debug(
            LoggingLevel.ERROR,
            'Current Role = ' +
            reqBeforeSubmit.Current_Role__c
        );

        System.debug(
            LoggingLevel.ERROR,
            'Current Approver = ' +
            reqBeforeSubmit.Current_Approver_User__c
        );

        System.debug(
            LoggingLevel.ERROR,
            'Current Approver IDs = ' +
            reqBeforeSubmit.Current_Approver_Ids__c
        );

        System.debug(
            LoggingLevel.ERROR,
            'Programme = ' +
            reqBeforeSubmit.Programme__c
        );

        System.debug(
            LoggingLevel.ERROR,
            'Account = ' +
            reqBeforeSubmit.Account__c
        );

        System.debug(
            LoggingLevel.ERROR,
            '================================================='
        );


        /*
         * ---------------------------------------------------------
         * 6. SUBMIT INTO APPROVAL PROCESS
         * ---------------------------------------------------------
         */

        Approval.ProcessSubmitRequest submitRequest =
            new Approval.ProcessSubmitRequest();

        submitRequest.setObjectId(req.Id);

        /*
         * The Approval Process is configured to allow the
         * record owner to submit.
         */
        submitRequest.setSubmitterId(manager.Id);

        /*
         * IMPORTANT:
         * This must be the DEVELOPER NAME / UNIQUE NAME of the
         * Approval Process, not the label.
         */
        submitRequest.setProcessDefinitionNameOrId(
            'Deferment_Request_Approval_Process'
        );


        Approval.ProcessResult submitResult;


        try {

            submitResult = Approval.process(
                submitRequest
            );

        } catch (Exception ex) {

            System.debug(
                LoggingLevel.ERROR,
                '================================================='
            );

            System.debug(
                LoggingLevel.ERROR,
                'APPROVAL SUBMISSION FAILED'
            );

            System.debug(
                LoggingLevel.ERROR,
                'Exception Type = ' +
                ex.getTypeName()
            );

            System.debug(
                LoggingLevel.ERROR,
                'Exception Message = ' +
                ex.getMessage()
            );

            System.debug(
                LoggingLevel.ERROR,
                'Status = ' +
                reqBeforeSubmit.Status__c
            );

            System.debug(
                LoggingLevel.ERROR,
                'Approval Status = ' +
                reqBeforeSubmit.Approval_Status__c
            );

            System.debug(
                LoggingLevel.ERROR,
                'Current Role = ' +
                reqBeforeSubmit.Current_Role__c
            );

            System.debug(
                LoggingLevel.ERROR,
                'Current Approver = ' +
                reqBeforeSubmit.Current_Approver_User__c
            );

            System.debug(
                LoggingLevel.ERROR,
                'Owner = ' +
                reqBeforeSubmit.OwnerId
            );

            System.debug(
                LoggingLevel.ERROR,
                'Programme = ' +
                reqBeforeSubmit.Programme__c
            );

            System.debug(
                LoggingLevel.ERROR,
                '================================================='
            );

            throw ex;
        }


        System.debug(
            LoggingLevel.ERROR,
            'Approval submission success = ' +
            submitResult.isSuccess()
        );


        if (!submitResult.isSuccess()) {

            String errorMessage =
                'Approval submission failed.';


            if (
                submitResult.getErrors() != null &&
                !submitResult.getErrors().isEmpty()
            ) {

                for (
                    Database.Error error :
                    submitResult.getErrors()
                ) {

                    System.debug(
                        LoggingLevel.ERROR,
                        'Approval Error = ' +
                        error.getMessage()
                    );

                    errorMessage +=
                        ' ' +
                        error.getMessage();
                }
            }


            System.assert(
                false,
                errorMessage
            );
        }


        return req;
    }


    /*
     * =============================================================
     * TEST SETUP
     * =============================================================
     */
    @TestSetup
    static void testSetup() {
        // No common data required.
    }


    /*
     * =============================================================
     * TEST 1
     * NULL RECORD ID
     * =============================================================
     */
    @isTest
    static void testProcessApproval_NullRecordId_Throws() {

        Test.startTest();

        try {

            DefermentApprovalController.processApproval(
                null,
                'APPROVE',
                'Test comment'
            );

            System.assert(
                false,
                'Expected exception for null recordId.'
            );

        } catch (AuraHandledException ex) {

            System.assert(
                true,
                'Expected AuraHandledException.'
            );
        }

        Test.stopTest();
    }


    /*
     * =============================================================
     * TEST 2
     * INVALID ACTION
     * =============================================================
     */
    @isTest
    static void testProcessApproval_InvalidAction_Throws() {

        User chairperson   = createUser('Standard User', '1');
        User associateDean = createUser('Standard User', '2');
        User dean          = createUser('Standard User', '3');
        User manager       = createUser('Standard User', '4');


        Deferment_Request__c req;


        System.runAs(
            new User(Id = UserInfo.getUserId())
        ) {

            req = setupData(
                chairperson,
                associateDean,
                dean,
                manager
            );
        }


        Test.startTest();

        System.runAs(chairperson) {

            try {

                DefermentApprovalController.processApproval(
                    req.Id,
                    'MAYBE',
                    'Invalid action test'
                );

                System.assert(
                    false,
                    'Expected exception for invalid action.'
                );

            } catch (AuraHandledException ex) {

                System.assert(
                    true,
                    'Expected AuraHandledException.'
                );
            }
        }

        Test.stopTest();
    }


    /*
     * =============================================================
     * TEST 3
     * RECORD NOT FOUND
     * =============================================================
     */
    @isTest
    static void testProcessApproval_RecordNotFound_Throws() {

        Test.startTest();

        try {

            Id fakeId =
                Id.valueOf(
                    Deferment_Request__c.SObjectType
                    .getDescribe()
                    .getKeyPrefix() +
                    '000000000000AAA'
                );

            DefermentApprovalController.processApproval(
                fakeId,
                'APPROVE',
                'Test'
            );

            System.assert(
                false,
                'Expected record not found exception.'
            );

        } catch (Exception ex) {

            System.assert(
                true,
                'Expected exception.'
            );
        }

        Test.stopTest();
    }


    /*
     * =============================================================
     * TEST 4
     * UNAUTHORIZED USER
     * =============================================================
     */
    @isTest
    static void testProcessApproval_UnauthorizedUser_Throws() {

        User chairperson   = createUser('Standard User', '5');
        User associateDean = createUser('Standard User', '6');
        User dean          = createUser('Standard User', '7');
        User manager       = createUser('Standard User', '8');
        User randomUser    = createUser('Standard User', '9');


        Deferment_Request__c req;


        System.runAs(
            new User(Id = UserInfo.getUserId())
        ) {

            req = setupData(
                chairperson,
                associateDean,
                dean,
                manager
            );
        }


        Test.startTest();

        System.runAs(randomUser) {

            try {

                DefermentApprovalController.processApproval(
                    req.Id,
                    'APPROVE',
                    'Unauthorized test'
                );

                System.assert(
                    false,
                    'Expected unauthorized exception.'
                );

            } catch (AuraHandledException ex) {

                System.assert(
                    ex.getMessage().contains('not authorized'),
                    'Unexpected message: ' +
                    ex.getMessage()
                );
            }
        }

        Test.stopTest();
    }


    /*
     * =============================================================
     * TEST 5
     * CHAIRPERSON APPROVES
     * =============================================================
     */
    @isTest
    static void testProcessApproval_ChairpersonApproves_RoutesToNextLevel() {

        User chairperson   = createUser('Standard User', '10');
        User associateDean = createUser('Standard User', '11');
        User dean          = createUser('Standard User', '12');
        User manager       = createUser('Standard User', '13');


        Deferment_Request__c req;


        System.runAs(
            new User(Id = UserInfo.getUserId())
        ) {

            req = setupData(
                chairperson,
                associateDean,
                dean,
                manager
            );
        }


        Test.startTest();

        System.runAs(chairperson) {

            DefermentApprovalController.processApproval(
                req.Id,
                'APPROVE',
                'Looks good'
            );
        }

        Test.stopTest();


        Deferment_Request__c updated = [
            SELECT
                Status__c,
                Approval_Status__c,
                Current_Role__c,
                Current_Approver_User__c,
                Current_Approver_Ids__c
            FROM Deferment_Request__c
            WHERE Id = :req.Id
            LIMIT 1
        ];


        System.assertEquals(
            'Pending',
            updated.Approval_Status__c
        );


        System.assert(
            updated.Current_Role__c == 'Associate Dean' ||
            updated.Current_Role__c == 'Dean',
            'Expected routing to Associate Dean or Dean.'
        );


        System.assertNotEquals(
            null,
            updated.Current_Approver_User__c,
            'Next approver should be populated.'
        );
    }


    /*
     * =============================================================
     * TEST 6
     * FINAL APPROVAL
     * =============================================================
     */
    @isTest
    static void testProcessApproval_FinalApproval_CompletesRequest() {

        User chairperson   = createUser('Standard User', '14');
        User associateDean = createUser('Standard User', '15');
        User dean          = createUser('Standard User', '16');
        User manager       = createUser('Standard User', '17');


        Deferment_Request__c req;


        System.runAs(
            new User(Id = UserInfo.getUserId())
        ) {

            req = setupData(
                chairperson,
                associateDean,
                dean,
                manager
            );
        }


        Test.startTest();


        /*
         * CHAIRPERSON APPROVAL
         */
        System.runAs(chairperson) {

            DefermentApprovalController.processApproval(
                req.Id,
                'APPROVE',
                'Chairperson approved'
            );
        }


        /*
         * GET NEXT APPROVER
         */
        Deferment_Request__c afterChair = [
            SELECT
                Current_Role__c,
                Current_Approver_User__c
            FROM Deferment_Request__c
            WHERE Id = :req.Id
            LIMIT 1
        ];


        User nextApprover;


        if (
            afterChair.Current_Role__c ==
            'Associate Dean'
        ) {

            nextApprover = associateDean;

        } else {

            nextApprover = dean;
        }


        System.assertNotEquals(
            null,
            nextApprover,
            'Next approver should exist.'
        );


        /*
         * FINAL APPROVAL
         */
        System.runAs(nextApprover) {

            DefermentApprovalController.processApproval(
                req.Id,
                'APPROVE',
                'Final approval granted'
            );
        }


        Test.stopTest();


        /*
         * VERIFY FINAL STATE
         */
        Deferment_Request__c finalReq = [
            SELECT
                Status__c,
                Approval_Status__c,
                Current_Role__c,
                Current_Approver_User__c,
                Current_Approver_Ids__c
            FROM Deferment_Request__c
            WHERE Id = :req.Id
            LIMIT 1
        ];


        System.assertEquals(
            'Rejoining Details',
            finalReq.Status__c
        );


        System.assertEquals(
            'Pending',
            finalReq.Approval_Status__c
        );


        System.assertEquals(
            null,
            finalReq.Current_Role__c
        );


        System.assertEquals(
            null,
            finalReq.Current_Approver_User__c
        );


        System.assertEquals(
            null,
            finalReq.Current_Approver_Ids__c
        );
    }


    /*
     * =============================================================
     * TEST 7
     * REJECT
     * =============================================================
     */
    @isTest
    static void testProcessApproval_Reject_ResetsRequest() {

        User chairperson   = createUser('Standard User', '18');
        User associateDean = createUser('Standard User', '19');
        User dean          = createUser('Standard User', '20');
        User manager       = createUser('Standard User', '21');


        Deferment_Request__c req;


        System.runAs(
            new User(Id = UserInfo.getUserId())
        ) {

            req = setupData(
                chairperson,
                associateDean,
                dean,
                manager
            );
        }


        Test.startTest();


        System.runAs(chairperson) {

            DefermentApprovalController.processApproval(
                req.Id,
                'REJECT',
                'Not eligible'
            );
        }


        Test.stopTest();


        Deferment_Request__c rejected = [
            SELECT
                Status__c,
                Approval_Status__c,
                Current_Approver_User__c,
                Current_Approver_Ids__c
            FROM Deferment_Request__c
            WHERE Id = :req.Id
            LIMIT 1
        ];


        System.assertEquals(
            'Deferment Form Enabled',
            rejected.Status__c
        );


        System.assertEquals(
            'Rejected',
            rejected.Approval_Status__c
        );


        System.assertEquals(
            null,
            rejected.Current_Approver_User__c
        );


        System.assertEquals(
            null,
            rejected.Current_Approver_Ids__c
        );
    }


    /*
     * =============================================================
     * TEST 8
     * NO PENDING WORK ITEM
     * =============================================================
     */
    @isTest
    static void testProcessApproval_NoPendingWorkItem_Throws() {

        User chairperson   = createUser('Standard User', '22');
        User associateDean = createUser('Standard User', '23');
        User dean          = createUser('Standard User', '24');
        User manager       = createUser('Standard User', '25');


        /*
         * Create student Account.
         */
        Account acc;


        List<RecordType> studentRecordTypes = [
            SELECT
                Id,
                DeveloperName,
                Name,
                IsPersonType
            FROM RecordType
            WHERE
                SObjectType = 'Account'
                AND (
                    DeveloperName LIKE '%Student%'
                    OR Name LIKE '%Student%'
                )
            LIMIT 1
        ];


        if (
            !studentRecordTypes.isEmpty() &&
            studentRecordTypes[0].IsPersonType
        ) {

            acc = new Account(
                RecordTypeId = studentRecordTypes[0].Id,
                FirstName    = 'Test',
                LastName     = 'No Work Item Student'
            );

        } else {

            acc = new Account(
                Name = 'Test No Work Item Student'
            );

            if (!studentRecordTypes.isEmpty()) {
                acc.RecordTypeId =
                    studentRecordTypes[0].Id;
            }
        }


        insert acc;


        /*
         * IMPORTANT:
         * We must create Programme + Team because
         * Programme__c is required/used by the controller.
         */
        Id programmeId = createProgrammeAndTeam(
            chairperson,
            associateDean,
            dean,
            manager
        );


        /*
         * Resolve Status here.
         *
         * This fixes the previous:
         * "Variable does not exist: chairpersonStatus"
         */
        String chairpersonStatus = getStatusValue(
            'Chairperson',
            'Approval'
        );


        System.assertNotEquals(
            null,
            chairpersonStatus,
            'Chairperson approval status was not found.'
        );


        /*
         * Create request.
         *
         * We intentionally DO NOT submit this request to the
         * Approval Process.
         *
         * Therefore ProcessInstanceWorkitem should not exist.
         */
        Deferment_Request__c req =
            new Deferment_Request__c(
                OwnerId                  = manager.Id,
                Programme__c             = programmeId,
                Account__c               = acc.Id,
                Status__c                = chairpersonStatus,
                Approval_Status__c       = 'Pending',
                Current_Role__c          = 'Chairperson',
                Current_Approver_User__c = chairperson.Id,
                Current_Approver_Ids__c  = String.valueOf(
                    chairperson.Id
                )
            );


        insert req;


        Test.startTest();


        System.runAs(chairperson) {

            try {

                DefermentApprovalController.processApproval(
                    req.Id,
                    'APPROVE',
                    'No work item test'
                );


                System.assert(
                    false,
                    'Expected no pending work item exception.'
                );

            } catch (AuraHandledException ex) {

                System.assert(
                    ex.getMessage().contains(
                        'No pending approval work item'
                    ),
                    'Unexpected error: ' +
                    ex.getMessage()
                );
            }
        }


        Test.stopTest();
    }
    
    /*
 * =============================================================
 * TEST 9
 * INVALID CURRENT ROLE ON RECORD
 * =============================================================
 */
@isTest
static void testProcessApproval_InvalidCurrentRole_Throws() {

    User chairperson   = createUser('Standard User', '26');
    User associateDean = createUser('Standard User', '27');
    User dean          = createUser('Standard User', '28');
    User manager       = createUser('Standard User', '29');

    Deferment_Request__c req;

    System.runAs(new User(Id = UserInfo.getUserId())) {
        req = setupData(chairperson, associateDean, dean, manager);
    }

    // Current_Role__c is a restricted picklist, so arbitrary text such as
    // "Manager" cannot be stored. Null is the representable invalid state
    // that reaches the controller's final invalid-role guard.
    req.Current_Role__c = null;
    req.Current_Approver_Ids__c = String.valueOf(chairperson.Id);
    update req;

    Test.startTest();

    System.runAs(chairperson) {
        try {
            DefermentApprovalController.processApproval(
                req.Id,
                'APPROVE',
                'Invalid role test'
            );

            System.assert(false, 'Expected exception for invalid role.');

        } catch (AuraHandledException ex) {
            System.assertNotEquals(
        null,
        ex,
        'Expected AuraHandledException for invalid approval role.'
    );
        }
    }

    Test.stopTest();
}


/*
 * =============================================================
 * TEST 10
 * NO ASSOCIATE DEAN OR DEAN CONFIGURED
 * =============================================================
 */
@isTest
static void testProcessApproval_NoDeanOrAD_Throws() {

    User chairperson = createUser('Standard User', '30');
    User manager      = createUser('Standard User', '31');

    // Build a Programme + Team with ONLY a Chairperson —
    // deliberately no Associate Dean or Dean — to hit
    // approveChairperson()'s "no AD/Dean configured" throw.
    Program programme = new Program(
        Name                    = 'No AD Dean Programme ' + String.valueOf(DateTime.now().getTime()),
        Program_Code__c         = 'NAD' + String.valueOf(DateTime.now().getTime()).right(6),
        Programme_Type__c       = 'Part-time',
        Programme_Sub_Type__c   = 'Class Room',
        Short_Programme_Code__c = 'NAD'
    );
    insert programme;

    Program_Team__c team = new Program_Team__c(
        Name       = 'No AD Dean Team',
        Program__c = programme.Id
    );
    insert team;

    insert new Program_Team_Members__c(
        Program_Team__c = team.Id,
        Role__c         = 'Chairperson',
        User__c         = chairperson.Id
    );

    Account acc = createStudentAccount(
        'No AD Dean Student ' + String.valueOf(DateTime.now().getTime())
    );

    String chairpersonStatus = getStatusValue('Chairperson', 'Approval');
    System.assertNotEquals(null, chairpersonStatus, 'Chairperson status not found.');

    Deferment_Request__c req = new Deferment_Request__c(
        OwnerId                  = manager.Id,
        Programme__c             = programme.Id,
        Account__c               = acc.Id,
        Status__c                = chairpersonStatus,
        Approval_Status__c       = 'Pending',
        Current_Role__c          = 'Chairperson',
        Current_Approver_User__c = chairperson.Id,
        Current_Approver_Ids__c  = String.valueOf(chairperson.Id)
    );
    insert req;

    Approval.ProcessSubmitRequest submitRequest = new Approval.ProcessSubmitRequest();
    submitRequest.setObjectId(req.Id);
    submitRequest.setSubmitterId(manager.Id);
    submitRequest.setProcessDefinitionNameOrId('Deferment_Request_Approval_Process');
    Approval.process(submitRequest);

    Test.startTest();

    System.runAs(chairperson) {
        try {
            DefermentApprovalController.processApproval(
                req.Id,
                'APPROVE',
                'No AD/Dean test'
            );

            System.assert(false, 'Expected exception for missing AD/Dean.');

        } catch (AuraHandledException ex) {
            System.assertNotEquals(
        null,
        ex,
        'Expected AuraHandledException for missing Associate Dean or Dean.'
    );
        }
    }

    Test.stopTest();
}

    @isTest
    static void testApproverLookupHelpers() {
        User manager = createUser('Standard User', '32');
        User chairperson = createUser('Standard User', '33');
        Id programmeId = createProgrammeAndTeam(
            chairperson,
            createUser('Standard User', '34'),
            createUser('Standard User', '35'),
            manager
        );

        Test.startTest();
        List<Id> managers = DefermentApprovalController.getAllApprovers(
            programmeId,
            'Manager'
        );
        System.assertEquals(
            new List<Id>{ manager.Id },
            managers,
            'The Programme Manager should be returned.'
        );
        System.assertEquals(
            0,
            DefermentApprovalController.getAllApprovers(null, 'Manager').size(),
            'A null programme must return no approvers.'
        );
        System.assertEquals(
            manager.Id,
            DefermentApprovalController.findApprover(programmeId, 'Manager'),
            'findApprover should return the matching user.'
        );
        System.assertEquals(
            null,
            DefermentApprovalController.findApprover(programmeId, 'Nonexistent Role'),
            'An unmatched role should not return an approver.'
        );
        System.assertEquals(
            null,
            DefermentApprovalController.findApprover(null, 'Manager'),
            'A null programme must not return an approver.'
        );
        Test.stopTest();
    }
}
/**
 * Updated to match the current DefermentRequestController:
 *  - submitDefermentRequest(String requestJson) now takes a single JSON payload
 *    (DefermentRequestController.SubmitDefermentRequestWrapper), not 9 positional params.
 *  - getActiveDefermentRequest() window-status logic now checks Status__c
 *    ('Pending Chairperson's Approval' / 'Pending Dean's / AD's Approval' -> SUBMITTED,
 *    'Rejoining Details Updated' -> APPROVED) before falling back to date-based
 *    NOT_STARTED / REOPENED / EXPIRED / OPEN.
 *  - submitDefermentRequest() now resolves a Chairperson (or Dean/Associate Dean, on
 *    resubmission) approver via Program_Team_Members__c and calls Approval.process()
 *    against an approval process named 'Deferment_Request_Approval_Process'.
 *  - Document type strings updated to match the renamed labels: 'Approval Email
 *    (Screenshot) with Rejoining Condition', 'Rejoining Condition Acceptance Email
 *    Screenshot', 'Transaction Details (Screenshot)'.
 *
 * ASSUMPTIONS / DEPENDENCIES you should verify against your org before running this:
 *   1. There is an ACTIVE approval process named 'Deferment_Request_Approval_Process'
 *      on Deferment_Request__c, with its entry step's approver left "unassigned"
 *      (so setNextApproverIds() on Approval.ProcessSubmitRequest is honored).
 *   2. Program__c, Program_Team__c (lookup Program__c), and Program_Team_Members__c
 *      (lookup Program_Team__c, User__c, Role__c) field/object API names below match
 *      your schema. Adjust createProgramme()/createProgramTeam()/addProgramTeamMember()
 *      if your actual API names differ.
 *   3. Deferment_Request__c has a Programme__c lookup to Program__c and a
 *      Current_Role__c picklist, matching the controller.
 */
@IsTest
private class DefermentRequestControllerTest {

    /*
     * ---------------------------------------------------------
     * Test Data Helpers
     * ---------------------------------------------------------
     */

    /**
     * Community/portal users are often auto-assigned a UserRoleId (the account's
     * portal role), so "UserRoleId != null" alone is NOT enough to identify an
     * internal user - it can pick up a previously-created portal user, which then
     * fails with OP_WITH_INVALID_USER_TYPE_EXCEPTION when used as an Account owner.
     * Restrict explicitly to internal ("Standard") users with no Contact.
     */
    private static User getInternalUserWithRole() {
        return [
            SELECT Id
            FROM User
            WHERE UserRoleId != null
            AND IsActive = true
            AND UserType = 'Standard'
            AND ContactId = null
            LIMIT 1
        ];
    }

   private static Account createStudentAccount(String uniqueName) {

    // Portal account owner MUST have a Salesforce Role
    User internalOwner = getInternalUserWithRole();

    List<RecordType> studentRecordTypes = [
        SELECT Id, DeveloperName, Name, IsPersonType
        FROM RecordType
        WHERE SObjectType = 'Account'
        AND IsActive = true
        AND (
            DeveloperName LIKE '%Student%'
            OR Name LIKE '%Student%'
        )
        LIMIT 1
    ];

    System.assert(
        !studentRecordTypes.isEmpty(),
        'No Student Account Record Type found.'
    );

    RecordType studentRT = studentRecordTypes[0];

    Account acc;

    if (studentRT.IsPersonType) {

        acc = new Account(
            RecordTypeId = studentRT.Id,
            FirstName = 'Test',
            LastName = uniqueName,
            OwnerId = internalOwner.Id
        );

    } else {

        acc = new Account(
            RecordTypeId = studentRT.Id,
            Name = 'Test Student ' + uniqueName,
            OwnerId = internalOwner.Id
        );
    }

    insert acc;

    return acc;
}
   private static Contact createStudentContact(Account acc, String lastName) {

    // Re-query to get PersonContactId
    acc = [
        SELECT Id, IsPersonAccount, PersonContactId
        FROM Account
        WHERE Id = :acc.Id
        LIMIT 1
    ];

    // For Person Account, Salesforce automatically creates the Contact
    if (acc.IsPersonAccount) {

        Contact personContact = [
            SELECT Id, FirstName, LastName, AccountId, Email
            FROM Contact
            WHERE Id = :acc.PersonContactId
            LIMIT 1
        ];

        return personContact;
    }

    // For Business Account, create a Contact normally
    Contact con = new Contact(
        FirstName = 'Test',
        LastName = lastName,
        AccountId = acc.Id,
        Email = lastName.toLowerCase() + '@example.com'
    );

    insert con;
    return con;
}

    private static User createPortalUser(Contact con) {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Customer Community Plus User'
            LIMIT 1
        ];

        String uniqueValue = String.valueOf(DateTime.now().getTime()) + Math.round(Math.random() * 10000);

        User u = new User(
            FirstName = 'Portal',
            LastName = 'Student',
            Alias = 'pstu' + uniqueValue.right(4),
            Email = 'portalstudent' + uniqueValue + '@example.com',
            Username = 'portalstudent' + uniqueValue + '@example.com',
            CommunityNickname = 'portalstudent' + uniqueValue,
            ProfileId = p.Id,
            ContactId = con.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        // User is a setup object; Account/Contact are not - runAs avoids Mixed DML.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    // --- Programme / approver setup -----------------------------------------

    private static Id createProgramme(String name) {

    Program prog = new Program(
        Name = name,
        Program_Code__c = 'TEST-' + String.valueOf(DateTime.now().getTime()),
        Short_Programme_Code__c = 'AD1',

        // Use values that actually exist in your Program picklists
        Programme_Type__c = 'Part-time',
        Programme_Sub_Type__c = 'Class Room'
    );

    insert prog;
    return prog.Id;
}

    private static Id createProgramTeam(Id programmeId) {
        Program_Team__c team = new Program_Team__c(Program__c = programmeId);
        insert team;
        return team.Id;
    }

    private static void addProgramTeamMember(Id programTeamId, Id userId, String role) {
        Program_Team_Members__c member = new Program_Team_Members__c(
            Program_Team__c = programTeamId,
            User__c = userId,
            Role__c = role
        );
        insert member;
    }

    /**
     * Creates a Programme with a Chairperson and an Associate Dean approver
     * (both existing internal users), returning the Programme Id.
     */
    private static Id createProgrammeWithApprovers() {
        List<User> internalUsers = [
            SELECT Id FROM User
            WHERE UserRoleId != null
            AND IsActive = true
            AND UserType = 'Standard'
            AND ContactId = null
            LIMIT 2
        ];

        System.assert(
            internalUsers.size() >= 2,
            'Need at least 2 internal users with a role to act as Chairperson/Associate Dean.'
        );

        Id programmeId = createProgramme('Test Programme');
        Id teamId = createProgramTeam(programmeId);

        addProgramTeamMember(teamId, internalUsers[0].Id, 'Chairperson');
        addProgramTeamMember(teamId, internalUsers[1].Id, 'Associate Dean');

        return programmeId;
    }

    // --- Deferment_Request__c setup -----------------------------------------

    private static Deferment_Request__c createRequest(
        Id accountId,
        String status,
        Decimal fee,
        Datetime startDate,
        Datetime endDate
    ) {
        return createRequest(accountId, status, fee, startDate, endDate, null, null, null);
    }

    private static Deferment_Request__c createRequest(
        Id accountId,
        String status,
        Decimal fee,
        Datetime startDate,
        Datetime endDate,
        Id programmeId,
        String currentRole,
        String approvalStatus
    ) {
        Deferment_Request__c req = new Deferment_Request__c(
            Account__c = accountId,
            Status__c = status,
            Deferment_Application_Fee__c = fee,
            Break_Start_Date_Time__c = startDate,
            Break_End_Date_Time__c = endDate,
            Programme__c = programmeId,
            Current_Role__c = currentRole,
            Approval_Status__c = approvalStatus
        );
        insert req;

        return [
            SELECT Id, Name, Account__c, Status__c, Approval_Status__c,
                   Deferment_Application_Fee__c, Break_Start_Date_Time__c,
                   Break_End_Date_Time__c, Reason_for_Deferment__c,
                   Student_Submission_Date__c, Programme__c, Current_Role__c
            FROM Deferment_Request__c
            WHERE Id = :req.Id
        ];
    }

    private static String getBase64File() {
        return EncodingUtil.base64Encode(Blob.valueOf('Test file content'));
    }

    /**
     * Builds the JSON payload the controller now expects for submitDefermentRequest,
     * using the controller's own wrapper classes so field names always stay in sync.
     */
    private static String buildRequestJson(
        Id defermentRequestId,
        String reason,
        List<DefermentRequestController.DefermentFileWrapper> files
    ) {
        DefermentRequestController.SubmitDefermentRequestWrapper wrapper =
            new DefermentRequestController.SubmitDefermentRequestWrapper();
        wrapper.defermentRequestId = defermentRequestId;
        wrapper.reason = reason;
        wrapper.files = files;
        return JSON.serialize(wrapper);
    }

    private static DefermentRequestController.DefermentFileWrapper buildFile(
        String documentType,
        String base64Data,
        String fileName
    ) {
        DefermentRequestController.DefermentFileWrapper f =
            new DefermentRequestController.DefermentFileWrapper();
        f.documentType = documentType;
        f.base64Data = base64Data;
        f.fileName = fileName;
        return f;
    }

    // ---- UPDATED: document type strings now match the renamed labels ----

    private static List<DefermentRequestController.DefermentFileWrapper> allFourFiles() {
        String fileData = getBase64File();
        return new List<DefermentRequestController.DefermentFileWrapper>{
            buildFile('Documents to Support Request', fileData, 'support.pdf'),
            buildFile('Approval Email (Screenshot) with Rejoining Condition', fileData, 'approval.png'),
            buildFile('Rejoining Condition Acceptance Email Screenshot', fileData, 'rejoining.png'),
            buildFile('Transaction Details (Screenshot)', fileData, 'transaction.png')
        };
    }

    private static List<DefermentRequestController.DefermentFileWrapper> threeFilesNoFee() {
        String fileData = getBase64File();
        return new List<DefermentRequestController.DefermentFileWrapper>{
            buildFile('Documents to Support Request', fileData, 'support.pdf'),
            buildFile('Approval Email (Screenshot) with Rejoining Condition', fileData, 'approval.png'),
            buildFile('Rejoining Condition Acceptance Email Screenshot', fileData, 'rejoining.png')
        };
    }

    /*
     * ---------------------------------------------------------
     * getActiveDefermentRequest
     * ---------------------------------------------------------
     */

    @IsTest
    static void testGetActiveDefermentRequest_OpenWindow() {
        Account acc = createStudentAccount('Student Open Account');
        Contact con = createStudentContact(acc, 'OpenStudent');
        User portalUser = createPortalUser(con);

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 1000,
            Datetime.now().addHours(-1), Datetime.now().addHours(2)
        );

        System.runAs(portalUser) {
            Test.startTest();
            DefermentRequestController.DefermentRequestWrapper result =
                DefermentRequestController.getActiveDefermentRequest();
            Test.stopTest();

            System.assertEquals(req.Id, result.recordId, 'Request Id should match.');
            System.assertEquals(req.Name, result.requestNumber, 'Request number should match.');
            System.assertEquals('Deferment Form Enabled', result.status);
            System.assertEquals(Decimal.valueOf(1000), result.fee);
            System.assertEquals('OPEN', result.windowStatus, 'Request should be OPEN.');
            System.assert(result.windowMessage.contains('currently open'));
        }
    }

    @IsTest
    static void testGetActiveDefermentRequest_NotStarted() {
        Account acc = createStudentAccount('Student Future Account');
        Contact con = createStudentContact(acc, 'FutureStudent');
        User portalUser = createPortalUser(con);

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 1000,
            Datetime.now().addHours(2), Datetime.now().addHours(5)
        );

        System.runAs(portalUser) {
            Test.startTest();
            DefermentRequestController.DefermentRequestWrapper result =
                DefermentRequestController.getActiveDefermentRequest();
            Test.stopTest();

            System.assertEquals(req.Id, result.recordId);
            System.assertEquals('NOT_STARTED', result.windowStatus);
            System.assert(result.windowMessage.contains('not open yet'));
        }
    }

    @IsTest
    static void testGetActiveDefermentRequest_Expired() {
        Account acc = createStudentAccount('Student Expired Account');
        Contact con = createStudentContact(acc, 'ExpiredStudent');
        User portalUser = createPortalUser(con);

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 1000,
            Datetime.now().addHours(-5), Datetime.now().addHours(-2)
        );

        System.runAs(portalUser) {
            Test.startTest();
            DefermentRequestController.DefermentRequestWrapper result =
                DefermentRequestController.getActiveDefermentRequest();
            Test.stopTest();

            System.assertEquals(req.Id, result.recordId);
            System.assertEquals('EXPIRED', result.windowStatus);
            System.assert(result.windowMessage.contains('expired'));
        }
    }

    @IsTest
    static void testGetActiveDefermentRequest_Submitted() {
        Account acc = createStudentAccount('Student Submitted Account');
        Contact con = createStudentContact(acc, 'SubmittedStudent');
        User portalUser = createPortalUser(con);

        Deferment_Request__c req = createRequest(
            acc.Id, 'Pending Chairperson\'s Approval', 1000,
            Datetime.now().addHours(-5), Datetime.now().addHours(5)
        );
        req.Reason_for_Deferment__c = 'Personal reasons';
        req.Student_Submission_Date__c = Datetime.now();
        update req;

        System.runAs(portalUser) {
            Test.startTest();
            DefermentRequestController.DefermentRequestWrapper result =
                DefermentRequestController.getActiveDefermentRequest();
            Test.stopTest();

            System.assertEquals(req.Id, result.recordId);
            System.assertEquals('Pending Chairperson\'s Approval', result.status);
            System.assertEquals('Personal reasons', result.reason);
            System.assertEquals('SUBMITTED', result.windowStatus);
            System.assert(result.windowMessage.contains('under approval'));
        }
    }

   @IsTest
static void testGetActiveDefermentRequest_Approved() {
    Account acc = createStudentAccount('Student Approved Account');
    Contact con = createStudentContact(acc, 'ApprovedStudent');
    User portalUser = createPortalUser(con);

    Deferment_Request__c req = createRequest(
        acc.Id,
        'Rejoining Details',
        1000,
        Datetime.now().addHours(-5),
        Datetime.now().addHours(5)
    );

    System.runAs(portalUser) {
        Test.startTest();

        DefermentRequestController.DefermentRequestWrapper result =
            DefermentRequestController.getActiveDefermentRequest();

        Test.stopTest();

        System.assertEquals(
            'APPROVED',
            result.windowStatus,
            'Request with status Rejoining Details should be APPROVED.'
        );

        System.assert(
            result.windowMessage != null &&
            result.windowMessage.toLowerCase().contains('approved'),
            'Approved message should be returned.'
        );
    }
}
    @IsTest
    static void testGetActiveDefermentRequest_Reopened() {
        Account acc = createStudentAccount('Student Reopened Account');
        Contact con = createStudentContact(acc, 'ReopenedStudent');
        User portalUser = createPortalUser(con);

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 1000,
            Datetime.now().addHours(-5), Datetime.now().addHours(5),
            null, 'Chairperson', 'Rejected'
        );

        System.runAs(portalUser) {
            Test.startTest();
            DefermentRequestController.DefermentRequestWrapper result =
                DefermentRequestController.getActiveDefermentRequest();
            Test.stopTest();

            System.assertEquals('REOPENED', result.windowStatus);
            System.assert(result.windowMessage.contains('reopened'));
        }
    }

    @IsTest
    static void testGetActiveDefermentRequest_NoRequest() {
        Account acc = createStudentAccount('Student No Request Account');
        Contact con = createStudentContact(acc, 'NoRequestStudent');
        User portalUser = createPortalUser(con);

        System.runAs(portalUser) {
            Test.startTest();
            DefermentRequestController.DefermentRequestWrapper result =
                DefermentRequestController.getActiveDefermentRequest();
            Test.stopTest();

            System.assertNotEquals(null, result);
            System.assertEquals(null, result.recordId);
            System.assertEquals(null, result.status);
        }
    }

    /*
     * ---------------------------------------------------------
     * submitDefermentRequest - happy paths
     * (Requires an active 'Deferment_Request_Approval_Process' - see class header.)
     * ---------------------------------------------------------
     */

    @IsTest
    static void testSubmitDefermentRequest_WithFee() {
        Account acc = createStudentAccount('Student Fee Account');
        Contact con = createStudentContact(acc, 'FeeStudent');
        User portalUser = createPortalUser(con);
        Id programmeId = createProgrammeWithApprovers();

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 1000,
            Datetime.now().addHours(-1), Datetime.now().addHours(2),
            programmeId, null, null
        );

        String payload = buildRequestJson(req.Id, 'Personal reasons', allFourFiles());

        System.runAs(portalUser) {
            Test.startTest();
            String resultId = DefermentRequestController.submitDefermentRequest(payload);
            Test.stopTest();

            System.assertEquals(req.Id, resultId, 'Returned Id should be the existing request Id.');
        }

        Deferment_Request__c updated = [
            SELECT Status__c, Reason_for_Deferment__c, Student_Submission_Date__c, Approval_Status__c
            FROM Deferment_Request__c WHERE Id = :req.Id
        ];
        System.assertEquals('Pending Chairperson\'s Approval', updated.Status__c);
        System.assertEquals('Personal reasons', updated.Reason_for_Deferment__c);
        System.assertNotEquals(null, updated.Student_Submission_Date__c);
        System.assertEquals('Pending', updated.Approval_Status__c);

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :req.Id
        ];
        System.assertEquals(4, links.size(), 'Four files should be attached when fee is applicable.');
    }

    @IsTest
    static void testSubmitDefermentRequest_WithoutFee() {
        Account acc = createStudentAccount('Student No Fee Account');
        Contact con = createStudentContact(acc, 'NoFeeStudent');
        User portalUser = createPortalUser(con);
        Id programmeId = createProgrammeWithApprovers();

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 0,
            Datetime.now().addHours(-1), Datetime.now().addHours(2),
            programmeId, null, null
        );

        String payload = buildRequestJson(req.Id, 'Financial reasons', threeFilesNoFee());

        System.runAs(portalUser) {
            Test.startTest();
            String resultId = DefermentRequestController.submitDefermentRequest(payload);
            Test.stopTest();

            System.assertEquals(req.Id, resultId);
        }

        Deferment_Request__c updated = [
            SELECT Status__c, Reason_for_Deferment__c FROM Deferment_Request__c WHERE Id = :req.Id
        ];
        System.assertEquals('Pending Chairperson\'s Approval', updated.Status__c);
        System.assertEquals('Financial reasons', updated.Reason_for_Deferment__c);

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :req.Id
        ];
        System.assertEquals(3, links.size(), 'Only three files should be attached when fee is zero.');
    }

    /*
     * ---------------------------------------------------------
     * submitDefermentRequest - validation failures
     * (These fail before approver resolution, so no Programme setup needed.)
     * ---------------------------------------------------------
     */

    @IsTest
    static void testSubmitDefermentRequest_BlankReason() {
        Account acc = createStudentAccount('Student Blank Reason');
        Contact con = createStudentContact(acc, 'BlankReasonStudent');
        User portalUser = createPortalUser(con);

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 0,
            Datetime.now().addHours(-1), Datetime.now().addHours(2)
        );

        String payload = buildRequestJson(req.Id, '', allFourFiles());

        System.runAs(portalUser) {
            try {
                Test.startTest();
                DefermentRequestController.submitDefermentRequest(payload);
                Test.stopTest();
                System.assert(false, 'Exception should have been thrown for blank reason.');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex);
            }
        }
    }

    // ---- UPDATED: uses renamed document type strings for the surviving files ----

    @IsTest
    static void testSubmitDefermentRequest_DocumentsMissing() {
        Account acc = createStudentAccount('Student Documents Missing');
        Contact con = createStudentContact(acc, 'DocumentsMissingStudent');
        User portalUser = createPortalUser(con);

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 0,
            Datetime.now().addHours(-1), Datetime.now().addHours(2)
        );

        String fileData = getBase64File();
        List<DefermentRequestController.DefermentFileWrapper> files =
            new List<DefermentRequestController.DefermentFileWrapper>{
                buildFile('Approval Email (Screenshot) with Rejoining Condition', fileData, 'approval.png'),
                buildFile('Rejoining Condition Acceptance Email Screenshot', fileData, 'rejoining.png')
            };

        String payload = buildRequestJson(req.Id, 'Personal reasons', files);

        System.runAs(portalUser) {
            try {
                Test.startTest();
                DefermentRequestController.submitDefermentRequest(payload);
                Test.stopTest();
                System.assert(false, 'Exception should have been thrown for missing documents.');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex);
            }
        }
    }

    @IsTest
    static void testSubmitDefermentRequest_ApprovalEmailMissing() {
        Account acc = createStudentAccount('Student Approval Missing');
        Contact con = createStudentContact(acc, 'ApprovalMissingStudent');
        User portalUser = createPortalUser(con);

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 0,
            Datetime.now().addHours(-1), Datetime.now().addHours(2)
        );

        String fileData = getBase64File();
        List<DefermentRequestController.DefermentFileWrapper> files =
            new List<DefermentRequestController.DefermentFileWrapper>{
                buildFile('Documents to Support Request', fileData, 'support.pdf'),
                buildFile('Rejoining Condition Acceptance Email Screenshot', fileData, 'rejoining.png')
            };

        String payload = buildRequestJson(req.Id, 'Personal reasons', files);

        System.runAs(portalUser) {
            try {
                Test.startTest();
                DefermentRequestController.submitDefermentRequest(payload);
                Test.stopTest();
                System.assert(false, 'Exception should have been thrown for missing approval email.');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex);
            }
        }
    }

    @IsTest
    static void testSubmitDefermentRequest_RejoiningAcceptanceMissing() {
        Account acc = createStudentAccount('Student Rejoining Missing');
        Contact con = createStudentContact(acc, 'RejoiningMissingStudent');
        User portalUser = createPortalUser(con);

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 0,
            Datetime.now().addHours(-1), Datetime.now().addHours(2)
        );

        String fileData = getBase64File();
        List<DefermentRequestController.DefermentFileWrapper> files =
            new List<DefermentRequestController.DefermentFileWrapper>{
                buildFile('Documents to Support Request', fileData, 'support.pdf'),
                buildFile('Approval Email (Screenshot) with Rejoining Condition', fileData, 'approval.png')
            };

        String payload = buildRequestJson(req.Id, 'Personal reasons', files);

        System.runAs(portalUser) {
            try {
                Test.startTest();
                DefermentRequestController.submitDefermentRequest(payload);
                Test.stopTest();
                System.assert(false, 'Exception should have been thrown for missing rejoining acceptance.');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex);
            }
        }
    }

    @IsTest
    static void testSubmitDefermentRequest_TransactionMissing() {
        Account acc = createStudentAccount('Student Transaction Missing');
        Contact con = createStudentContact(acc, 'TransactionMissingStudent');
        User portalUser = createPortalUser(con);

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 1000,
            Datetime.now().addHours(-1), Datetime.now().addHours(2)
        );

        String payload = buildRequestJson(req.Id, 'Personal reasons', threeFilesNoFee());

        System.runAs(portalUser) {
            try {
                Test.startTest();
                DefermentRequestController.submitDefermentRequest(payload);
                Test.stopTest();
                System.assert(false, 'Exception should have been thrown when fee > 0 and transaction file missing.');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex);
            }
        }
    }

    @IsTest
    static void testSubmitDefermentRequest_UnauthorizedUser() {
        Account ownerAccount = createStudentAccount('Request Owner Account');
        Contact ownerContact = createStudentContact(ownerAccount, 'RequestOwner');
        createPortalUser(ownerContact);

        Account otherAccount = createStudentAccount('Other Student Account');
        Contact otherContact = createStudentContact(otherAccount, 'OtherStudent');
        User otherUser = createPortalUser(otherContact);

        Deferment_Request__c req = createRequest(
            ownerAccount.Id, 'Deferment Form Enabled', 0,
            Datetime.now().addHours(-1), Datetime.now().addHours(2)
        );

        String payload = buildRequestJson(req.Id, 'Trying to update another request', threeFilesNoFee());

        System.runAs(otherUser) {
            try {
                Test.startTest();
                DefermentRequestController.submitDefermentRequest(payload);
                Test.stopTest();
                System.assert(false, 'Unauthorized user should not update the request.');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex);
            }
        }
    }

    @IsTest
    static void testSubmitDefermentRequest_NullRequestId() {
        Account acc = createStudentAccount('Student Null Request');
        Contact con = createStudentContact(acc, 'NullRequestStudent');
        User portalUser = createPortalUser(con);

        String payload = buildRequestJson(null, 'Personal reasons', allFourFiles());

        System.runAs(portalUser) {
            try {
                Test.startTest();
                DefermentRequestController.submitDefermentRequest(payload);
                Test.stopTest();
                System.assert(false, 'Exception should have been thrown for null request Id.');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex);
            }
        }
    }

    @IsTest
    static void testSubmitDefermentRequest_BlankPayload() {
        try {
            Test.startTest();
            DefermentRequestController.submitDefermentRequest('');
            Test.stopTest();
            System.assert(false, 'Exception should have been thrown for a blank JSON payload.');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex);
        }
    }

    @IsTest
    static void testSubmitDefermentRequest_WindowClosed() {
        Account acc = createStudentAccount('Student Window Closed');
        Contact con = createStudentContact(acc, 'WindowClosedStudent');
        User portalUser = createPortalUser(con);

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 0,
            Datetime.now().addHours(-5), Datetime.now().addHours(-1)
        );

        String payload = buildRequestJson(req.Id, 'Personal reasons', threeFilesNoFee());

        System.runAs(portalUser) {
            try {
                Test.startTest();
                DefermentRequestController.submitDefermentRequest(payload);
                Test.stopTest();
                System.assert(false, 'Exception should have been thrown once the deferment window has closed.');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex);
            }
        }
    }

    /*
     * ---------------------------------------------------------
     * getUploadedDocuments
     * ---------------------------------------------------------
     */

    @IsTest
    static void testGetUploadedDocuments() {
        Account acc = createStudentAccount('Student Docs Account');
        Contact con = createStudentContact(acc, 'DocsStudent');

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 0,
            Datetime.now().addHours(-1), Datetime.now().addHours(2)
        );

        ContentVersion cv = new ContentVersion();
        cv.Title = 'Documents to Support Request - support.pdf';
        cv.PathOnClient = 'support.pdf';
        cv.VersionData = Blob.valueOf('doc content');
        cv.FirstPublishLocationId = req.Id;
        insert cv;

        Test.startTest();
        List<Map<String, String>> docs = DefermentRequestController.getUploadedDocuments(req.Id);
        Test.stopTest();

        System.assertEquals(1, docs.size());
        System.assertEquals('Documents to Support Request', docs[0].get('documentType'));
        System.assertEquals('support.pdf', docs[0].get('fileName'));
    }

    @IsTest
    static void testGetUploadedDocuments_NullRecordId() {
        Test.startTest();
        List<Map<String, String>> docs = DefermentRequestController.getUploadedDocuments(null);
        Test.stopTest();

        System.assertEquals(0, docs.size());
    }

    /*
     * ---------------------------------------------------------
     * getApprovalRemarks
     * ---------------------------------------------------------
     */

    @IsTest
    static void testGetApprovalRemarks_NullRecordId() {
        Test.startTest();
        Map<String, String> remarks = DefermentRequestController.getApprovalRemarks(null);
        Test.stopTest();

        System.assertEquals('', remarks.get('L1'));
        System.assertEquals('', remarks.get('L2'));
    }

    /*
     * ---------------------------------------------------------
     * getApprovalHistory
     * (Exercised end-to-end via a real submission, since ProcessInstanceStep /
     * ProcessInstanceWorkitem are system objects that can't be inserted directly.
     * Requires the same active approval process as the submit happy-path tests.)
     * ---------------------------------------------------------
     */

    @IsTest
    static void testGetApprovalHistory_AfterSubmission() {
        Account acc = createStudentAccount('Student History Account');
        Contact con = createStudentContact(acc, 'HistoryStudent');
        User portalUser = createPortalUser(con);
        Id programmeId = createProgrammeWithApprovers();

        Deferment_Request__c req = createRequest(
            acc.Id, 'Deferment Form Enabled', 0,
            Datetime.now().addHours(-1), Datetime.now().addHours(2),
            programmeId, null, null
        );

        String payload = buildRequestJson(req.Id, 'Personal reasons', threeFilesNoFee());

        System.runAs(portalUser) {
            DefermentRequestController.submitDefermentRequest(payload);
        }

        Test.startTest();
        List<DefermentRequestController.ApprovalHistoryWrapper> history =
            DefermentRequestController.getApprovalHistory(req.Id);
        Test.stopTest();

        System.assert(!history.isEmpty(), 'History should contain at least the Submitted step.');
        System.assertEquals('Deferment Request Submitted', history[0].stepName);
        System.assertEquals('Submitted', history[0].status);
    }

    @IsTest
    static void testGetApprovalHistory_NullRecordId() {
        Test.startTest();
        List<DefermentRequestController.ApprovalHistoryWrapper> history =
            DefermentRequestController.getApprovalHistory(null);
        Test.stopTest();

        System.assert(history.isEmpty());
    }
}
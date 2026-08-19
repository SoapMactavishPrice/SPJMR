@IsTest
private class DefermentRequestControllerTest {

    // =========================================================
    // TEST DATA HELPERS
    // =========================================================

    private static Account createStudentAccount() {
        Account acc = new Account(
            Name = 'Test Student Account'
        );
        insert acc;
        return acc;
    }

    private static Contact createStudentContact(Id accountId) {
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Student',
            Email = 'test.student.' + System.currentTimeMillis() + '@example.com',
            AccountId = accountId
        );
        insert con;
        return con;
    }

    private static Deferment_Request__c createDefermentRequest(
        Id accountId,
        String status,
        Decimal fee,
        Datetime startDateTime,
        Datetime endDateTime
    ) {
        Deferment_Request__c req = new Deferment_Request__c(
            Account__c = accountId,
            Status__c = status,
            Deferment_Application_Fee__c = fee,
            Break_Start_Date_Time__c = startDateTime,
            Break_End_Date_Time__c = endDateTime
        );

        insert req;
        return req;
    }

    private static String base64File(String value) {
        return EncodingUtil.base64Encode(
            Blob.valueOf(value)
        );
    }


    // =========================================================
    // 1. GET ACTIVE REQUEST - MATCHING REQUEST
    // =========================================================

    @IsTest
    static void testGetActiveDefermentRequest() {

        Account acc = createStudentAccount();
        Contact con = createStudentContact(acc.Id);

        User portalUser = createPortalUser(con.Id);

        Datetime now = Datetime.now();

        Deferment_Request__c req = createDefermentRequest(
            acc.Id,
            'Deferment Form Enabled',
            5000,
            now.addHours(-2),
            now.addHours(2)
        );

        req.Reason_for_Deferment__c = 'Personal reasons';
        update req;

        System.runAs(portalUser) {

            Test.startTest();

            DefermentRequestController.DefermentRequestWrapper result =
                DefermentRequestController.getActiveDefermentRequest();

            Test.stopTest();

            System.assertNotEquals(
                null,
                result,
                'Wrapper should not be null.'
            );

            System.assertEquals(
                req.Id,
                result.recordId,
                'The existing deferment request should be returned.'
            );

            System.assertEquals(
                req.Name,
                result.requestNumber
            );

            System.assertEquals(
                'Deferment Form Enabled',
                result.status
            );

            System.assertEquals(
                'Personal reasons',
                result.reason
            );

            System.assertEquals(
                5000,
                result.fee
            );

            System.assertEquals(
                acc.Id,
                result.debugResolvedAccountId
            );

            System.assertEquals(
                1,
                result.debugRecordCountMatchingFilters
            );

            System.assertNotEquals(
                null,
                result.debugNow
            );
        }
    }


    // =========================================================
    // 2. GET ACTIVE REQUEST - NO REQUEST
    // =========================================================

    @IsTest
    static void testGetActiveDefermentRequest_NoRequest() {

        Account acc = createStudentAccount();
        Contact con = createStudentContact(acc.Id);

        User portalUser = createPortalUser(con.Id);

        System.runAs(portalUser) {

            Test.startTest();

            DefermentRequestController.DefermentRequestWrapper result =
                DefermentRequestController.getActiveDefermentRequest();

            Test.stopTest();

            System.assertNotEquals(
                null,
                result,
                'Current implementation always returns a wrapper.'
            );

            System.assertEquals(
                null,
                result.recordId,
                'No request should be returned.'
            );

            System.assertEquals(
                0,
                result.debugRecordCountMatchingFilters
            );
        }
    }


    // =========================================================
    // 3. GET ACTIVE REQUEST - OUTSIDE DATE WINDOW
    // =========================================================

    @IsTest
    static void testGetActiveDefermentRequest_OutsideDateWindow() {

        Account acc = createStudentAccount();
        Contact con = createStudentContact(acc.Id);

        User portalUser = createPortalUser(con.Id);

        Datetime now = Datetime.now();

        createDefermentRequest(
            acc.Id,
            'Deferment Form Enabled',
            5000,
            now.addDays(-5),
            now.addDays(-2)
        );

        System.runAs(portalUser) {

            Test.startTest();

            DefermentRequestController.DefermentRequestWrapper result =
                DefermentRequestController.getActiveDefermentRequest();

            Test.stopTest();

            System.assertNotEquals(
                null,
                result
            );

            System.assertEquals(
                null,
                result.recordId,
                'Expired request should not be returned.'
            );

            System.assertEquals(
                0,
                result.debugRecordCountMatchingFilters
            );
        }
    }


    // =========================================================
    // 4. GET ACTIVE REQUEST - NON ENABLED STATUS
    // =========================================================

    @IsTest
    static void testGetActiveDefermentRequest_NonEnabledStatus() {

        Account acc = createStudentAccount();
        Contact con = createStudentContact(acc.Id);

        User portalUser = createPortalUser(con.Id);

        Datetime now = Datetime.now();

        Deferment_Request__c req = createDefermentRequest(
            acc.Id,
            'Form Submitted',
            5000,
            now.addHours(-2),
            now.addHours(2)
        );

        System.runAs(portalUser) {

            Test.startTest();

            DefermentRequestController.DefermentRequestWrapper result =
                DefermentRequestController.getActiveDefermentRequest();

            Test.stopTest();

            System.assertNotEquals(
                null,
                result
            );

            /*
             * Your current SOQL intentionally allows statuses other than
             * "Deferment Form Enabled".
             */
            System.assertEquals(
                req.Id,
                result.recordId
            );

            System.assertEquals(
                'Form Submitted',
                result.status
            );
        }
    }


    // =========================================================
    // 5. SUCCESSFUL SUBMISSION - FEE > 0
    // =========================================================

    @IsTest
    static void testSubmitDefermentRequest_WithFee() {

        Account acc = createStudentAccount();
        Contact con = createStudentContact(acc.Id);

        User portalUser = createPortalUser(con.Id);

        Datetime now = Datetime.now();

        Deferment_Request__c req = createDefermentRequest(
            acc.Id,
            'Deferment Form Enabled',
            5000,
            now.addHours(-1),
            now.addHours(2)
        );

        String documentsData =
            base64File('Documents supporting deferment');

        String approvalData =
            base64File('Approval email screenshot');

        String rejoiningData =
            base64File('Rejoining acceptance screenshot');

        String transactionData =
            base64File('Transaction screenshot');

        System.runAs(portalUser) {

            Test.startTest();

            String returnedId =
                DefermentRequestController.submitDefermentRequest(
                    req.Id,
                    'Personal reasons',
                    documentsData,
                    'supporting-document.pdf',
                    approvalData,
                    'approval-email.png',
                    rejoiningData,
                    'rejoining-acceptance.png',
                    transactionData,
                    'transaction.png'
                );

            Test.stopTest();

            System.assertEquals(
                req.Id,
                returnedId,
                'Existing request Id should be returned.'
            );
        }

        Deferment_Request__c updatedReq = [
            SELECT Id,
                   Reason_for_Deferment__c,
                   Status__c,
                   Student_Submission_Date__c
            FROM Deferment_Request__c
            WHERE Id = :req.Id
        ];

        System.assertEquals(
            'Personal reasons',
            updatedReq.Reason_for_Deferment__c
        );

        System.assertEquals(
            'Form Submitted',
            updatedReq.Status__c
        );

        System.assertNotEquals(
            null,
            updatedReq.Student_Submission_Date__c
        );

        List<ContentDocumentLink> links = [
            SELECT Id,
                   LinkedEntityId,
                   ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :req.Id
        ];

        System.assertEquals(
            4,
            links.size(),
            'Four files should be attached when fee is applicable.'
        );
    }


    // =========================================================
    // 6. SUCCESSFUL SUBMISSION - FEE = 0
    // =========================================================

    @IsTest
    static void testSubmitDefermentRequest_NoFee() {

        Account acc = createStudentAccount();
        Contact con = createStudentContact(acc.Id);

        User portalUser = createPortalUser(con.Id);

        Datetime now = Datetime.now();

        Deferment_Request__c req = createDefermentRequest(
            acc.Id,
            'Deferment Form Enabled',
            0,
            now.addHours(-1),
            now.addHours(2)
        );

        String documentsData =
            base64File('Documents supporting deferment');

        String approvalData =
            base64File('Approval email screenshot');

        String rejoiningData =
            base64File('Rejoining acceptance screenshot');

        System.runAs(portalUser) {

            Test.startTest();

            String returnedId =
                DefermentRequestController.submitDefermentRequest(
                    req.Id,
                    'Personal reasons',
                    documentsData,
                    'supporting-document.pdf',
                    approvalData,
                    'approval-email.png',
                    rejoiningData,
                    'rejoining-acceptance.png',
                    null,
                    null
                );

            Test.stopTest();

            System.assertEquals(
                req.Id,
                returnedId
            );
        }

        Deferment_Request__c updatedReq = [
            SELECT Id,
                   Reason_for_Deferment__c,
                   Status__c,
                   Student_Submission_Date__c
            FROM Deferment_Request__c
            WHERE Id = :req.Id
        ];

        System.assertEquals(
            'Personal reasons',
            updatedReq.Reason_for_Deferment__c
        );

        System.assertEquals(
            'Form Submitted',
            updatedReq.Status__c
        );

        System.assertNotEquals(
            null,
            updatedReq.Student_Submission_Date__c
        );

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :req.Id
        ];

        System.assertEquals(
            3,
            links.size(),
            'Only three files should be attached when fee = 0.'
        );
    }


    // =========================================================
    // 7. SUBMISSION - MISSING REASON
    // =========================================================

    @IsTest
    static void testSubmitDefermentRequest_MissingReason() {

        Account acc = createStudentAccount();
        Contact con = createStudentContact(acc.Id);

        User portalUser = createPortalUser(con.Id);

        Datetime now = Datetime.now();

        Deferment_Request__c req = createDefermentRequest(
            acc.Id,
            'Deferment Form Enabled',
            0,
            now.addHours(-1),
            now.addHours(2)
        );

        System.runAs(portalUser) {

            Test.startTest();

            try {

                DefermentRequestController.submitDefermentRequest(
                    req.Id,
                    '',
                    base64File('Documents'),
                    'documents.pdf',
                    base64File('Approval'),
                    'approval.png',
                    base64File('Rejoining'),
                    'rejoining.png',
                    null,
                    null
                );

                System.assert(
                    false,
                    'Expected missing reason exception.'
                );

            } catch (AuraHandledException ex) {

                System.assert(
                    ex.getMessage().contains(
                        'Reason for Deferment is required'
                    )
                );
            }

            Test.stopTest();
        }
    }


    // =========================================================
    // 8. SUBMISSION - MISSING DOCUMENTS
    // =========================================================

    @IsTest
    static void testSubmitDefermentRequest_MissingDocuments() {

        Account acc = createStudentAccount();
        Contact con = createStudentContact(acc.Id);

        User portalUser = createPortalUser(con.Id);

        Datetime now = Datetime.now();

        Deferment_Request__c req = createDefermentRequest(
            acc.Id,
            'Deferment Form Enabled',
            0,
            now.addHours(-1),
            now.addHours(2)
        );

        System.runAs(portalUser) {

            Test.startTest();

            try {

                DefermentRequestController.submitDefermentRequest(
                    req.Id,
                    'Personal reasons',
                    null,
                    null,
                    base64File('Approval'),
                    'approval.png',
                    base64File('Rejoining'),
                    'rejoining.png',
                    null,
                    null
                );

                System.assert(
                    false,
                    'Expected missing documents exception.'
                );

            } catch (AuraHandledException ex) {

                System.assert(
                    ex.getMessage().contains(
                        'Documents to Support Request is required'
                    )
                );
            }

            Test.stopTest();
        }
    }


    // =========================================================
    // 9. SUBMISSION - MISSING APPROVAL EMAIL
    // =========================================================

    @IsTest
    static void testSubmitDefermentRequest_MissingApprovalEmail() {

        Account acc = createStudentAccount();
        Contact con = createStudentContact(acc.Id);

        User portalUser = createPortalUser(con.Id);

        Datetime now = Datetime.now();

        Deferment_Request__c req = createDefermentRequest(
            acc.Id,
            'Deferment Form Enabled',
            0,
            now.addHours(-1),
            now.addHours(2)
        );

        System.runAs(portalUser) {

            Test.startTest();

            try {

                DefermentRequestController.submitDefermentRequest(
                    req.Id,
                    'Personal reasons',
                    base64File('Documents'),
                    'documents.pdf',
                    null,
                    null,
                    base64File('Rejoining'),
                    'rejoining.png',
                    null,
                    null
                );

                System.assert(
                    false,
                    'Expected missing approval email exception.'
                );

            } catch (AuraHandledException ex) {

                System.assert(
                    ex.getMessage().contains(
                        'Approval Email screenshot is required'
                    )
                );
            }

            Test.stopTest();
        }
    }


    // =========================================================
    // 10. SUBMISSION - MISSING REJOINING ACCEPTANCE
    // =========================================================

    @IsTest
    static void testSubmitDefermentRequest_MissingRejoiningAcceptance() {

        Account acc = createStudentAccount();
        Contact con = createStudentContact(acc.Id);

        User portalUser = createPortalUser(con.Id);

        Datetime now = Datetime.now();

        Deferment_Request__c req = createDefermentRequest(
            acc.Id,
            'Deferment Form Enabled',
            0,
            now.addHours(-1),
            now.addHours(2)
        );

        System.runAs(portalUser) {

            Test.startTest();

            try {

                DefermentRequestController.submitDefermentRequest(
                    req.Id,
                    'Personal reasons',
                    base64File('Documents'),
                    'documents.pdf',
                    base64File('Approval'),
                    'approval.png',
                    null,
                    null,
                    null,
                    null
                );

                System.assert(
                    false,
                    'Expected missing rejoining acceptance exception.'
                );

            } catch (AuraHandledException ex) {

                System.assert(
                    ex.getMessage().contains(
                        'Rejoining Condition Acceptance Email screenshot is required'
                    )
                );
            }

            Test.stopTest();
        }
    }


    // =========================================================
    // 11. SUBMISSION - MISSING TRANSACTION DETAILS
    // =========================================================

    @IsTest
    static void testSubmitDefermentRequest_MissingTransaction() {

        Account acc = createStudentAccount();
        Contact con = createStudentContact(acc.Id);

        User portalUser = createPortalUser(con.Id);

        Datetime now = Datetime.now();

        Deferment_Request__c req = createDefermentRequest(
            acc.Id,
            'Deferment Form Enabled',
            5000,
            now.addHours(-1),
            now.addHours(2)
        );

        System.runAs(portalUser) {

            Test.startTest();

            try {

                DefermentRequestController.submitDefermentRequest(
                    req.Id,
                    'Personal reasons',
                    base64File('Documents'),
                    'documents.pdf',
                    base64File('Approval'),
                    'approval.png',
                    base64File('Rejoining'),
                    'rejoining.png',
                    null,
                    null
                );

                System.assert(
                    false,
                    'Expected missing transaction exception.'
                );

            } catch (AuraHandledException ex) {

                System.assert(
                    ex.getMessage().contains(
                        'Transaction Details screenshot is required'
                    )
                );
            }

            Test.stopTest();
        }
    }


    // =========================================================
    // 12. SUBMISSION - UNAUTHORIZED REQUEST
    // =========================================================

    @IsTest
    static void testSubmitDefermentRequest_Unauthorized() {

        Account studentAccount = createStudentAccount();
        Contact studentContact = createStudentContact(
            studentAccount.Id
        );

        User portalUser = createPortalUser(
            studentContact.Id
        );

        Account anotherAccount = new Account(
            Name = 'Another Student Account'
        );
        insert anotherAccount;

        Datetime now = Datetime.now();

        Deferment_Request__c req = createDefermentRequest(
            anotherAccount.Id,
            'Deferment Form Enabled',
            0,
            now.addHours(-1),
            now.addHours(2)
        );

        System.runAs(portalUser) {

            Test.startTest();

            try {

                DefermentRequestController.submitDefermentRequest(
                    req.Id,
                    'Personal reasons',
                    base64File('Documents'),
                    'documents.pdf',
                    base64File('Approval'),
                    'approval.png',
                    base64File('Rejoining'),
                    'rejoining.png',
                    null,
                    null
                );

                System.assert(
                    false,
                    'Expected authorization exception.'
                );

            } catch (AuraHandledException ex) {

                System.assert(
                    ex.getMessage().contains(
                        'You are not authorized to update this request'
                    )
                );
            }

            Test.stopTest();
        }
    }


    // =========================================================
    // 13. NULL REQUEST ID
    // =========================================================

    @IsTest
    static void testSubmitDefermentRequest_NullRequestId() {

        Test.startTest();

        try {

            DefermentRequestController.submitDefermentRequest(
                null,
                'Personal reasons',
                base64File('Documents'),
                'documents.pdf',
                base64File('Approval'),
                'approval.png',
                base64File('Rejoining'),
                'rejoining.png',
                null,
                null
            );

            System.assert(
                false,
                'Expected null request Id exception.'
            );

        } catch (AuraHandledException ex) {

            System.assert(
                ex.getMessage().contains(
                    'No active deferment request found to update'
                )
            );
        }

        Test.stopTest();
    }


    // =========================================================
    // PORTAL USER CREATION
    // =========================================================

    private static User createPortalUser(Id contactId) {

        Contact con = [
            SELECT Id,
                   AccountId,
                   FirstName,
                   LastName,
                   Email
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];

        Profile portalProfile = [
            SELECT Id, Name
            FROM Profile
            WHERE UserType IN (
                'CustomerCommunity',
                'CustomerCommunityPlus',
                'CustomerSuccess'
            )
            LIMIT 1
        ];

        User user = new User(
            FirstName = 'Portal',
            LastName = 'Student',
            Email = 'portal.' + System.currentTimeMillis() + '@example.com',
            Username = 'portal.' + System.currentTimeMillis() + '@example.com',
            Alias = 'pstud',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = portalProfile.Id,
            ContactId = con.Id
        );

        insert user;

        return user;
    }
}
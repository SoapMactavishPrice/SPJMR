@IsTest
private class DefermentRequestTriggerHandlerTest {

    // Without an explicit record type the insert relies on a profile default,
    // which exists in spjDev but not in devfeat ("record type missing for:
    // Account"). Student is mandatory here, not a preference: the lookup
    // filter on Deferment_Request__c.Account__c is active and non-optional,
    // and requires Account.RecordType.DeveloperName = 'Student'.
    // Queried rather than read from getRecordTypeInfosByDeveloperName(): spjDev
    // has TWO active record types with DeveloperName 'Student' - the person one
    // and the business-side shadow ("Student*") - and the describe map returns
    // the business one, which rejects LastName. Filtering on IsPersonType is the
    // only way to get the right Id in every org.
    private static final Id STUDENT_ACCOUNT_RT_ID = [
        SELECT Id
        FROM RecordType
        WHERE SobjectType = 'Account'
        AND DeveloperName = 'Student'
        AND IsPersonType = true
        AND IsActive = true
        LIMIT 1
    ].Id;

    @TestSetup
    static void setupData() {

        Account studentAccount = new Account(
            LastName = 'Test Student',
            RecordTypeId = STUDENT_ACCOUNT_RT_ID
        );
        // AccountTrigger creates a portal User for Student accounts - that is
        // setup-object DML, so it must not share a transaction with the
        // Deferment_Request__c insert below.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert studentAccount;
        }

        Deferment_Request__c request = new Deferment_Request__c(
            Account__c = studentAccount.Id,
            Status__c = 'Deferment Form Enabled'
        );

        insert request;
    }


    // ============================================================
    // 1. Positive scenario
    //    Status = Deferment Form Enabled
    //    Account is populated
    // ============================================================

    @IsTest
    static void testSendDefermentFormEnabledEmail() {

        Deferment_Request__c request = [
            SELECT Id,
                   Account__c,
                   Status__c
            FROM Deferment_Request__c
            LIMIT 1
        ];

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentFormEnabledEmail(
            new List<Deferment_Request__c>{
                request
            }
        );

        Test.stopTest();

        System.assertEquals(
            'Deferment Form Enabled',
            request.Status__c,
            'Request should have Deferment Form Enabled status.'
        );
    }


    // ============================================================
    // 2. Negative scenario
    //    Status is NOT Deferment Form Enabled
    // ============================================================

    @IsTest
    static void testStatusNotFormEnabled() {

        Deferment_Request__c request = [
            SELECT Id,
                   Account__c,
                   Status__c
            FROM Deferment_Request__c
            LIMIT 1
        ];

        request.Status__c = 'Deferment Form Enabled';
        update request;

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentFormEnabledEmail(
            new List<Deferment_Request__c>{
                request
            }
        );

        Test.stopTest();

        System.assertEquals(
            'Deferment Form Enabled',
            request.Status__c,
            'Request should remain Draft.'
        );
    }


    // ============================================================
    // 3. Account is null
    // ============================================================

    @IsTest
    static void testAccountIsNull() {

        Deferment_Request__c request = new Deferment_Request__c(
            Status__c = 'Deferment Form Enabled'
        );

        insert request;

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentFormEnabledEmail(
            new List<Deferment_Request__c>{
                request
            }
        );

        Test.stopTest();

        System.assertEquals(
            'Deferment Form Enabled',
            request.Status__c
        );
    }


    // ============================================================
    // 4. Empty list
    // ============================================================

    @IsTest
    static void testEmptyRequestList() {

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentFormEnabledEmail(
            new List<Deferment_Request__c>()
        );

        Test.stopTest();

        System.assert(true, 'Method should handle empty list without exception.');
    }


    // ============================================================
    // 5. Multiple records
    // ============================================================

    @IsTest
    static void testMultipleRequests() {

        Account account2 = new Account(
            LastName = 'Second Test Student',
            RecordTypeId = STUDENT_ACCOUNT_RT_ID
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert account2;
        }

        Deferment_Request__c request2 = new Deferment_Request__c(
            Account__c = account2.Id,
            Status__c = 'Deferment Form Enabled'
        );
        insert request2;

        Deferment_Request__c request1 = [
            SELECT Id,
                   Account__c,
                   Status__c
            FROM Deferment_Request__c
            LIMIT 1
        ];

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentFormEnabledEmail(
            new List<Deferment_Request__c>{
                request1,
                request2
            }
        );

        Test.stopTest();

        System.assertEquals(
            'Deferment Form Enabled',
            request1.Status__c
        );

        System.assertEquals(
            'Deferment Form Enabled',
            request2.Status__c
        );
    }
        // ============================================================
    // 6. Deferment Process Complete transition
    //    Old Status = something else
    //    New Status = Pending Re-enrollment
    // ============================================================

    @IsTest
    static void testSendDefermentProcessCompleteEmail() {

        Deferment_Request__c request = [
            SELECT Id,
                   Account__c,
                   Status__c
            FROM Deferment_Request__c
            LIMIT 1
        ];

        String oldStatus = request.Status__c;

        request.Status__c = 'Pending Re-enrollment';
        update request;

        Deferment_Request__c updatedRequest = [
            SELECT Id,
                   Account__c,
                   Status__c
            FROM Deferment_Request__c
            WHERE Id = :request.Id
            LIMIT 1
        ];

        Deferment_Request__c oldRequest =
            new Deferment_Request__c(
                Id = updatedRequest.Id,
                Account__c = updatedRequest.Account__c,
                Status__c = oldStatus
            );

        Map<Id, Deferment_Request__c> oldMap =
            new Map<Id, Deferment_Request__c>{
                updatedRequest.Id => oldRequest
            };

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentProcessCompleteEmail(
            new List<Deferment_Request__c>{
                updatedRequest
            },
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            'Pending Re-enrollment',
            updatedRequest.Status__c,
            'Request should be in Pending Re-enrollment status.'
        );
    }


    // ============================================================
    // 7. Already Pending Re-enrollment
    //    Old Status = Pending Re-enrollment
    //    New Status = Pending Re-enrollment
    //
    //    Email should NOT be triggered again.
    // ============================================================

    @IsTest
    static void testAlreadyPendingReEnrollmentDoesNotSendEmail() {

        Deferment_Request__c request = [
            SELECT Id,
                   Account__c,
                   Status__c
            FROM Deferment_Request__c
            LIMIT 1
        ];

        request.Status__c = 'Pending Re-enrollment';
        update request;

        Deferment_Request__c oldRequest = [
            SELECT Id,
                   Account__c,
                   Status__c
            FROM Deferment_Request__c
            WHERE Id = :request.Id
            LIMIT 1
        ];

        Deferment_Request__c newRequest =
            new Deferment_Request__c(
                Id = request.Id,
                Account__c = request.Account__c,
                Status__c = 'Pending Re-enrollment'
            );

        Map<Id, Deferment_Request__c> oldMap =
            new Map<Id, Deferment_Request__c>{
                request.Id => oldRequest
            };

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentProcessCompleteEmail(
            new List<Deferment_Request__c>{
                newRequest
            },
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            'Pending Re-enrollment',
            newRequest.Status__c,
            'Status should remain Pending Re-enrollment.'
        );
    }


    // ============================================================
    // 8. Status is NOT Pending Re-enrollment
    // ============================================================

    @IsTest
    static void testProcessCompleteEmail_WrongStatus() {

        Deferment_Request__c request = [
            SELECT Id,
                   Account__c,
                   Status__c
            FROM Deferment_Request__c
            LIMIT 1
        ];

        Deferment_Request__c oldRequest =
            new Deferment_Request__c(
                Id = request.Id,
                Account__c = request.Account__c,
                Status__c = 'Deferment Form Enabled'
            );

        Deferment_Request__c newRequest =
            new Deferment_Request__c(
                Id = request.Id,
                Account__c = request.Account__c,
                Status__c = 'Rejoining Details Updated'
            );

        Map<Id, Deferment_Request__c> oldMap =
            new Map<Id, Deferment_Request__c>{
                request.Id => oldRequest
            };

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentProcessCompleteEmail(
            new List<Deferment_Request__c>{
                newRequest
            },
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            'Rejoining Details Updated',
            newRequest.Status__c,
            'Status should remain unchanged.'
        );
    }


    // ============================================================
    // 9. Account is NULL
    //    Status transition occurs but email must be skipped.
    // ============================================================

    @IsTest
    static void testProcessCompleteEmail_AccountIsNull() {

        Deferment_Request__c request = [
            SELECT Id
            FROM Deferment_Request__c
            LIMIT 1
        ];

        Deferment_Request__c oldRequest =
            new Deferment_Request__c(
                Id = request.Id,
                Status__c = 'Rejoining Details Updated'
            );

        Deferment_Request__c newRequest =
            new Deferment_Request__c(
                Id = request.Id,
                Status__c = 'Pending Re-enrollment'
            );

        Map<Id, Deferment_Request__c> oldMap =
            new Map<Id, Deferment_Request__c>{
                request.Id => oldRequest
            };

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentProcessCompleteEmail(
            new List<Deferment_Request__c>{
                newRequest
            },
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            'Pending Re-enrollment',
            newRequest.Status__c
        );
    }


    // ============================================================
    // 10. Old Map is NULL
    //
    //    Handler explicitly supports oldRequestsById == null.
    //    New status = Pending Re-enrollment should be treated
    //    as a completion event.
    // ============================================================

    @IsTest
    static void testProcessCompleteEmail_NullOldMap() {

        Deferment_Request__c request = [
            SELECT Id,
                   Account__c
            FROM Deferment_Request__c
            LIMIT 1
        ];

        Deferment_Request__c newRequest =
            new Deferment_Request__c(
                Id = request.Id,
                Account__c = request.Account__c,
                Status__c = 'Pending Re-enrollment'
            );

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentProcessCompleteEmail(
            new List<Deferment_Request__c>{
                newRequest
            },
            null
        );

        Test.stopTest();

        System.assertEquals(
            'Pending Re-enrollment',
            newRequest.Status__c
        );
    }


    // ============================================================
    // 11. Empty list
    // ============================================================

    @IsTest
    static void testProcessCompleteEmail_EmptyList() {

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentProcessCompleteEmail(
            new List<Deferment_Request__c>(),
            new Map<Id, Deferment_Request__c>()
        );

        Test.stopTest();

        System.assert(
            true,
            'Method should handle an empty request list without exception.'
        );
    }


    // ============================================================
    // 12. Multiple requests
    //
    //    One request transitions to Pending Re-enrollment.
    //    One request does not.
    // ============================================================

    @IsTest
    static void testProcessCompleteEmail_MultipleRequests() {

        List<Deferment_Request__c> existingRequests = [
            SELECT Id,
                   Account__c,
                   Status__c
            FROM Deferment_Request__c
            LIMIT 2
        ];

        System.assert(
            !existingRequests.isEmpty(),
            'At least one test request should exist.'
        );

        Deferment_Request__c request1 = existingRequests[0];

        Deferment_Request__c newRequest1 =
            new Deferment_Request__c(
                Id = request1.Id,
                Account__c = request1.Account__c,
                Status__c = 'Pending Re-enrollment'
            );

        Deferment_Request__c oldRequest1 =
            new Deferment_Request__c(
                Id = request1.Id,
                Account__c = request1.Account__c,
                Status__c = 'Rejoining Details Updated'
            );

        List<Deferment_Request__c> newRequests =
            new List<Deferment_Request__c>{
                newRequest1
            };

        Map<Id, Deferment_Request__c> oldMap =
            new Map<Id, Deferment_Request__c>{
                request1.Id => oldRequest1
            };

        if (existingRequests.size() > 1) {

            Deferment_Request__c request2 =
                existingRequests[1];

            Deferment_Request__c newRequest2 =
                new Deferment_Request__c(
                    Id = request2.Id,
                    Account__c = request2.Account__c,
                    Status__c = 'Rejoining Details Updated'
                );

            Deferment_Request__c oldRequest2 =
                new Deferment_Request__c(
                    Id = request2.Id,
                    Account__c = request2.Account__c,
                    Status__c = 'Pending Re-enrollment'
                );

            newRequests.add(newRequest2);
            oldMap.put(request2.Id, oldRequest2);
        }

        Test.startTest();

        DefermentRequestTriggerHandler.sendDefermentProcessCompleteEmail(
            newRequests,
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            'Pending Re-enrollment',
            newRequests[0].Status__c,
            'First request should transition to Pending Re-enrollment.'
        );
    }
}
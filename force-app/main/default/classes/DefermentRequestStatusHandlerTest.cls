@IsTest
private class DefermentRequestStatusHandlerTest {

    private static final String STATUS_COMPLETE = 'Deferment Process Complete';
    private static final String STATUS_PENDING = 'Pending Re-enrollment';
    // Was: 'Rejoining Details Updated' - not a member of the restricted
    // Status__c picklist, so every test using it failed on insert with
    // INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST. The org's value is
    // 'Rejoining Details'.
    private static final String STATUS_APPROVED = 'Rejoining Details';

    /**
     * @description Inserts one request at the given status.
     * @param status the Status__c value to start from
     * @return the inserted record
     */
    private static Deferment_Request__c buildRequest(String status) {

        Deferment_Request__c request = new Deferment_Request__c(
            Status__c = status
        );
        insert request;

        return request;
    }

    /**
     * @description Re-reads one record's stored status.
     * @param requestId the record to re-read
     * @return the stored Status__c value
     */
    private static String storedStatus(Id requestId) {

        return [
            SELECT Status__c
            FROM Deferment_Request__c
            WHERE Id = :requestId
        ].Status__c;
    }

    @IsTest
    static void movesToPendingReEnrollmentOnStatusChange() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            Deferment_Request__c request = buildRequest(STATUS_APPROVED);

            Test.startTest();
            request.Status__c = STATUS_COMPLETE;
            update request;
            Test.stopTest();

            System.assertEquals(
                STATUS_PENDING,
                storedStatus(request.Id),
                'Completing the deferment should park the student at Pending Re-enrollment.'
            );
        }
    }

    @IsTest
    static void movesToPendingReEnrollmentOnInsert() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            Test.startTest();
            Deferment_Request__c request = buildRequest(STATUS_COMPLETE);
            Test.stopTest();

            System.assertEquals(
                STATUS_PENDING,
                storedStatus(request.Id),
                'A request created as complete should also land on Pending Re-enrollment.'
            );
        }
    }

    @IsTest
    static void leavesEveryOtherStatusAlone() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            Deferment_Request__c request = buildRequest('Deferment Form Enabled');

            Test.startTest();
            request.Status__c = STATUS_APPROVED;
            update request;
            Test.stopTest();

            System.assertEquals(
                STATUS_APPROVED,
                storedStatus(request.Id),
                'Statuses other than Deferment Process Complete must not be rewritten.'
            );
        }
    }

    @IsTest
    static void leavesAnAlreadyPendingRequestUntouched() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            Deferment_Request__c request = buildRequest(STATUS_PENDING);

            Test.startTest();
            request.Rejoining_Date__c = Date.today().addMonths(4);
            update request;
            Test.stopTest();

            System.assertEquals(
                STATUS_PENDING,
                storedStatus(request.Id),
                'Editing another field must not disturb Pending Re-enrollment.'
            );
        }
    }

    @IsTest
    static void handlesTwoHundredMixedRecordsInOneUpdate() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            List<Deferment_Request__c> requests =
                new List<Deferment_Request__c>();

            for (Integer i = 0; i < 200; i++) {
                requests.add(new Deferment_Request__c(
                    Status__c = STATUS_APPROVED
                ));
            }

            insert requests;

            for (Integer i = 0; i < 200; i++) {
                requests[i].Status__c = Math.mod(i, 2) == 0
                    ? STATUS_COMPLETE
                    : 'No Dues Process Complete';
            }

            Test.startTest();
            update requests;
            Test.stopTest();

            Integer pending = 0;
            Integer untouched = 0;

            for (Deferment_Request__c stored : [
                SELECT Status__c
                FROM Deferment_Request__c
                WHERE Id IN :requests
            ]) {
                if (stored.Status__c == STATUS_PENDING) {
                    pending++;
                }

                if (stored.Status__c == 'No Dues Process Complete') {
                    untouched++;
                }
            }

            System.assertEquals(
                100,
                pending,
                'Every completed request in the batch should move to Pending Re-enrollment.'
            );

            System.assertEquals(
                100,
                untouched,
                'The other half of the batch should keep its own status.'
            );
        }
    }

    @IsTest
    static void toleratesAnEmptyAndNullList() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            Test.startTest();
            DefermentRequestStatusHandler.applyPendingReEnrollment(null);
            DefermentRequestStatusHandler.applyPendingReEnrollment(
                new List<Deferment_Request__c>()
            );

            System.assertEquals(
                0,
                Limits.getDmlStatements(),
                'The handler must never issue DML of its own.'
            );
            Test.stopTest();
        }
    }
}
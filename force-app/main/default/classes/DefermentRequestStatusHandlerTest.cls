@IsTest
private class DefermentRequestStatusHandlerTest {

    private static final String STATUS_COMPLETE = 'Deferment Process Complete';
    private static final String STATUS_PENDING = 'Pending Re-enrollment';
    private static final String STATUS_APPROVED = 'Rejoining Details Updated';
    private static final String STATUS_DETAILS_DUE = 'Rejoining Details';

    private static Deferment_Request__c buildRequest(String status) {

        Deferment_Request__c request = new Deferment_Request__c(
            Status__c = status
        );
        insert request;

        return request;
    }

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
    static void movesToRejoiningCompleteOnAllRightsReactivated() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Deferment_Request__c request = buildRequest('Payment Confirmed');

            Test.startTest();
            request.Status__c = 'All Rights Reactivated';
            update request;
            Test.stopTest();

            System.assertEquals(
                'Rejoining Complete',
                storedStatus(request.Id),
                'All Rights Reactivated should rewrite to Rejoining Complete.'
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

    @IsTest
    static void rejectNegativeFeeBlocksSave() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Boolean failed = false;
            try {
                insert new Deferment_Request__c(
                    Status__c = STATUS_APPROVED,
                    Deferment_Application_Fee__c = -100
                );
            } catch (DmlException e) {
                failed = true;
                System.assert(
                    e.getMessage().contains('negative') ||
                    e.getMessage().contains('Fee'),
                    e.getMessage()
                );
            }
            System.assert(failed, 'Negative fee must be rejected.');
        }
    }

    @IsTest
    static void enforceStatusOrderBlocksBackwardMove() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Deferment_Request__c request = buildRequest('No Dues Process Initiated');
            Boolean failed = false;
            try {
                request.Status__c = STATUS_APPROVED;
                update request;
            } catch (DmlException e) {
                failed = true;
                System.assert(
                    e.getMessage().contains('cannot be moved back') ||
                    e.getMessage().contains('Completed steps'),
                    e.getMessage()
                );
            }
            System.assert(failed, 'Backward status change must be blocked.');
        }
    }

    @IsTest
    static void enforceStatusOrderBlocksEarlyRejoiningComplete() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Deferment_Request__c request = buildRequest(STATUS_APPROVED);
            Boolean failed = false;
            try {
                request.Status__c = 'Rejoining Complete';
                update request;
            } catch (DmlException e) {
                failed = true;
                System.assert(
                    e.getMessage().contains('Rejoining Complete') ||
                    e.getMessage().contains('fee'),
                    e.getMessage()
                );
            }
            System.assert(failed, 'Jumping to Rejoining Complete before payment must fail.');
        }
    }

    @IsTest
    static void enforceStatusOrderAllowsWithdrawal() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Deferment_Request__c request = buildRequest(STATUS_APPROVED);
            request.Status__c = 'Withdrawal';
            update request;
            System.assertEquals(
                'Withdrawal',
                storedStatus(request.Id),
                'Withdrawal is reachable from any stage, so it must be allowed.'
            );
        }
    }

    @IsTest
    static void nullGuardsDoNotThrow() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            DefermentRequestStatusHandler.rejectNegativeFee(null);
            DefermentRequestStatusHandler.enforceStatusOrder(null, null);
            DefermentRequestStatusHandler.advanceOnRejoiningDetails(null, null);
            DefermentRequestStatusHandler.markStudentDeferredOnPendingReEnrollment(
                null,
                null
            );
            DefermentRequestStatusHandler.markStudentDeferredOnPendingReEnrollment(
                new List<Deferment_Request__c>(),
                null
            );
            DefermentRequestStatusHandler.markEnrollmentActiveOnRejoiningComplete(
                null,
                null
            );
            DefermentRequestStatusHandler.applyRejoiningComplete(null);
            DefermentRequestStatusHandler.applyRejoiningComplete(
                new List<Deferment_Request__c>()
            );
            System.assert(
                true,
                'Null guards must return quietly rather than throwing.'
            );
        }
    }

    @IsTest
    static void completingDefermentMarksPcmAndProgramEnrollment() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            SpjimrPortalTestDataFactory.Ctx ctx =
                SpjimrPortalTestDataFactory.buildAll('defpcm');

            List<ProgramCohortMember> members = [
                SELECT Id, ProgramEnrollmentId
                FROM ProgramCohortMember
                WHERE ProgramCohortId = :ctx.programCohortId
                LIMIT 1
            ];
            if (members.isEmpty() || members[0].ProgramEnrollmentId == null) {
                System.assert(false, 'Test setup needs a Program Cohort Member.');
                return;
            }

            ProgramCohortMember member = members[0];
            update new ProgramEnrollment(
                Id = member.ProgramEnrollmentId,
                Status = 'Enrolled in Batch',
                isDeferred__c = false
            );

            Deferment_Request__c request = new Deferment_Request__c(
                Status__c = STATUS_APPROVED,
                Program_Cohort_Member__c = member.Id
            );
            insert request;

            Test.startTest();
            request.Status__c = STATUS_COMPLETE;
            update request;
            Test.stopTest();

            ProgramCohortMember storedMember = [
                SELECT ProgramEnrollmentStatus
                FROM ProgramCohortMember
                WHERE Id = :member.Id
            ];
            ProgramEnrollment storedEnrollment = [
                SELECT Status, isDeferred__c
                FROM ProgramEnrollment
                WHERE Id = :member.ProgramEnrollmentId
            ];

            System.assertEquals(
                'Pending Re Enrollment',
                storedMember.ProgramEnrollmentStatus,
                'Batch enrolment status should move to Pending Re Enrollment.'
            );
            System.assertEquals(
                'Pending Re Enrollment',
                storedEnrollment.Status,
                'Programme Enrollment status should move to Pending Re Enrollment.'
            );
            System.assertEquals(
                true,
                storedEnrollment.isDeferred__c,
                'Programme Enrollment should be marked deferred.'
            );
        }
    }

    @IsTest
    static void missingBatchEnrollmentDoesNotBlockPendingReEnrollment() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Deferment_Request__c request = buildRequest(STATUS_APPROVED);

            Test.startTest();
            request.Status__c = STATUS_COMPLETE;
            update request;
            Test.stopTest();

            System.assertEquals(
                STATUS_PENDING,
                storedStatus(request.Id),
                'A request without a batch enrolment must still park at Pending Re-enrollment.'
            );
        }
    }

    @IsTest
    static void alreadyPendingDoesNotRestampEnrollment() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            SpjimrPortalTestDataFactory.Ctx ctx =
                SpjimrPortalTestDataFactory.buildAll('defstay');

            List<ProgramCohortMember> members = [
                SELECT Id, ProgramEnrollmentId
                FROM ProgramCohortMember
                WHERE ProgramCohortId = :ctx.programCohortId
                LIMIT 1
            ];
            if (members.isEmpty() || members[0].ProgramEnrollmentId == null) {
                System.assert(false, 'Test setup needs a Program Cohort Member.');
                return;
            }

            ProgramCohortMember member = members[0];

            Deferment_Request__c request = new Deferment_Request__c(
                Status__c = STATUS_PENDING,
                Program_Cohort_Member__c = member.Id
            );
            insert request;

            update new ProgramEnrollment(
                Id = member.ProgramEnrollmentId,
                Status = 'Enrolled in Batch',
                isDeferred__c = false
            );

            Test.startTest();
            request.Rejoining_Date__c = Date.today().addMonths(4);
            update request;
            Test.stopTest();

            ProgramEnrollment storedEnrollment = [
                SELECT Status, isDeferred__c
                FROM ProgramEnrollment
                WHERE Id = :member.ProgramEnrollmentId
            ];
            System.assertEquals(
                false,
                storedEnrollment.isDeferred__c,
                'Editing a request already at Pending Re-enrollment must not restamp enrollment.'
            );
        }
    }

    @IsTest
    static void rejoiningCompleteSetsProgramEnrollmentActiveRejoined() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            SpjimrPortalTestDataFactory.Ctx ctx =
                SpjimrPortalTestDataFactory.buildAll('defrejn');

            List<ProgramCohortMember> members = [
                SELECT Id, ProgramEnrollmentId
                FROM ProgramCohortMember
                WHERE ProgramCohortId = :ctx.programCohortId
                LIMIT 1
            ];
            if (members.isEmpty() || members[0].ProgramEnrollmentId == null) {
                System.assert(false, 'Test setup needs a Program Cohort Member.');
                return;
            }

            ProgramCohortMember member = members[0];
            update new ProgramEnrollment(
                Id = member.ProgramEnrollmentId,
                Status = 'Pending Re Enrollment',
                isDeferred__c = true
            );

            Deferment_Request__c request = new Deferment_Request__c(
                Status__c = 'Payment Confirmed',
                Program_Cohort_Member__c = member.Id
            );
            insert request;

            Test.startTest();
            request.Status__c = 'Rejoining Complete';
            update request;
            Test.stopTest();

            ProgramEnrollment storedEnrollment = [
                SELECT Status, isDeferred__c
                FROM ProgramEnrollment
                WHERE Id = :member.ProgramEnrollmentId
            ];
            ProgramCohortMember storedMember = [
                SELECT ProgramEnrollmentStatus
                FROM ProgramCohortMember
                WHERE Id = :member.Id
            ];
            System.assertEquals(
                'Active - Rejoined',
                storedEnrollment.Status,
                'Programme Enrollment status should be Active - Rejoined.'
            );
            System.assertEquals(
                false,
                storedEnrollment.isDeferred__c,
                'isDeferred should be cleared when rejoining is complete.'
            );
            System.assertEquals(
                'Active - Rejoined',
                storedMember.ProgramEnrollmentStatus,
                'Batch enrolment status should follow Programme Enrollment.'
            );
        }
    }

    private static Map<String, Id> buildRunningBatch() {

        Id programId = SpjimrPortalTestDataFactory.insertProgram();
        Id cohortId = SpjimrPortalTestDataFactory.insertProgramCohort(programId);

        if (cohortId != null) {
            update new ProgramCohort(
                Id = cohortId,
                EndDate = Date.today().addYears(3)
            );
        }

        return new Map<String, Id>{
            'programme' => programId,
            'batch' => cohortId
        };
    }

    @IsTest
    static void advancesOnceEveryRejoiningDetailIsFilled() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            Map<String, Id> batch = buildRunningBatch();

            Deferment_Request__c request = new Deferment_Request__c(
                Status__c = STATUS_DETAILS_DUE,
                Programme__c = batch.get('programme')
            );
            insert request;

            Test.startTest();
            request.Rejoining_Date__c = Date.today().addDays(60);
            request.Rejoining_Fee_Deadline__c = Date.today().addDays(45);
            request.Rejoining_Batch__c = batch.get('batch');
            update request;
            Test.stopTest();

            System.assertEquals(
                STATUS_APPROVED,
                storedStatus(request.Id),
                'Filling every rejoining detail should move the tracker on.'
            );
        }
    }

    @IsTest
    static void staysPutWhileARejoiningDetailIsMissing() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            Deferment_Request__c request = buildRequest(STATUS_DETAILS_DUE);

            Test.startTest();
            request.Rejoining_Date__c = Date.today().addDays(60);
            request.Rejoining_Fee_Deadline__c = Date.today().addDays(45);
            update request;
            Test.stopTest();

            System.assertEquals(
                STATUS_DETAILS_DUE,
                storedStatus(request.Id),
                'A request with no Rejoining Batch is not finished, so it must wait.'
            );
        }
    }

    @IsTest
    static void clearingADetailLaterDoesNotDragTheTrackerBack() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            Deferment_Request__c request = buildRequest(STATUS_APPROVED);

            Test.startTest();
            request.Rejoining_Fee_Deadline__c = null;
            update request;
            Test.stopTest();

            System.assertEquals(
                STATUS_APPROVED,
                storedStatus(request.Id),
                'A request past this stage must not be pulled back by a cleared field.'
            );
        }
    }
}
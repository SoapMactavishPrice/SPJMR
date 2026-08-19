@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class LeaveApproverResolverTest {

    private static final String ROLE_PO = 'Programme Office';
    private static final String ROLE_MANAGER = 'Manager';

    private static Id seedProgramId;
    private static Integer programmeCounter = 0;
    private static Account learner;

    /**
     * @description Two active standard users to act as approvers of two different programmes.
     * @return Two User records.
     */
    private static List<User> approverUsers() {
        return [
            SELECT Id
            FROM User
            WHERE IsActive = TRUE AND UserType = 'Standard'
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];
    }

    /**
     * @description One reusable learner person account. Only one is ever created: two factory
     * learners in the same test trip the org's duplicate-student check.
     * @return The learner Account.
     */
    private static Account learnerAccount() {
        if (learner == null) {
            learner = SpjimrPortalTestDataFactory.buildLearnerPersonAccount('lar');
        }
        return learner;
    }

    /**
     * @description Creates a distinct programme. Programmes are cloned from one factory-built
     * seed: the factory swallows insert errors and returns null, and a validation rule rejects a
     * duplicate Programme Code, so the clone needs a fresh code as well as a fresh name.
     * @param programName Name for the new programme.
     * @return Id of the created Program.
     */
    private static Id newProgramme(String programName) {
        programmeCounter++;
        if (seedProgramId == null) {
            seedProgramId = SpjimrPortalTestDataFactory.insertProgram();
            System.assertNotEquals(null, seedProgramId, 'Seed programme could not be created.');
            update new Program(Id = seedProgramId, Name = programName);
            return seedProgramId;
        }

        List<String> fieldNames = new List<String>();
        for (Schema.SObjectField f :
                Program.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = f.getDescribe();
            if (dfr.isCreateable()) {
                fieldNames.add(dfr.getName());
            }
        }
        Id seedId = seedProgramId;
        Program seed = Database.query(
            'SELECT ' + String.join(fieldNames, ',') + ' FROM Program WHERE Id = :seedId LIMIT 1'
        );

        Program copy = seed.clone(false, true, false, false);
        copy.Name = programName;
        copy.Program_Code__c = 'TPR' + programmeCounter;
        // Short Programme Code is capped at 3 characters in this org.
        copy.Short_Programme_Code__c = 'T' + programmeCounter;
        insert copy;
        return copy.Id;
    }

    /**
     * @description Enrols the learner into a programme and returns the batch enrollment, which is
     * what a leave application points at and what the resolver derives the programme from.
     * @param programId Programme to enrol into.
     * @return ProgramCohortMember Id.
     */
    private static Id newBatchEnrollment(Id programId) {
        Id cohortId = SpjimrPortalTestDataFactory.insertProgramCohort(programId);
        System.assertNotEquals(null, cohortId, 'Cohort could not be created.');
        Id enrollmentId = SpjimrPortalTestDataFactory.insertProgramEnrollment(learnerAccount().Id, programId);
        SpjimrPortalTestDataFactory.insertProgramCohortMember(cohortId, enrollmentId);

        List<ProgramCohortMember> members = [
            SELECT Id FROM ProgramCohortMember WHERE ProgramCohortId = :cohortId LIMIT 1
        ];
        System.assertEquals(1, members.size(), 'Batch enrollment could not be created.');
        return members[0].Id;
    }

    private static Program_Team__c newTeam(Id programId, String teamName) {
        Program_Team__c team = new Program_Team__c(Name = teamName, Program__c = programId);
        insert team;
        return team;
    }

    private static void addMember(Id teamId, String role, Id userId) {
        insert new Program_Team_Members__c(
            Program_Team__c = teamId,
            Role__c = role,
            User__c = userId
        );
    }

    private static Leave_Application__c newLeave(Id batchEnrollmentId) {
        return new Leave_Application__c(
            Batch_Enrollment__c = batchEnrollmentId,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addDays(1),
            Leave_Type__c = 'Medical Leave'
        );
    }

    // ================= APPROVER SCOPING =================

    @IsTest
    static void getApproversReturnsOnlyOwnProgrammeApprovers() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<User> users = approverUsers();
            Id programmeA = newProgramme('Programme A');
            Id programmeB = newProgramme('Programme B');
            addMember(newTeam(programmeA, 'Team A').Id, ROLE_PO, users[0].Id);
            addMember(newTeam(programmeB, 'Team B').Id, ROLE_PO, users[1].Id);

            Test.startTest();
            List<Id> forA = LeaveApproverResolver.getApprovers(programmeA, ROLE_PO);
            List<Id> forB = LeaveApproverResolver.getApprovers(programmeB, ROLE_PO);
            Test.stopTest();

            System.assertEquals(1, forA.size(), 'Programme A should resolve exactly its own approver.');
            System.assertEquals(users[0].Id, forA[0], 'Programme A must get user A, not the org-wide list.');
            System.assertEquals(1, forB.size(), 'Programme B should resolve exactly its own approver.');
            System.assertEquals(users[1].Id, forB[0], 'Programme B must get user B.');
        }
    }

    @IsTest
    static void getApproversIgnoresOtherRolesInSameProgramme() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<User> users = approverUsers();
            Id programId = newProgramme('Single Programme');
            Program_Team__c team = newTeam(programId, 'One Team');
            addMember(team.Id, ROLE_PO, users[0].Id);
            addMember(team.Id, ROLE_MANAGER, users[1].Id);

            Test.startTest();
            List<Id> managers = LeaveApproverResolver.getApprovers(programId, ROLE_MANAGER);
            Test.stopTest();

            System.assertEquals(1, managers.size(), 'Only the Manager row should match.');
            System.assertEquals(users[1].Id, managers[0], 'The Manager user should be returned.');
        }
    }

    @IsTest
    static void getApproversDeDupesAcrossTeamsOfSameProgramme() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<User> users = approverUsers();
            Id programId = newProgramme('Two Team Programme');
            addMember(newTeam(programId, 'Team One').Id, ROLE_PO, users[0].Id);
            addMember(newTeam(programId, 'Team Two').Id, ROLE_PO, users[0].Id);

            Test.startTest();
            List<Id> approvers = LeaveApproverResolver.getApprovers(programId, ROLE_PO);
            Test.stopTest();

            System.assertEquals(1, approvers.size(),
                'A user on two teams of the same programme should appear once.');
        }
    }

    @IsTest
    static void getApproversReturnsEmptyForNullProgramme() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            List<Id> approvers = LeaveApproverResolver.getApprovers(null, ROLE_PO);
            Test.stopTest();

            System.assertEquals(0, approvers.size(),
                'A leave with no derivable programme must not fall back to the org-wide list.');
        }
    }

    @IsTest
    static void getApproversByProgramResolvesSeveralProgrammesAtOnce() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<User> users = approverUsers();
            Id programmeA = newProgramme('Bulk A');
            Id programmeB = newProgramme('Bulk B');
            addMember(newTeam(programmeA, 'Bulk Team A').Id, ROLE_MANAGER, users[0].Id);
            addMember(newTeam(programmeB, 'Bulk Team B').Id, ROLE_MANAGER, users[1].Id);

            Test.startTest();
            Map<Id, List<Id>> byProgram = LeaveApproverResolver.getApproversByProgram(
                new Set<Id>{ programmeA, programmeB },
                ROLE_MANAGER
            );
            Test.stopTest();

            System.assertEquals(2, byProgram.size(), 'Both programmes should be resolved in one call.');
            System.assertEquals(users[0].Id, byProgram.get(programmeA)[0], 'Programme A manager mismatch.');
            System.assertEquals(users[1].Id, byProgram.get(programmeB)[0], 'Programme B manager mismatch.');
        }
    }

    // ================= PROGRAMME DERIVATION =================

    @IsTest
    static void resolveProgramIdDerivesFromBatchEnrollment() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id programId = newProgramme('Derived Programme');
            Id batchEnrollmentId = newBatchEnrollment(programId);

            Test.startTest();
            Id resolved = LeaveApproverResolver.resolveProgramId(newLeave(batchEnrollmentId));
            Test.stopTest();

            System.assertEquals(programId, resolved,
                'Programme should be derived from the batch enrollment cohort.');
        }
    }

    @IsTest
    static void resolveProgramIdFallsBackToTermEnrollment() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id programId = newProgramme('Term Fallback Programme');
            Id termId = SpjimrPortalTestDataFactory.insertAcademicTerm();
            System.assertNotEquals(null, termId, 'Academic term could not be created.');
            update new AcademicTerm(Id = termId, Program_Name__c = programId);
            Id termEnrollmentId =
                SpjimrPortalTestDataFactory.insertAcademicTermEnrollment(learnerAccount().Id, termId);
            System.assertNotEquals(null, termEnrollmentId, 'Term enrollment could not be created.');

            Leave_Application__c leave = newLeave(null);
            leave.Term_Enrollment__c = termEnrollmentId;

            Test.startTest();
            Id resolved = LeaveApproverResolver.resolveProgramId(leave);
            Test.stopTest();

            System.assertEquals(programId, resolved,
                'With no batch enrollment the academic term should supply the programme.');
        }
    }

    @IsTest
    static void resolveProgramIdReturnsNullWhenUnderivable() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Id resolved = LeaveApproverResolver.resolveProgramId(newLeave(null));
            Test.stopTest();

            System.assertEquals(null, resolved,
                'A leave with no enrollment links has no derivable programme.');
        }
    }

    @IsTest
    static void resolveProgramIdsHandlesEmptyAndNullInput() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            List<Id> fromNull = LeaveApproverResolver.resolveProgramIds(null);
            List<Id> fromEmpty = LeaveApproverResolver.resolveProgramIds(new List<Leave_Application__c>());
            Test.stopTest();

            System.assertEquals(0, fromNull.size(), 'Null input should yield no programmes.');
            System.assertEquals(0, fromEmpty.size(), 'Empty input should yield no programmes.');
        }
    }

    // ================= END-TO-END ROUTING =================

    @IsTest
    static void insertRoutesFirstApproverToOwnProgrammeOnly() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<User> users = approverUsers();
            Id programmeA = newProgramme('Routing A');
            Id programmeB = newProgramme('Routing B');
            addMember(newTeam(programmeA, 'Routing Team A').Id, ROLE_PO, users[0].Id);
            addMember(newTeam(programmeB, 'Routing Team B').Id, ROLE_PO, users[1].Id);
            Id batchEnrollmentId = newBatchEnrollment(programmeA);

            Leave_Application__c leave = newLeave(batchEnrollmentId);

            Test.startTest();
            insert leave;
            Test.stopTest();

            Leave_Application__c saved = [
                SELECT Current_Approver_User__c, Current_Role_Name__c
                FROM Leave_Application__c
                WHERE Id = :leave.Id
            ];
            System.assertEquals(users[0].Id, saved.Current_Approver_User__c,
                'The first approver must come from the leave programme, not another programme.');
            System.assertEquals(ROLE_PO, saved.Current_Role_Name__c,
                'A new leave should start at Programme Office.');
        }
    }

    @IsTest
    static void submitJobRoutesToOwnProgrammeApproversOnly() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<User> users = approverUsers();
            Id programmeA = newProgramme('Submit A');
            Id programmeB = newProgramme('Submit B');
            addMember(newTeam(programmeA, 'Submit Team A').Id, ROLE_PO, users[0].Id);
            addMember(newTeam(programmeB, 'Submit Team B').Id, ROLE_PO, users[1].Id);
            Id batchEnrollmentId = newBatchEnrollment(programmeA);

            Leave_Application__c leave = newLeave(batchEnrollmentId);
            insert leave;

            Test.startTest();
            new LeaveSubmissionController.SubmitLeaveJob(leave.Id).execute(null);
            Test.stopTest();

            Leave_Application__c saved = [
                SELECT Current_Approver_Ids__c FROM Leave_Application__c WHERE Id = :leave.Id
            ];
            System.assert(saved.Current_Approver_Ids__c.contains(String.valueOf(users[0].Id)),
                'The programme own approver should be in the approver list.');
            System.assert(!saved.Current_Approver_Ids__c.contains(String.valueOf(users[1].Id)),
                'Another programme approver must NOT be in the approver list.');
        }
    }

    @IsTest
    static void submitJobRecordsErrorWhenProgrammeHasNoApprover() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id programId = newProgramme('Unmapped Programme');
            Id batchEnrollmentId = newBatchEnrollment(programId);

            Leave_Application__c leave = newLeave(batchEnrollmentId);
            insert leave;

            Test.startTest();
            new LeaveSubmissionController.SubmitLeaveJob(leave.Id).execute(null);
            Test.stopTest();

            System.assert(LeaveSubmissionController.lastSubmitError != null
                && LeaveSubmissionController.lastSubmitError.contains('No Programme Office approver'),
                'An unmapped programme should be recorded rather than routed org-wide.');
        }
    }
}
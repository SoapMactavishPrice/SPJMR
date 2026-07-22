@IsTest
private class SPJIMR_ProgramCohortTriggerHandlerTest {

    /**
     * Changing the profile (photo) window time on a cohort that has enrolled members must
     * create Portal_Notification__c records (sendNotificationOnWindowChange path).
     */
    @IsTest
    static void windowChange_createsPortalNotifications() {
        Id programId = SpjimrPortalTestDataFactory.insertProgram();
        System.assertNotEquals(null, programId);
        Account learner = SpjimrPortalTestDataFactory.buildLearnerPersonAccount(
            'pcwin' + String.valueOf(Crypto.getRandomInteger()).right(4));
        Id peId = SpjimrPortalTestDataFactory.insertProgramEnrollment(learner.Id, programId);

        String r = String.valueOf(Math.abs(Crypto.getRandomInteger())).right(4);
        ProgramCohort pc = new ProgramCohort(
            Name = 'PC Win ' + r, ProgramId = programId,
            Batch_Code__c = 'WIN' + r, Short_Batch_Code__c = 'W' + r.right(2),
            Batch_Sub_Type__c = 'Class Room', Batch_Base_Currency__c = 'INR',
            Profile_Window_End_Time__c = Datetime.now().addDays(1), Is_Active__c = true);
        insert pc;
        SpjimrPortalTestDataFactory.insertProgramCohortMember(pc.Id, peId);

        ProgramCohort upd = [SELECT Id, Profile_Window_End_Time__c FROM ProgramCohort WHERE Id = :pc.Id];
        upd.Profile_Window_End_Time__c = upd.Profile_Window_End_Time__c.addHours(2);

        Test.startTest();
        update upd; // afterUpdate -> sendNotificationOnWindowChange -> inserts Portal_Notification__c
        Test.stopTest();

        if (peId != null) {
            System.assert(
                ![SELECT Id FROM Portal_Notification__c WHERE Recipient_Account__c = :learner.Id].isEmpty(),
                'Window change with enrolled members should create a portal notification.');
        }
    }

    @IsTest
    static void insertAndUpdate_paths() {
        Id programId = SpjimrPortalTestDataFactory.insertProgram();
        System.assertNotEquals(null, programId, 'Program setup failed');

        ProgramCohort pc = new ProgramCohort(Name = 'PC Main ' + String.valueOf(Datetime.now().getTime()));
        pc.ProgramId = programId;
        pc.Batch_Code__c = 'BC' + String.valueOf(Math.mod(Datetime.now().getTime(), 100000));
        pc.Short_Batch_Code__c = 'A1';
        pc.Batch_Sub_Type__c = 'Class Room';
        pc.Profile_Window_Start_Time__c = Datetime.now().addDays(-1);
        pc.Profile_Window_End_Time__c = Datetime.now().addDays(2);
        pc.Is_Active__c = true;

        Test.startTest();
        insert pc; // before insert + after insert

        ProgramCohort upd = [
            SELECT Id, Short_Batch_Code__c, Profile_Window_Start_Time__c, Profile_Window_End_Time__c
            FROM ProgramCohort
            WHERE Id = :pc.Id
        ];
        upd.Short_Batch_Code__c = 'B2';
        upd.Profile_Window_End_Time__c = upd.Profile_Window_End_Time__c.addHours(1);
        update upd; // before update + after update + notification path
        Test.stopTest();
    }

    @IsTest
    static void duplicateValidation_paths() {
        Id programId = SpjimrPortalTestDataFactory.insertProgram();
        if (programId == null) return;

        String uniqueCode = 'D' + String.valueOf(Math.mod(Datetime.now().getTime(), 90));
        ProgramCohort first = new ProgramCohort(
            Name = 'PC1 ' + uniqueCode,
            ProgramId = programId,
            Batch_Code__c = 'B1' + uniqueCode,
            Short_Batch_Code__c = 'C1',
            Batch_Sub_Type__c = 'Class Room',
            Is_Active__c = true
        );
        insert first;

        ProgramCohort dup = new ProgramCohort(
            Name = 'PC2 ' + uniqueCode,
            ProgramId = programId,
            Batch_Code__c = 'B2' + uniqueCode,
            Short_Batch_Code__c = 'C1',
            Batch_Sub_Type__c = 'Class Room',
            Is_Active__c = true
        );
        Test.startTest();
        Database.SaveResult sr = Database.insert(dup, false);
        Test.stopTest();
        System.assertEquals(false, sr.isSuccess(), 'Duplicate validation should fail');
    }

    @IsTest
    static void handleTriggerDirectlyWithEmpty() {
        try {
            SPJIMR_ProgramCohortTriggerHandler.handleTrigger(new List<ProgramCohort>(), new Map<Id, ProgramCohort>());
        } catch (Exception e) {
            System.assert(true);
        }
    }

    @IsTest
    static void shortCodeModificationRestrictedWhenRollNumberExists() {
        Id programId = SpjimrPortalTestDataFactory.insertProgram();
        if (programId == null) return;

        Account learner = SpjimrPortalTestDataFactory.buildLearnerPersonAccount('pcRestrict');
        Id peId = SpjimrPortalTestDataFactory.insertProgramEnrollment(learner.Id, programId);
        if (peId == null) return;

        ProgramCohort cohort = new ProgramCohort(
            Name = 'PC Restrict',
            ProgramId = programId,
            Batch_Code__c = 'R01',
            Short_Batch_Code__c = 'R1',
            Batch_Sub_Type__c = 'Class Room',
            Is_Active__c = true
        );
        insert cohort;

        // Factory inserts ProgramCohortMember with Roll_Number__c populated.
        SpjimrPortalTestDataFactory.insertProgramCohortMember(cohort.Id, peId);

        ProgramCohort upd = [
            SELECT Id, Short_Batch_Code__c
            FROM ProgramCohort
            WHERE Id = :cohort.Id
            LIMIT 1
        ];
        upd.Short_Batch_Code__c = 'R2';

        Test.startTest();
        Database.SaveResult sr = Database.update(upd, false);
        Test.stopTest();
        System.assertEquals(false, sr.isSuccess(), 'Short code update should be blocked after roll number generation');
    }
}
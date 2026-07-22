@IsTest
private class ProgramTriggerHandlerTest {

    @IsTest
    static void preventDuplicate_emptyAndBlankAndUnique() {
        ProgramTriggerHandler.preventDuplicateShortProgrammeCode(
            new List<Program>(), new Map<Id, Program>());

        Program blank = new Program();
        ProgramTriggerHandler.preventDuplicateShortProgrammeCode(
            new List<Program>{ blank }, new Map<Id, Program>());
        System.assert(!blank.hasErrors(), 'Blank codes are skipped.');

        Program uniq = new Program(
            Short_Programme_Code__c = 'ZZUNIQ' + Crypto.getRandomInteger(),
            Program_Code__c = 'ZZPROG' + Crypto.getRandomInteger());
        ProgramTriggerHandler.preventDuplicateShortProgrammeCode(new List<Program>{ uniq }, null);
        System.assert(!uniq.hasErrors(), 'Unique codes do not error.');
    }

    @IsTest
    static void preventDuplicate_collisionAddsError() {
        Id progId = SpjimrPortalTestDataFactory.insertProgram();
        System.assertNotEquals(null, progId, 'Need a saved Program to collide against.');
        Program saved = [SELECT Short_Programme_Code__c, Program_Code__c FROM Program WHERE Id = :progId];

        Program dup = new Program(
            Short_Programme_Code__c = saved.Short_Programme_Code__c,
            Program_Code__c = saved.Program_Code__c);

        Test.startTest();
        ProgramTriggerHandler.preventDuplicateShortProgrammeCode(new List<Program>{ dup }, null);
        Test.stopTest();

        System.assert(dup.hasErrors(), 'Duplicate short/programme codes must error.');
    }

    @IsTest
    static void validateShortCodeModification_blockedAfterEnrollment() {
        Id progId = SpjimrPortalTestDataFactory.insertProgram();
        Id cohortId = SpjimrPortalTestDataFactory.insertProgramCohort(progId);
        Account biz = new Account(Name = 'PE Owner');
        insert biz;
        Id peId = SpjimrPortalTestDataFactory.insertProgramEnrollment(biz.Id, progId);
        SpjimrPortalTestDataFactory.insertProgramCohortMember(cohortId, peId); // sets Roll_Number__c

        Program orig = [SELECT Id, Short_Programme_Code__c FROM Program WHERE Id = :progId];
        Program changed = new Program(Id = progId, Short_Programme_Code__c = 'CHANGED');
        Map<Id, Program> oldMap = new Map<Id, Program>{ progId => orig };

        Test.startTest();
        // oldMap null -> no-op (insert context)
        ProgramTriggerHandler.validateShortProgrammeCodeModification(new List<Program>{ changed }, null);
        // unchanged -> no-op
        ProgramTriggerHandler.validateShortProgrammeCodeModification(
            new List<Program>{ new Program(Id = progId, Short_Programme_Code__c = orig.Short_Programme_Code__c) },
            oldMap);
        // changed with enrolled members -> blocked
        ProgramTriggerHandler.validateShortProgrammeCodeModification(new List<Program>{ changed }, oldMap);
        Test.stopTest();

        System.assert(changed.hasErrors(),
            'Short code change should be blocked once cohort members with roll numbers exist.');
    }
}
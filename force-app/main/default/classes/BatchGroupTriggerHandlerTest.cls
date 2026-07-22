@IsTest
private class BatchGroupTriggerHandlerTest {

    // The handler methods operate on in-memory AcademicYear (Batch Group) records, so they can
    // be covered without inserting AcademicYear rows (which carry org-specific date validations).

    @IsTest
    static void handleBeforeInsert_assignsSequenceAndCode() {
        Id progId = SpjimrPortalTestDataFactory.insertProgram();
        Id cohortId = SpjimrPortalTestDataFactory.insertProgramCohort(progId);
        System.assertNotEquals(null, cohortId, 'Need a ProgramCohort (Batch) to drive the handler.');

        // Best-effort: an existing committed Batch Group lets the MAX(sequence) aggregate
        // branch run on the next call. Tolerated if org validations block the insert.
        try {
            insert new AcademicYear(
                Name = 'BG Existing', Batch__c = cohortId,
                Batch_Group_Sub_Type__c = 'Class Room', Batch_Group_Base_Currency__c = 'INR');
        } catch (Exception e) { System.debug('AcademicYear insert skipped: ' + e.getMessage()); }

        AcademicYear bg1 = new AcademicYear(Name = 'BG One', Batch__c = cohortId);
        AcademicYear bg2 = new AcademicYear(Name = 'BG Two', Batch__c = cohortId);
        AcademicYear noBatch = new AcademicYear(Name = 'No Batch');

        Test.startTest();
        new BatchGroupTriggerHandler();
        BatchGroupTriggerHandler.handleBeforeInsert(new List<AcademicYear>{ bg1, bg2, noBatch });
        BatchGroupTriggerHandler.handleBeforeInsert(new List<AcademicYear>()); // empty path
        BatchGroupTriggerHandler.handleBeforeInsert(
            new List<AcademicYear>{ new AcademicYear(Name = 'x') }); // batchIds empty -> early return
        Test.stopTest();

        System.assertNotEquals(null, bg1.Batch_Group_Number__c, 'A sequence number is assigned.');
        System.assertEquals(bg1.Batch_Group_Number__c + 1, bg2.Batch_Group_Number__c,
            'Second in same batch is one higher than the first.');
        System.assertNotEquals(null, bg1.Batch_Group_Code__c, 'Code is composed from series + number.');
    }

    @IsTest
    static void validateUniqueNames_inMemoryDuplicate() {
        Id progId = SpjimrPortalTestDataFactory.insertProgram();
        Id cohortId = SpjimrPortalTestDataFactory.insertProgramCohort(progId);

        AcademicYear a = new AcademicYear(Name = 'Dup', Batch__c = cohortId);
        AcademicYear b = new AcademicYear(Name = 'Dup', Batch__c = cohortId); // same key in one txn
        AcademicYear blank = new AcademicYear(Batch__c = cohortId); // blank name -> skipped

        Test.startTest();
        BatchGroupTriggerHandler.validateUniqueNames(new List<AcademicYear>{ a, b, blank }, null);
        BatchGroupTriggerHandler.validateUniqueNames(new List<AcademicYear>(), null);
        Test.stopTest();

        System.assert(b.hasErrors(), 'The second same-named Batch Group in the txn should error.');
    }

    @IsTest
    static void setBatchGroupCurrency_copiesFromProgram() {
        Id progId = SpjimrPortalTestDataFactory.insertProgram();
        System.assertNotEquals(null, progId);

        AcademicYear bg = new AcademicYear(Name = 'Cur', Program_Master__c = progId);
        AcademicYear noProg = new AcademicYear(Name = 'NoProg');

        Test.startTest();
        BatchGroupTriggerHandler.setBatchGroupCurrency(new List<AcademicYear>{ bg, noProg });
        BatchGroupTriggerHandler.setBatchGroupCurrency(new List<AcademicYear>()); // empty -> early return
        Test.stopTest();

        // Program was created with Programme_Base_Currency__c = 'INR' by the factory.
        System.assertEquals('INR', bg.Batch_Group_Base_Currency__c,
            'Currency should be copied from the related Program.');
    }
}
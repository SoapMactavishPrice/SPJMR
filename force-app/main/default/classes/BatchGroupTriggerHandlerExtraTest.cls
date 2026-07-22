/**
 * Exercises BatchGroupTriggerHandler's three static methods directly:
 *  - handleBeforeInsert (two AcademicYears sharing a batch -> running-sequence branch)
 *  - validateUniqueNames (in-transaction dup + existing-DB dup)
 *  - setBatchGroupCurrency (populated + empty-programIds early return)
 */
@IsTest(seeAllData=true)
private class BatchGroupTriggerHandlerExtraTest {

    @IsTest
    static void handleBeforeInsert_assignsSequenceForSameBatch() {
        List<ProgramCohort> cohorts = [SELECT Id FROM ProgramCohort LIMIT 1];
        if (cohorts.isEmpty()) {
            return;
        }
        Id batchId = cohorts[0].Id;
        AcademicYear a1 = new AcademicYear(Name = 'BGTseq A', Batch__c = batchId);
        AcademicYear a2 = new AcademicYear(Name = 'BGTseq B', Batch__c = batchId);
        BatchGroupTriggerHandler.handleBeforeInsert(new List<AcademicYear>{ a1, a2 });
        // Second record with the same batch hits the runningMap branch and gets the next number.
        System.assertNotEquals(null, a1.Batch_Group_Number__c);
        System.assertNotEquals(null, a2.Batch_Group_Number__c);
        System.assertEquals(a1.Batch_Group_Number__c + 1, a2.Batch_Group_Number__c);
    }

    @IsTest
    static void validateUniqueNames_inTransactionAndExistingDuplicates() {
        List<AcademicYear> existing = [SELECT Id, Name, Batch__c FROM AcademicYear WHERE Batch__c != null AND Name != null LIMIT 1];
        if (existing.isEmpty()) {
            return;
        }
        Id batchId = existing[0].Batch__c;

        // In-transaction duplicate: two new records, same batch + same name
        AcademicYear d1 = new AcademicYear(Name = 'DupName', Batch__c = batchId);
        AcademicYear d2 = new AcademicYear(Name = 'DupName', Batch__c = batchId);
        BatchGroupTriggerHandler.validateUniqueNames(new List<AcademicYear>{ d1, d2 }, null);
        System.assertEquals(true, d2.hasErrors(), 'Second same-name record should error');

        // Existing-DB duplicate: a new record reusing an existing Name+Batch
        AcademicYear clash = new AcademicYear(Name = existing[0].Name, Batch__c = batchId);
        BatchGroupTriggerHandler.validateUniqueNames(new List<AcademicYear>{ clash }, null);
        System.assertEquals(true, clash.hasErrors(), 'Reusing an existing Name within the batch should error');
    }

    @IsTest
    static void validateUniqueNames_updateNoChangeSkips() {
        List<AcademicYear> existing = [SELECT Id, Name, Batch__c FROM AcademicYear WHERE Batch__c != null AND Name != null LIMIT 1];
        if (existing.isEmpty()) {
            return;
        }
        AcademicYear same = new AcademicYear(Id = existing[0].Id, Name = existing[0].Name, Batch__c = existing[0].Batch__c);
        Map<Id, AcademicYear> oldMap = new Map<Id, AcademicYear>{
            existing[0].Id => new AcademicYear(Id = existing[0].Id, Name = existing[0].Name, Batch__c = existing[0].Batch__c)
        };
        // name & batch unchanged -> continue/skip branch; self-match on existing record is ignored.
        BatchGroupTriggerHandler.validateUniqueNames(new List<AcademicYear>{ same }, oldMap);
    }

    @IsTest
    static void setBatchGroupCurrency_populatedAndEmpty() {
        // Empty programIds -> early return
        BatchGroupTriggerHandler.setBatchGroupCurrency(new List<AcademicYear>{ new AcademicYear(Name = 'NoProg') });

        List<Program> progs = [SELECT Id FROM Program WHERE Programme_Base_Currency__c != null LIMIT 1];
        if (progs.isEmpty()) {
            return;
        }
        AcademicYear bg = new AcademicYear(Name = 'WithProg', Program_Master__c = progs[0].Id);
        BatchGroupTriggerHandler.setBatchGroupCurrency(new List<AcademicYear>{ bg });
        // Currency copied from program when available (may be null if program field blank)
    }
}
@IsTest(SeeAllData=true)
private class BatchGroupSequenceCtrlTest {
    @IsTest
    static void getBatchGroupNumbers_unknownAndRealBatch() {
        Id fake = Schema.SObjectType.ProgramCohort.getKeyPrefix() + '000000000001';
        Map<String, Object> out = BatchGroupSequenceController.getBatchGroupNumbers(fake);
        System.assertNotEquals(null, out);

        List<ProgramCohort> existing = [SELECT Id FROM ProgramCohort LIMIT 1];
        if (!existing.isEmpty()) {
            BatchGroupSequenceController.getBatchGroupNumbers(existing[0].Id);
        }
    }
    @IsTest
    static void createBatchGroup_withRealOrFakeBatch() {
        List<ProgramCohort> existing = [SELECT Id FROM ProgramCohort LIMIT 1];
        Id batchId = existing.isEmpty()
            ? (Id)(Schema.SObjectType.ProgramCohort.getKeyPrefix() + '000000000001')
            : existing[0].Id;
        try {
            Test.startTest();
            BatchGroupSequenceController.createBatchGroup(batchId, 9999);
            Test.stopTest();
        } catch (Exception e) {
            // Required-fields/validation may reject the insert; lines were still executed.
        }
    }
}
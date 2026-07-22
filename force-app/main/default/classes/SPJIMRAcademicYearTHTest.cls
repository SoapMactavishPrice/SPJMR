@IsTest(SeeAllData=true)
private class SPJIMRAcademicYearTHTest {
    @IsTest
    static void syncProgramCodeFromProgram_emptyAndDirect() {
        SPJIMR_AcademicYearTriggerHandler.syncProgramCodeFromProgram(
            new List<AcademicYear>(), new Map<Id, AcademicYear>()
        );
    }
    @IsTest
    static void updateAcademicYearsAcrossManyRecords_firesAfterUpdatePath() {
        // Larger batch + records that have related AcademicTerms (so term-query branch is exercised
        // when at least one record's update succeeds).
        List<AggregateResult> withTerms = [
            SELECT AcademicYearId bg FROM AcademicTerm WHERE AcademicYearId != null
            GROUP BY AcademicYearId LIMIT 5
        ];
        Set<Id> bgIds = new Set<Id>();
        for (AggregateResult ar : withTerms) bgIds.add((Id) ar.get('bg'));
        List<AcademicYear> targeted = bgIds.isEmpty()
            ? new List<AcademicYear>()
            : [SELECT Id, Batch_Group_Code__c FROM AcademicYear WHERE Id IN :bgIds];

        List<AcademicYear> generic = [
            SELECT Id, Batch_Group_Code__c FROM AcademicYear
            WHERE Batch_Group_Code__c != null AND Id NOT IN :bgIds
            LIMIT 20
        ];
        List<AcademicYear> all = new List<AcademicYear>();
        all.addAll(targeted);
        all.addAll(generic);
        if (all.isEmpty()) return;
        for (AcademicYear ay : all) {
            ay.Batch_Group_Code__c = (ay.Batch_Group_Code__c == null ? 'Z' : ay.Batch_Group_Code__c) + 'Z';
        }
        Test.startTest();
        Database.update(all, false);
        Test.stopTest();
    }
}
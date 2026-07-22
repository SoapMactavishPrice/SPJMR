@IsTest(SeeAllData=true)
private class BatchGroupDeleteHandlerTest {
    @IsTest
    static void emptyListIsHandled() {
        BatchGroupDeleteHandler.preventDeleteIfTermsExist(new List<AcademicYear>());
    }
    @IsTest
    static void existingBatchGroupWithTerms_isBlocked() {
        // Find a real AcademicYear that has at least one AcademicTerm so the addError path runs.
        List<AggregateResult> ar = [
            SELECT AcademicYearId bg
            FROM AcademicTerm
            WHERE AcademicYearId != null
            GROUP BY AcademicYearId
            LIMIT 1
        ];
        if (ar.isEmpty()) return; // no test data available
        Id bgId = (Id) ar[0].get('bg');
        AcademicYear ay = [SELECT Id FROM AcademicYear WHERE Id = :bgId LIMIT 1];

        BatchGroupDeleteHandler.preventDeleteIfTermsExist(new List<AcademicYear>{ ay });
        System.assert(ay.hasErrors(), 'Expected addError to be applied');
    }
}
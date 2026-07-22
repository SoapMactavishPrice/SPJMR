@IsTest
private class SPJIMRDivisionCodeHandlerTest {
    @IsTest
    static void allMethodsEarlyReturnOnEmpty() {
        SPJIMRDivisionCodeHandler.updateDivisionCodes(new List<Division__c>());
        SPJIMRDivisionCodeHandler.updateDivisionCodesForTerms(new List<AcademicTerm>());
        SPJIMRDivisionCodeHandler.updateDivisionCodesForAcademicYears(new List<AcademicYear>());
        SPJIMRDivisionCodeHandler.updateDivisionCodesForBatches(new List<ProgramCohort>());
    }
}
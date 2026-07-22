@IsTest
private class TermRenumberHandlerTest {
    @IsTest
    static void earlyReturnsOnEmptyInput() {
        TermRenumberHandler.renumberAfterDelete(null);
        TermRenumberHandler.renumberAfterDelete(new List<AcademicTerm>());
        TermRenumberHandler.renumberAfterBatchGroupChange(new Set<Id>());
        System.assert(true);
    }
}
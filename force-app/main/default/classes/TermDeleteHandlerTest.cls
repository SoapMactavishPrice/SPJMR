@IsTest
private class TermDeleteHandlerTest {
    @IsTest
    static void emptyListEarlyReturns() {
        TermDeleteHandler.preventDeleteIfEnrollmentsExist(new List<AcademicTerm>());
        System.assert(true);
    }
}
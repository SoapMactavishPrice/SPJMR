@IsTest
private class ProgramPicklistUpdaterTest {
    @IsTest
    static void emptyAndBlankNamesEarlyReturn() {
        ProgramPicklistUpdater.updatePicklist(new List<Program>());
        ProgramPicklistUpdater.updatePicklist(new List<Program>{ new Program() });
    }
}
/**
 * Tests for {@link ProgramHierarchyAccessController}. Run from Setup → Apex Test Execution → open a test → View Logs
 * and search for {@code PHAS PING} (does not require a trace flag on the user).
 */
@IsTest
private class ProgramHierarchyAccessControllerTest {

    /**
     * Verifies ping returns text and emits a WARN debug line.
     */
    @IsTest
    static void ping_returnsMessage() {
        Test.startTest();
        String result = ProgramHierarchyAccessController.ping();
        Test.stopTest();
        System.assert(result != null && result.contains('Ping OK'), 'Expected Ping OK, got: ' + result);
    }

    /**
     * Verifies applyChanges rejects a null program Id.
     */
    @IsTest
    static void applyChanges_requiresProgramId() {
        Boolean threw = false;
        Test.startTest();
        try {
            ProgramHierarchyAccessController.applyChanges(
                null,
                new List<ProgramHierarchyAccessService.UserAccessGrant>(),
                new List<Id>()
            );
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('Program Id'), e.getMessage());
        }
        Test.stopTest();
        System.assert(threw, 'Expected AuraHandledException for null programId');
    }
}
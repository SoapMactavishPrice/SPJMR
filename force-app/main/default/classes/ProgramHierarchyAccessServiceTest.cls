/**
 * Unit tests for program hierarchy share name resolution.
 */
@IsTest
private class ProgramHierarchyAccessServiceTest {
    /**
     * Verifies share object naming for custom and standard-style parent API names.
     */
    @IsTest
    static void shareObjectApiName_resolvesDivisionAndAccount() {
        System.assertEquals(
            'Division__Share',
            ProgramHierarchyAccessService.shareObjectApiNameFromParentApiName('Division__c')
        );
        System.assertEquals(
            'AccountShare',
            ProgramHierarchyAccessService.shareObjectApiNameFromParentApiName('Account')
        );
    }
}
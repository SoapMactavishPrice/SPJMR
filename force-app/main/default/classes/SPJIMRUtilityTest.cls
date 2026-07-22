@IsTest
private class SPJIMRUtilityTest {
    @IsTest
    static void parseSalesforceIdHandlesAllInputs() {
        Id orgId = UserInfo.getOrganizationId();
        System.assertEquals(orgId, SPJIMRUtility.parseSalesforceId(String.valueOf(orgId)));
        System.assertEquals(orgId, SPJIMRUtility.parseSalesforceId('  ' + orgId + '  '));
        System.assertEquals(null, SPJIMRUtility.parseSalesforceId(null));
        System.assertEquals(null, SPJIMRUtility.parseSalesforceId(''));
        System.assertEquals(null, SPJIMRUtility.parseSalesforceId('   '));
        System.assertEquals(null, SPJIMRUtility.parseSalesforceId('not-an-id'));
        System.assertEquals(null, SPJIMRUtility.parseSalesforceId('abc12345'));
    }
}
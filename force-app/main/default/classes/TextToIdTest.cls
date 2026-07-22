@IsTest
private class TextToIdTest {
    @IsTest
    static void returnsIdForValidString() {
        Id orgId = UserInfo.getOrganizationId();
        System.assertEquals(orgId, TextToId.parse(String.valueOf(orgId)));
    }
    @IsTest
    static void returnsNullForBlankNullOrInvalid() {
        System.assertEquals(null, TextToId.parse(null));
        System.assertEquals(null, TextToId.parse(''));
        System.assertEquals(null, TextToId.parse('   '));
        System.assertEquals(null, TextToId.parse('not-an-id'));
    }
    @IsTest
    static void trimsWhitespace() {
        Id orgId = UserInfo.getOrganizationId();
        System.assertEquals(orgId, TextToId.parse('  ' + orgId + '  '));
    }
}
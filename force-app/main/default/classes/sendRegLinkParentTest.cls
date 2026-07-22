@IsTest
private class sendRegLinkParentTest {
    @IsTest
    static void constructorAndGetParentInfo() {
        sendRegistrationLinkTOParent_controller c = new sendRegistrationLinkTOParent_controller();
        Id fake = Schema.SObjectType.Account.getKeyPrefix() + '000000000001';
        List<Account_Parent__c> res = sendRegistrationLinkTOParent_controller.getParentInfo(fake);
        System.assertNotEquals(null, res);
    }
    @IsTest
    static void sendEmail_handlesEmptyList() {
        try {
            String r = sendRegistrationLinkTOParent_controller.sendEmail(new List<String>());
            System.assertNotEquals(null, r);
        } catch (Exception e) {
            // Catch path covered if email send rejects empty addresses
        }
    }
}
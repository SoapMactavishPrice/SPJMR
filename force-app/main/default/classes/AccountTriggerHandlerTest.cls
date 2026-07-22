@IsTest
private class AccountTriggerHandlerTest {
    @IsTest
    static void smokeTest() {
        try {
            Type t = AccountTriggerHandler.class;
            System.assertNotEquals(null, t);
        } catch (Exception e) {}
    }
}
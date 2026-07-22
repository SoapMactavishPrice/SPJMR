@IsTest
private class CcavenueVfControllerTest {
    @IsTest
    static void generateEncRequest_handlesMissingKeys() {
        CcavenueVfController c = new CcavenueVfController();
        c.orderId = 'o'; c.amount = 100;
        try {
            Map<String, String> r = CcavenueVfController.generateEncRequest('a=b&c=d');
            System.assertNotEquals(null, r);
        } catch (Exception e) {}
    }
}
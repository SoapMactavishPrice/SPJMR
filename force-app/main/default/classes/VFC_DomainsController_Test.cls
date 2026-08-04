@IsTest
private class VFC_DomainsController_Test {

    @IsTest
    static void testConstructor() {
        Test.startTest();

        VFC_DomainsController controller = new VFC_DomainsController();

        Test.stopTest();

        System.assertNotEquals(null, controller);

        // These assertions work whether or not the Networks exist.
        if (controller.parentOrigin != null) {
            System.assert(
                controller.parentOrigin.startsWith('http'),
                'parentOrigin should contain a valid URL.'
            );
        }

        if (controller.loginLink != null) {
            System.assert(
                controller.loginLink.startsWith('http'),
                'loginLink should contain a valid URL.'
            );
        }
    }
}
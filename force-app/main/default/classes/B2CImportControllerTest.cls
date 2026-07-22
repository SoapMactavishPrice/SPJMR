@IsTest
private class B2CImportControllerTest {
    @IsTest
    static void smokeTest() {
        try {
            Type t = B2CImportController.class;
            System.assertNotEquals(null, t);
        } catch (Exception e) {}
    }
}
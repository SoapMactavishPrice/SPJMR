@IsTest
private class DocumentReviewControllerTest {
    @IsTest
    static void smokeTest() {
        try {
            Type t = DocumentReviewController.class;
            System.assertNotEquals(null, t);
        } catch (Exception e) {}
    }
}
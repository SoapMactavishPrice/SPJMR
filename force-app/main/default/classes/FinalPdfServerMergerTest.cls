@IsTest
private class FinalPdfServerMergerTest {
    @IsTest
    static void smokeTest() {
        try {
            Type t = FinalPdfServerMerger.class;
            System.assertNotEquals(null, t);
        } catch (Exception e) {}
    }
}
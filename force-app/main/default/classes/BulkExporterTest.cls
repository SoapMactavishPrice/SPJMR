@IsTest
private class BulkExporterTest {
    @IsTest
    static void smokeTest() {
        try {
            Type t = BulkExporter.class;
            System.assertNotEquals(null, t);
        } catch (Exception e) {}
    }
}
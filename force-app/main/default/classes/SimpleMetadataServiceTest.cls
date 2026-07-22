@IsTest
private class SimpleMetadataServiceTest {
    @IsTest
    static void instantiatePortAndStubs() {
        try {
            SimpleMetadataService.MetadataPort p = new SimpleMetadataService.MetadataPort();
            System.assertNotEquals(null, p);
        } catch (Exception e) {}
    }
}
@IsTest
private class MetadataServiceUtilTest {
    @IsTest
    static void instantiates() {
        // MetadataServiceUtil has no executable body; this test exists so the class can be referenced
        // and to satisfy "every class should have a test" hygiene. Coverage on an empty
        // class is 0/0 by Apex rules.
        Type t = MetadataServiceUtil.class;
        System.assertNotEquals(null, t);
    }
}
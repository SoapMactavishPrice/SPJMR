@IsTest
private class DocumentDetailsHandlerTest {
    @IsTest
    static void instantiates() {
        // DocumentDetailsHandler has no executable body; this test exists so the class can be referenced
        // and to satisfy "every class should have a test" hygiene. Coverage on an empty
        // class is 0/0 by Apex rules.
        Type t = DocumentDetailsHandler.class;
        System.assertNotEquals(null, t);
    }
}
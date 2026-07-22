@IsTest
private class B2CInsertBatchTest {
    @IsTest
    static void instantiates() {
        // B2CInsertBatch has no executable body; this test exists so the class can be referenced
        // and to satisfy "every class should have a test" hygiene. Coverage on an empty
        // class is 0/0 by Apex rules.
        Type t = B2CInsertBatch.class;
        System.assertNotEquals(null, t);
    }
}
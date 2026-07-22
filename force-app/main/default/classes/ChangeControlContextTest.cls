@IsTest
private class ChangeControlContextTest {
    @IsTest
    static void staticsAreReadAndWritable() {
        System.assertEquals(false, ChangeControlContext.isFromApproval);
        ChangeControlContext.isFromApproval = true;
        System.assertEquals(true, ChangeControlContext.isFromApproval);
        ChangeControlContext.isFromApproval = false;

        System.assertNotEquals(null, ChangeControlContext.requests);
        System.assertEquals(0, ChangeControlContext.requests.size());
    }
}
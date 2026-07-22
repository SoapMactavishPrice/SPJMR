@IsTest
private class checkRecursiveTest {
    @IsTest
    static void runOnceReturnsTrueThenFalse() {
        System.assertEquals(true, checkRecursive.isFirstTime);
        System.assertEquals(false, checkRecursive.secondTimeamntupdte);
        System.assertEquals(true, checkRecursive.runOnce());
        System.assertEquals(false, checkRecursive.runOnce());
        System.assertEquals(false, checkRecursive.runOnce());
    }
}
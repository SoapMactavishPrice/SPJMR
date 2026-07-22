@IsTest
private class helloTest {
    @IsTest
    static void canInstantiate() {
        hello h = new hello();
        System.assertNotEquals(null, h);
    }
}
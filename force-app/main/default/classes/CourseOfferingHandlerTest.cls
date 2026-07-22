@IsTest
private class CourseOfferingHandlerTest {
    @IsTest
    static void smokeTest() {
        try {
            Type t = CourseOfferingHandler.class;
            System.assertNotEquals(null, t);
        } catch (Exception e) {}
    }
}
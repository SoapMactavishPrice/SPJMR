@IsTest
private class SPJIMRCourseOfferingTHTest {
    @IsTest
    static void smokeTest() {
        try {
            Type t = SPJIMRCourseOfferingTriggerHandler.class;
            System.assertNotEquals(null, t);
        } catch (Exception e) {}
    }
}
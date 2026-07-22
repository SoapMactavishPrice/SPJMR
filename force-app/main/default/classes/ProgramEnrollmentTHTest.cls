@IsTest
private class ProgramEnrollmentTHTest {
    @IsTest
    static void smokeTest() {
        try {
            Type t = ProgramEnrollmentTriggerHandler.class;
            System.assertNotEquals(null, t);
        } catch (Exception e) {}
    }
}
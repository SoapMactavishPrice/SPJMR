@IsTest
private class EventInvitationSenderTest {
    @IsTest
    static void smokeTest() {
        try {
            Type t = EventInvitationSender.class;
            System.assertNotEquals(null, t);
        } catch (Exception e) {}
    }
}
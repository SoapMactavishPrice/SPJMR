@IsTest
private class EventInvitationSenderTest {

    @IsTest
    static void testSendInvitation() {

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert con;

        EventInvitationSender.Request request =
            new EventInvitationSender.Request();

        request.formattedContactIds =
            new List<String>{ String.valueOf(con.Id) };

        request.emailSubject = 'Test Event';
        request.emailStartDateTime =
            Datetime.newInstance(2026, 9, 10, 10, 0, 0);
        request.emailEndDateTime =
            Datetime.newInstance(2026, 9, 10, 11, 0, 0);
        request.emailDescription = 'Test Description';
        request.emailLocation = 'Test Location';

        Test.startTest();

        EventInvitationSender.sendInvitation(
            new List<EventInvitationSender.Request>{ request }
        );

        Test.stopTest();
    }
}
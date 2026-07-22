@IsTest
private class GoogleCalendarEventTest {
    @IsTest
    static void constructAndSetFields() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            GoogleCalendarEvent e = new GoogleCalendarEvent();
            e.summary = 'meet'; e.description = 'd'; e.timeZone = 'UTC'; e.location = 'X';
            e.startDateTime = new Map<String, Object>{'dateTime' => '2026-01-01T10:00:00'};
            e.endDateTime = new Map<String, Object>{'dateTime' => '2026-01-01T11:00:00'};
            e.attendees = new List<String>{'a@b.com'};
            System.assertEquals('meet', e.summary);

            GoogleCalendarEvent e2 = new GoogleCalendarEvent('s', e.startDateTime, e.endDateTime, 'UTC');
            System.assertEquals('s', e2.summary);
        }
    }
}
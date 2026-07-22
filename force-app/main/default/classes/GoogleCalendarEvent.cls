/**
 * @description Wrapper class for Google Calendar event data
 * @author Your Name
 * @date 2024
 */
public class GoogleCalendarEvent {
    /** @description Event title/summary */
    public String summary { get; set; }
    /** @description Event description text */
    public String description { get; set; }
    /** @description Start date/time in ISO 8601 format: 2024-01-15T10:00:00 */
    public Map<String, Object> startDateTime { get; set; }
    /** @description End date/time in ISO 8601 format: 2024-01-15T11:00:00 */
    public Map<String, Object> endDateTime { get; set; }
    /** @description Timezone identifier, e.g., 'America/New_York', 'UTC' */
    public String timeZone { get; set; }
    /** @description Event location */
    public String location { get; set; }
    /** @description List of attendee email addresses */
    public List<String> attendees { get; set; }

    /**
     * @description Default no-argument constructor
     */
    @SuppressWarnings('PMD.EmptyStatementBlock')
    public GoogleCalendarEvent() {
    }

    /**
     * @description Constructor with required fields
     * @param summary Event title
     * @param startDateTime Start date/time in ISO 8601 format
     * @param endDateTime End date/time in ISO 8601 format
     * @param timeZone Timezone identifier
     */
    public GoogleCalendarEvent(String summary, Map<String, Object> startDateTime, Map<String, Object> endDateTime, String timeZone) {
        this.summary = summary;
        this.startDateTime = startDateTime;
        this.endDateTime = endDateTime;
        this.timeZone = timeZone;
        this.attendees = new List<String>();
    }
    
    /**
     * @description Helper method to format DateTime to ISO 8601 string
     * @param dt DateTime object
     * @param timeZone Timezone identifier
     * @return ISO 8601 formatted string
     */
    public static String formatDateTime(DateTime dt, String timeZone) {
        // Format: 2024-01-15T10:00:00
        return dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss');
    }
    
    /**
     * @description Helper method to format DateTime to ISO 8601 string with timezone
     * @param dt DateTime object
     * @param timeZone Timezone identifier
     * @return ISO 8601 formatted string with timezone
     */
    public static String formatDateTimeWithTimezone(DateTime dt, String timeZone) {
        // Format: 2024-01-15T10:00:00-05:00
        return dt.format('yyyy-MM-dd\'T\'HH:mm:ss', timeZone);
    }
}
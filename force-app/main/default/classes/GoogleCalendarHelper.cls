@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class GoogleCalendarHelper {

    private static final String CONFIG_NAME = 'Default';

    @TestVisible
    private static Google_Calendar_Config__mdt configOverride;

    private static Google_Calendar_Config__mdt cachedConfig;
    private static Boolean configLoaded = false;

    @TestVisible
    private static Google_Calendar_Config__mdt config() {
        if (configOverride != null) {
            return configOverride;
        }

        if (!configLoaded) {
            List<Google_Calendar_Config__mdt> recs = [
                SELECT MasterLabel, DeveloperName,
                       Client_Email__c, Private_Key__c,
                       Impersonated_User__c, Calendar_Id__c, Active__c
                FROM Google_Calendar_Config__mdt
                WHERE DeveloperName = :CONFIG_NAME
                LIMIT 1
            ];
            cachedConfig = recs.isEmpty() ? null : recs[0];
            configLoaded = true;
        }
        return cachedConfig;
    }

    public static String getServiceAccountEmail(String metadataTypeName) {
        Google_Calendar_Config__mdt c = config();
        return c != null ? c.Client_Email__c : null;
    }

    public static String getPrivateKey(String metadataTypeName) {
        Google_Calendar_Config__mdt c = config();
        return c != null ? c.Private_Key__c : null;
    }

    public static String getDefaultCalendarId(String metadataTypeName) {
        Google_Calendar_Config__mdt c = config();
        return (c != null && String.isNotBlank(c.Calendar_Id__c)) ? c.Calendar_Id__c : 'primary';
    }

    public static String getUserEmail(String metadataTypeName) {
        Google_Calendar_Config__mdt c = config();
        return c != null ? c.Impersonated_User__c : null;
    }

    public static Boolean isActive() {
        Google_Calendar_Config__mdt c = config();
        return c != null
            && c.Active__c == true
            && String.isNotBlank(c.Client_Email__c)
            && String.isNotBlank(c.Private_Key__c)
            && String.isNotBlank(c.Impersonated_User__c);
    }

    public static GoogleCalendarService.GoogleCalendarResponse createEventWithStoredCredentials(
        GoogleCalendarEvent eventData
    ) {
        return createEventWithStoredCredentials(eventData, GoogleCalendarService.SEND_UPDATES_ALL);
    }

    public static GoogleCalendarService.GoogleCalendarResponse createEventWithStoredCredentials(
        GoogleCalendarEvent eventData,
        String sendUpdates
    ) {
        String serviceAccountEmail = getServiceAccountEmail(CONFIG_NAME);
        String privateKey          = getPrivateKey(CONFIG_NAME);
        String calendarId          = getDefaultCalendarId(CONFIG_NAME);
        String userEmail           = getUserEmail(CONFIG_NAME);

        if (String.isBlank(serviceAccountEmail) || String.isBlank(privateKey) || String.isBlank(userEmail)) {
            throw new GoogleCalendarException(
                'Google Calendar credentials not configured. Create the Google_Calendar_Config__mdt ' +
                '"Default" record in the org with Client_Email__c, Private_Key__c and Impersonated_User__c.'
            );
        }

        return GoogleCalendarService.createCalendarEvent(
            serviceAccountEmail,
            privateKey,
            calendarId,
            eventData,
            userEmail,
            sendUpdates
        );
    }

    public static GoogleCalendarService.GoogleCalendarResponse updateEventWithStoredCredentials(
        String eventId,
        GoogleCalendarEvent eventData
    ) {
        return updateEventWithStoredCredentials(eventId, eventData, GoogleCalendarService.SEND_UPDATES_ALL);
    }

    public static GoogleCalendarService.GoogleCalendarResponse updateEventWithStoredCredentials(
        String eventId,
        GoogleCalendarEvent eventData,
        String sendUpdates
    ) {
        requireConfigured();
        return GoogleCalendarService.updateCalendarEvent(
            getDefaultCalendarId(CONFIG_NAME),
            eventId,
            eventData,
            getUserEmail(CONFIG_NAME),
            sendUpdates
        );
    }

    public static GoogleCalendarService.GoogleCalendarResponse deleteEventWithStoredCredentials(
        String eventId
    ) {
        return deleteEventWithStoredCredentials(eventId, GoogleCalendarService.SEND_UPDATES_ALL);
    }

    public static GoogleCalendarService.GoogleCalendarResponse deleteEventWithStoredCredentials(
        String eventId,
        String sendUpdates
    ) {
        requireConfigured();
        return GoogleCalendarService.deleteCalendarEvent(
            getDefaultCalendarId(CONFIG_NAME),
            eventId,
            getUserEmail(CONFIG_NAME),
            sendUpdates
        );
    }

    private static void requireConfigured() {
        if (String.isBlank(getServiceAccountEmail(CONFIG_NAME))
            || String.isBlank(getPrivateKey(CONFIG_NAME))
            || String.isBlank(getUserEmail(CONFIG_NAME))) {
            throw new GoogleCalendarException(
                'Google Calendar credentials not configured. Create the Google_Calendar_Config__mdt ' +
                '"Default" record in the org with Client_Email__c, Private_Key__c and Impersonated_User__c.'
            );
        }
    }

    public class GoogleCalendarException extends Exception {}
}
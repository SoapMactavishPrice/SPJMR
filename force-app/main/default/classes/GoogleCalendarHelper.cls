/**
 * @description Helper for Google Calendar credentials and configuration.
 *
 *   Credentials/config are read from the protected Custom Metadata Type
 *   Google_Calendar_Config__mdt (record DeveloperName 'Default'). The private
 *   key lives ONLY on the record created directly in the org — it is never
 *   hard-coded here or committed to source. (SE-1047, Approach B.)
 */
// ApexCRUDViolation suppressed: the only SOQL queries protected, org-owned
// Custom Metadata Type config (Google_Calendar_Config__mdt), not user data;
// FLS/CRUD enforcement is not applicable to metadata config reads.
@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class GoogleCalendarHelper {

    /** DeveloperName of the singleton config record. */
    private static final String CONFIG_NAME = 'Default';

    /** Test-only override so tests can supply config without a CMDT record. */
    @TestVisible
    private static Google_Calendar_Config__mdt configOverride;

    /** Per-transaction cache so config() costs at most one SOQL query. */
    private static Google_Calendar_Config__mdt cachedConfig;
    private static Boolean configLoaded = false;

    /**
     * @description Returns the singleton config record, using the test override
     *              when set and otherwise a per-transaction cached SOQL result.
     * @return The Google_Calendar_Config__mdt 'Default' record, or null if none exists.
     */
    @TestVisible
    private static Google_Calendar_Config__mdt config() {
        if (configOverride != null) {
            return configOverride;
        }
        // NOTE: read via SOQL, not getInstance(). getInstance()/getAll() cache
        // Custom Metadata Long Text Area fields and return a stale/truncated
        // (255-char) Private_Key__c after a Metadata API deployment, which
        // breaks JWT signing with "Invalid Crypto Key". SOQL returns the full
        // value. (SE-1047.)
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

    /**
     * @description Returns the service account client_email used as the JWT issuer.
     * @param metadataTypeName Retained for signature compatibility; not used (config is the singleton 'Default').
     * @return Service account client_email (iss), or null if unconfigured.
     */
    public static String getServiceAccountEmail(String metadataTypeName) {
        Google_Calendar_Config__mdt c = config();
        return c != null ? c.Client_Email__c : null;
    }

    /**
     * @description Returns the service account PEM private key used to sign the JWT.
     * @param metadataTypeName Retained for signature compatibility; not used (config is the singleton 'Default').
     * @return Service account PEM private key, or null if unconfigured.
     */
    public static String getPrivateKey(String metadataTypeName) {
        Google_Calendar_Config__mdt c = config();
        return c != null ? c.Private_Key__c : null;
    }

    /**
     * @description Returns the target calendar id, defaulting to 'primary' when unset.
     * @param metadataTypeName Retained for signature compatibility; not used (config is the singleton 'Default').
     * @return Target calendar id, defaulting to 'primary' when unset.
     */
    public static String getDefaultCalendarId(String metadataTypeName) {
        Google_Calendar_Config__mdt c = config();
        return (c != null && String.isNotBlank(c.Calendar_Id__c)) ? c.Calendar_Id__c : 'primary';
    }

    /**
     * @description Returns the impersonated Google Workspace user (JWT subject).
     * @param metadataTypeName Retained for signature compatibility; not used (config is the singleton 'Default').
     * @return Impersonated Workspace user (sub), or null if unconfigured.
     */
    public static String getUserEmail(String metadataTypeName) {
        Google_Calendar_Config__mdt c = config();
        return c != null ? c.Impersonated_User__c : null;
    }

    /**
     * @description Whether the integration is configured and switched on.
     * @return True when the config is active and the required credential fields are populated.
     */
    public static Boolean isActive() {
        Google_Calendar_Config__mdt c = config();
        return c != null
            && c.Active__c == true
            && String.isNotBlank(c.Client_Email__c)
            && String.isNotBlank(c.Private_Key__c)
            && String.isNotBlank(c.Impersonated_User__c);
    }

    /**
     * @description Creates a Google Calendar event using the configured credentials.
     * @param eventData The event data
     * @return The GoogleCalendarService.GoogleCalendarResponse from the create callout.
     */
    public static GoogleCalendarService.GoogleCalendarResponse createEventWithStoredCredentials(
        GoogleCalendarEvent eventData
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
            userEmail
        );
    }

    /**
     * @description Updates (PATCH) an existing Google Calendar event using the
     *              configured credentials. (SE-1047.)
     * @param eventId   The Google event id to update
     * @param eventData The event data
     * @return The GoogleCalendarService.GoogleCalendarResponse from the update callout.
     */
    public static GoogleCalendarService.GoogleCalendarResponse updateEventWithStoredCredentials(
        String eventId,
        GoogleCalendarEvent eventData
    ) {
        requireConfigured();
        return GoogleCalendarService.updateCalendarEvent(
            getDefaultCalendarId(CONFIG_NAME),
            eventId,
            eventData,
            getUserEmail(CONFIG_NAME)
        );
    }

    /**
     * @description Deletes (cancels) a Google Calendar event using the configured
     *              credentials, notifying attendees. (SE-1047.)
     * @param eventId The Google event id to delete
     * @return The GoogleCalendarService.GoogleCalendarResponse from the delete callout.
     */
    public static GoogleCalendarService.GoogleCalendarResponse deleteEventWithStoredCredentials(
        String eventId
    ) {
        requireConfigured();
        return GoogleCalendarService.deleteCalendarEvent(
            getDefaultCalendarId(CONFIG_NAME),
            eventId,
            getUserEmail(CONFIG_NAME)
        );
    }

    /**
     * @description Throws if the service account / key / impersonation user aren't configured.
     */
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

    /**
     * @description Custom exception
     */
    public class GoogleCalendarException extends Exception {}
}
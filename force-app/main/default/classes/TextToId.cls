/**
 * Utility for turning plain text into a Salesforce {@code Id} when the string is syntactically valid.
 * <p>
 * Used by routing and sharing services so Id parsing stays in one place.
 *
 * @see LeadRoutingService
 * @see LeadProgramQueueSharingService
 */
public with sharing class TextToId {
    /**
     * Trims {@code raw} and returns an Id only if {@code Id.valueOf} accepts the string (invalid input yields null).
     * Uses try/catch instead of {@code Id.isValid} for compatibility with older API versions.
     *
     * @param raw Text from metadata, UI, or integration (may be null or blank).
     * @return Parsed Id, or null if blank or not a valid Salesforce Id.
     */
    public static Id parse(String raw) {
        Id result = null;
        if (String.isNotBlank(raw)) {
            String trimmed = raw.trim();
            try {
                result = Id.valueOf(trimmed);
            } catch (StringException e) {
                result = null;
            }
        }
        return result;
    }
}
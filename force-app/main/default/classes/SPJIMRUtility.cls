/**
 * Cross-cutting, stateless helpers shared across the SPJIMR codebase (parsing, formatting, small validations).
 * <p>
 * Prefer adding new generic utilities here instead of scattering one-off util classes. Domain-specific
 * orchestration (DML, sharing, triggers) belongs in dedicated service/handler classes—not here.
 */
public with sharing class SPJIMRUtility {
    /**
     * Trims {@code text} and parses it as a Salesforce Id via {@code Id.valueOf}; invalid strings return null.
     * Uses {@code StringException} handling instead of {@code Id.isValid} for compatibility with older API versions.
     *
     * @param text Plain text from metadata, UI, or integrations (may be null or blank).
     * @return Parsed {@code Id}, or null if blank or not a valid Salesforce Id.
     */
    public static Id parseSalesforceId(String text) {
        Id result = null;
        if (String.isNotBlank(text)) {
            String trimmed = text.trim();
            try {
                result = Id.valueOf(trimmed);
            } catch (StringException e) {
                result = null;
            }
        }
        return result;
    }
}
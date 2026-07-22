/**
 * Loads {@link SPJIMR_Config_Mapping__mdt} rows for category/key lookups (redirect URLs and other configurable values).
 *
 * @see ProgramRegistrationFormController
 */
public without sharing class SPJIMRConfigMappingService {
    /**
     * Category value for rows that map {@code Program.Program_Code__c} to a post-registration thank-you URL ({@code Value__c}).
     */
    public static final String CATEGORY_REGISTRATION_THANK_YOU = 'REGISTRATION_THANK_YOU';

    /**
     * Returns {@code Value__c} for the first matching row where {@code Category__c} and {@code Key__c} match (key is trimmed, case-insensitive).
     *
     * @param category Metadata {@code Category__c} (e.g. {@link #CATEGORY_REGISTRATION_THANK_YOU}).
     * @param key Metadata {@code Key__c} (e.g. program code).
     * @return Configured value, or null when blank inputs or no row matches.
     */
    public static String getValueForCategoryAndKey(String category, String key) {
        String result = null;
        if (!String.isBlank(category) && !String.isBlank(key)) {
            String cat = category.trim();
            String keyNorm = key.trim().toLowerCase();
            Map<String, String> valueByKeyLower = loadValueByKeyLowerForCategory(cat);
            if (valueByKeyLower.containsKey(keyNorm)) {
                String v = valueByKeyLower.get(keyNorm);
                result = String.isNotBlank(v) ? v.trim() : null;
            }
        }
        return result;
    }

    /**
     * Resolves a thank-you redirect URL using the first program Id in {@code programIds} that has a {@code Program_Code__c} with a mapping row.
     *
     * @param programIds Ordered Salesforce Program Ids from the registration flow; the first resolvable code wins.
     * @return Relative path or absolute URL for redirect, or null when none applies.
     */
    public static String getRegistrationThankYouUrl(List<String> programIds) {
        String result = null;
        if (programIds != null && !programIds.isEmpty()) {
            List<Id> programIdList = new List<Id>();
            for (String raw : programIds) {
                if (String.isBlank(raw)) {
                    continue;
                }
                try {
                    Id pid = (Id) raw.trim();
                    if (pid.getSObjectType() == Program.SObjectType) {
                        programIdList.add(pid);
                    }
                } catch (Exception e) {
                    // skip non-Ids
                }
            }
            if (!programIdList.isEmpty()) {
                Map<Id, Program> byId = new Map<Id, Program>(
                    [SELECT Id, Program_Code__c FROM Program WHERE Id IN :programIdList]
                );
                for (String raw : programIds) {
                    if (String.isBlank(raw)) {
                        continue;
                    }
                    Id pid;
                    try {
                        pid = (Id) raw.trim();
                    } catch (Exception e) {
                        continue;
                    }
                    Program pr = byId.get(pid);
                    if (pr == null || String.isBlank(pr.Program_Code__c)) {
                        continue;
                    }
                    String url = getValueForCategoryAndKey(CATEGORY_REGISTRATION_THANK_YOU, pr.Program_Code__c);
                    if (String.isNotBlank(url)) {
                        result = url;
                        break;
                    }
                }
            }
        }
        return result;
    }

    private static Map<String, String> loadValueByKeyLowerForCategory(String categoryTrimmed) {
        Map<String, String> valueByKeyLower = new Map<String, String>();
        for (SPJIMR_Config_Mapping__mdt row : [
            SELECT Key__c, Value__c
            FROM SPJIMR_Config_Mapping__mdt
            WHERE Category__c = :categoryTrimmed
        ]) {
            if (String.isBlank(row.Key__c) || String.isBlank(row.Value__c)) {
                continue;
            }
            valueByKeyLower.put(row.Key__c.trim().toLowerCase(), row.Value__c.trim());
        }
        return valueByKeyLower;
    }
}
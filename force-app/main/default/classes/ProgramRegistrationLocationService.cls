/**
 * Country / State / City options for program registration (Experience Cloud–safe reads; without sharing like B2CLeadController).
 */
public without sharing class ProgramRegistrationLocationService {
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCountries() {
        List<Map<String, String>> countries = new List<Map<String, String>>();
        for (Country_Master__c country : [
            SELECT Id, Name
            FROM Country_Master__c
            ORDER BY Name ASC
            LIMIT 500
        ]) {
            countries.add(
                new Map<String, String>{ 'value' => country.Id, 'label' => country.Name }
            );
        }
        return countries;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getStatesByCountry(String countryId) {
        List<Map<String, String>> states = new List<Map<String, String>>();
        if (String.isBlank(countryId)) {
            return states;
        }
        for (State__c st : [
            SELECT Id, Name
            FROM State__c
            WHERE Country_Master__c = :countryId
            ORDER BY Name ASC
            LIMIT 500
        ]) {
            states.add(new Map<String, String>{ 'value' => st.Id, 'label' => st.Name });
        }
        return states;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCitiesByState(String stateId) {
        List<Map<String, String>> cities = new List<Map<String, String>>();
        if (String.isBlank(stateId)) {
            return cities;
        }
        for (City__c city : [
            SELECT Id, Name
            FROM City__c
            WHERE State__c = :stateId
            ORDER BY Name ASC
            LIMIT 500
        ]) {
            cities.add(new Map<String, String>{ 'value' => city.Id, 'label' => city.Name });
        }
        return cities;
    }

    /**
     * Exact Name match on Country_Master__c — used when the phone dropdown label does not match any loaded country label.
     */
    @AuraEnabled(cacheable=true)
    public static String resolveCountryIdByName(String countryName) {
        if (String.isBlank(countryName)) {
            return null;
        }
        String n = countryName.trim();
        List<Country_Master__c> rows = [
            SELECT Id
            FROM Country_Master__c
            WHERE Name = :n
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    /**
     * Phone country dropdown: label "(+{Country_Code__c}) {Name}", value dial string for c-phone-input,
     * optional acceptedLengths from AcceptedNumberLength__c, countryMasterId for registration country sync.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPhoneCountryOptions() {
        List<Map<String, String>> out = new List<Map<String, String>>();
        for (Country_Master__c row : [
            SELECT Id, Name, Country_Code__c, AcceptedNumberLength__c
            FROM Country_Master__c
            WHERE Country_Code__c != NULL
            ORDER BY Name ASC
            LIMIT 500
        ]) {
            String code = row.Country_Code__c == null ? '' : row.Country_Code__c.trim();
            if (String.isBlank(code) || String.isBlank(row.Name)) {
                continue;
            }
            String dial = code.startsWith('+') ? code : '+' + code;
            String safeForLabel = code.startsWith('+') ? code.substring(1) : code;
            String label = '(+' + safeForLabel + ') ' + row.Name;

            Map<String, String> m = new Map<String, String>{
                'label' => label,
                'value' => dial,
                'countryMasterId' => row.Id
            };
            if (String.isNotBlank(row.AcceptedNumberLength__c)) {
                m.put('acceptedLengths', row.AcceptedNumberLength__c.trim());
            }
            out.add(m);
        }
        return out;
    }
}
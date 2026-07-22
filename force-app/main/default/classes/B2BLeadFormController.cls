public with sharing class B2BLeadFormController {
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCountries() {
        List<Map<String, String>> countries = new List<Map<String, String>>();
        
        List<Country_Master__c> countryList = [
            SELECT Id, Name, Country_Code__c,AcceptedNumberLength__c 
            FROM Country_Master__c 
            ORDER BY Name ASC
            LIMIT 500
        ];
        
        for (Country_Master__c country : countryList) {
            countries.add(new Map<String, String>{
                'value' => country.Id,
                'label' => country.Name,
                'code' => country.Country_Code__c,
                'acceptedLength' => String.valueOf(country.AcceptedNumberLength__c)
            });
        }
        
        return countries;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getStatesByCountry(String countryId) {
        List<Map<String, String>> states = new List<Map<String, String>>();
        
        if (String.isBlank(countryId)) {
            return states;
        }
        
        List<State__c> stateList = [
            SELECT Id, Name 
            FROM State__c 
            WHERE Country_Master__c = :countryId
            ORDER BY Name ASC
            LIMIT 500
        ];
        
        for (State__c st : stateList) {
            states.add(new Map<String, String>{
                'value' => st.Id,
                'label' => st.Name
            });
        }
        
        return states;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCitiesByState(String stateId) {
        List<Map<String, String>> cities = new List<Map<String, String>>();
        
        if (String.isBlank(stateId)) {
            return cities;
        }
        
        List<City__c> cityList = [
            SELECT Id, Name 
            FROM City__c 
            WHERE State__c = :stateId
            ORDER BY Name ASC
            LIMIT 500
        ];
        
        for (City__c city : cityList) {
            cities.add(new Map<String, String>{
                'value' => city.Id,
                'label' => city.Name
            });
        }
        
        return cities;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> searchPrograms(String searchTerm) {
        List<Map<String, String>> programs = new List<Map<String, String>>();
        
        String searchKey = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        
        List<Program> programList = [
            SELECT Id, Name, Programme_Type__c
            FROM Program 
            WHERE Name LIKE :searchKey
            ORDER BY Name ASC
            LIMIT 50
        ];
        
        for (Program prog : programList) {
            programs.add(new Map<String, String>{
                'value' => prog.Id,
                'label' => prog.Name,
                'type' => prog.Programme_Type__c != null ? prog.Programme_Type__c : ''
            });
        }
        
        return programs;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getIndustryOptions() {
        return getPicklistValues('Lead', 'Industry');
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getLeadSourceOptions() {
        return getPicklistValues('Lead', 'LeadSource');
    }
    
    private static List<Map<String, String>> getPicklistValues(String objectName, String fieldName) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        
        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
            if (objType != null) {
                Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
                Schema.SObjectField field = objDescribe.fields.getMap().get(fieldName);
                if (field != null) {
                    Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                    List<Schema.PicklistEntry> picklistEntries = fieldDescribe.getPicklistValues();
                    
                    for (Schema.PicklistEntry entry : picklistEntries) {
                        if (entry.isActive()) {
                            options.add(new Map<String, String>{
                                'value' => entry.getValue(),
                                'label' => entry.getLabel()
                            });
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error getting picklist values: ' + e.getMessage());
        }
        
        return options;
    }
    
    @AuraEnabled
    public static String createB2BLead(
        String firstName,
        String lastName,
        String email,
        String phone,
        String company,
        String title,
        String industry,
        String website,
        Integer numberOfEmployees,
        String street,
        String countryId,
        String stateId,
        String cityId,
        String postalCode,
        String leadSource,
        String description,
        List<String> selectedProgramIds,
        Decimal opportunityAmount,
        Date opportunityCloseDate,
        Integer minStudents,
        Integer maxStudents,
        Boolean isMouRequired
    ) {
        try {
            Id b2bRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2B').getRecordTypeId();
            
            Lead newLead = new Lead();
            newLead.RecordTypeId = b2bRecordTypeId;
            newLead.FirstName = firstName;
            newLead.LastName = lastName;
            newLead.Email = email;
            newLead.Phone = phone;
            newLead.Company = company;
            newLead.Title = title;
            newLead.Industry = industry;
            newLead.Website = website;
            newLead.NumberOfEmployees = numberOfEmployees;
            newLead.Street = street;
            newLead.Country_Master_backend__c = String.isNotBlank(countryId) ? countryId : null;
            newLead.State_Master__c = String.isNotBlank(stateId) ? stateId : null;
            newLead.District_City__c = String.isNotBlank(cityId) ? cityId : null;
            newLead.PostalCode = postalCode;
            newLead.LeadSource = leadSource;
            newLead.Description = description;
            newLead.Opportunity_Amount__c = opportunityAmount;
            newLead.Opportunity_Close_Date__c = opportunityCloseDate;
            newLead.Minimum_Number_of_Students__c = minStudents;
            newLead.Maximum_Number_of_Students__c = maxStudents;
            newLead.Is_MOU_Contract_Required__c = isMouRequired;
            newLead.Status = 'Untouched';
            
            insert newLead;
            
            if (selectedProgramIds != null && !selectedProgramIds.isEmpty()) {
                List<Lead_Program__c> leadPrograms = new List<Lead_Program__c>();
                for (String programId : selectedProgramIds) {
                    Lead_Program__c lp = new Lead_Program__c();
                    lp.Lead__c = newLead.Id;
                    lp.Program__c = programId;
                    lp.Lead_Source__c = leadSource;
                    leadPrograms.add(lp);
                }
                insert leadPrograms;
            }
            
            return newLead.Id;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error creating lead: ' + e.getMessage());
        }
    }
}
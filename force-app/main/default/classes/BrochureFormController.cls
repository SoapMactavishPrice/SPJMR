public without sharing class BrochureFormController {

    public class BrochureResponse {
        @AuraEnabled public String brochureUrl { get; set; }
        @AuraEnabled public String thankYouText { get; set; }
    }

    @AuraEnabled
    public static void saveLead(String leadData) {
        try {
            Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(leadData);
            Id b2cRecTypeId = Schema.SobjectType.Lead.getRecordTypeInfosByName().get('B2C').getRecordTypeId();

            String fullName = (String) dataMap.get('Name');
            String firstName = parseFirstName(fullName);
            String lastName = parseLastName(fullName);

            Lead newLead = new Lead();
            newLead.RecordTypeId = b2cRecTypeId;
            newLead.FirstName = firstName;
            newLead.LastName = lastName;
            newLead.Email = (String) dataMap.get('Email');
            newLead.Phone = (String) dataMap.get('Phone');
            newLead.State = (String) dataMap.get('State');
            newLead.City = (String) dataMap.get('City');
            newLead.LeadSource = (String) dataMap.get('LeadSource');

            //newLead.Company = 'Individual';
            newLead.Status = 'Open - Not Contacted';
            newLead.XS_Programme__c = (String) dataMap.get('Program');
            String programCode = (String)dataMap.get('Program');
            if (String.isNotBlank(programCode)) {
                Program prog = [
                    SELECT Id 
                    FROM Program 
                    WHERE Program_Code__c = :programCode 
                    LIMIT 1
                ];
                if (prog != null) {
                    newLead.Program_Master__c = prog.Id;
                }
            }

            insert newLead;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating lead: ' + e.getMessage());
        }
    }

    private static String parseFirstName(String fullName) {
        if (String.isBlank(fullName)) return '';
        String[] parts = fullName.trim().split(' ');
        return (parts.size() > 1) ? parts[0] : '';
    }

    private static String parseLastName(String fullName) {
        if (String.isBlank(fullName)) return 'Unknown';
        String[] parts = fullName.trim().split(' ');
        return (parts.size() == 1) ? parts[0] : parts[parts.size() - 1];
    }


    @AuraEnabled(cacheable=true)
    public static BrochureResponse getBrochureData(String programCode) {
        Program prog = [
            SELECT Id, Brochure_URL__c,Brochure_Thank_You_Information__c
            FROM Program
            WHERE Program_Code__c = :programCode
            LIMIT 1
        ];
        BrochureResponse response = new BrochureResponse();
        response.brochureUrl = prog.Brochure_URL__c;
        response.thankYouText = prog.Brochure_Thank_You_Information__c;
        return response;
    }
}
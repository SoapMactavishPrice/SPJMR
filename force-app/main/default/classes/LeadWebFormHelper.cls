public without sharing class LeadWebFormHelper {
    
    
    
    @AuraEnabled
    public static String submitForm(Map<String, Object> formData, String programCode) {
        try{
            Lead l = new Lead();
            
         
            if(formData.containsKey('FirstName')) {
                l.FirstName = (String) formData.get('FirstName');
            }
            
            if(formData.containsKey('Email')) {
                l.Email = (String) formData.get('Email');
            }
            
            if(formData.containsKey('Phone')) {
                l.Phone = (String) formData.get('Phone');
            }
            
            l.Company = 'Website';
            
            String firstName = (String) formData.get('FirstName');
            String email     = (String) formData.get('Email');
            String phone     = (String) formData.get('Phone');
            
            if (String.isBlank(firstName) || String.isBlank(email) || String.isBlank(phone)) {
                throw new AuraHandledException('Name, Email and Phone are mandatory');
            }
            
          
            Program programRec = [
            SELECT Id, Name
            FROM Program
            WHERE Program_Code__c = :programCode
            LIMIT 1
        ];
            
            if (programRec == null) {
                throw new AuraHandledException('Invalid Program');
            }
            
            List<Account> accList = [
            SELECT Id, FirstName
            FROM Account
            WHERE PersonEmail = :email
            OR PersonMobilePhone = :phone
            LIMIT 1
        ];
            
            if (!accList.isEmpty()) {
                
                Account acc = accList[0];
                
                Opportunity opp = new Opportunity();
                opp.AccountId = acc.Id;
                opp.Name = firstName + ' - ' + programRec.Name;
                opp.StageName = 'Prospecting';
                opp.CloseDate = Date.today().addDays(30);
                opp.Program__c = programRec.Id;
                
                insert opp;
                
                return 'Created Opportunity for already existing account with Id:'+opp.Id;
            }
            
            List<Lead> leadList = [
            SELECT Id, IsConverted
            FROM Lead
            WHERE Email = :email
            OR Phone = :phone
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
            
            if (!leadList.isEmpty()) {
                
                Lead existingLead = leadList[0];
                
                if (!existingLead.IsConverted) {
                    
                    List<Lead_Program__c> lpList = [
            SELECT Id
            FROM Lead_Program__c
            WHERE Lead__c = :existingLead.Id
            AND Program__c = :programRec.Id
            AND Email__c = :email
            AND Phone__c = :phone
            LIMIT 1
        ];
                    
                    if (lpList.isEmpty()) {
                        
                        Lead_Program__c lp = new Lead_Program__c();
                        lp.Lead__c = existingLead.Id;
                        lp.Program__c = programRec.Id;
                        lp.Email__c = email;
                        lp.Phone__c = phone;
                        
                        insert lp;
                        
                        return 'Lead exists, created LP: ' + lp.Id;
                    }
                    
                    return 'Lead exists, LP already present';
                }
                
                return 'Lead already converted';
            }
            
            
            Lead newLead = new Lead();
            
            Id b2cRecTypeId = Schema.SObjectType.Lead
                .getRecordTypeInfosByName()
                .get('B2C')
                .getRecordTypeId();
            
            Lead applicant = new Lead();
            
            applicant.RecordTypeId = b2cRecTypeId;
            applicant.LeadSource   = 'Website';
            applicant.Company      = 'Website';
            
           
            List<String> nameParts = firstName.split(' ');
            applicant.FirstName = nameParts.size() > 0 ? nameParts[0] : '';
            applicant.LastName  = nameParts.size() > 1 ? nameParts[1] : '.';
            
            applicant.Email = email;
            applicant.Phone = phone;
            String country = (String) formData.get('Country');
            
            if (String.isBlank(country)) {
                country = 'India';
            }
            
            List<Country_Master__c> countryList = [
    SELECT Id FROM Country_Master__c WHERE Name = :country LIMIT 1
];
            
            applicant.Country_Master_backend__c =
                countryList.isEmpty() ? null : countryList[0].Id;
            
            
            String state = (String) formData.get('State');
            String city  = (String) formData.get('City');
            
            if (String.isNotBlank(state) && applicant.Country_Master_backend__c != null) {
                
                List<State__c> stateList = [
        SELECT Id FROM State__c 
        WHERE Name = :state 
        AND Country_Master__c = :applicant.Country_Master_backend__c
        LIMIT 1
    ];
                
                if (!stateList.isEmpty()) {
                    applicant.State_Master__c = stateList[0].Id;
                    
                    if (String.isNotBlank(city)) {
                        List<City__c> cityList = [
                SELECT Id FROM City__c
                WHERE State__c = :stateList[0].Id
                            AND Name = :city
                            LIMIT 1
                            ];
                        
                        applicant.District_City__c =
                            cityList.isEmpty() ? null : cityList[0].Id;
                    }
                }
            }
            
            applicant.XS_State__c = (String) formData.get('State');
            applicant.XS_City__c  = (String) formData.get('City');
            
            applicant.XS_YearsOfWorkExperience__c =
                (String) formData.get('Work_Experience__c');
            
            applicant.XS_HaveYouCompletedYourGraduation__c =
                (String) formData.get('Graduation__c');
            
            applicant.XS_EntranceExamName__c =
                (String) formData.get('Entrance_Exam_Name__c');
            
            applicant.XS_CurrentEmployer__c =
                (String) formData.get('Current_Employer__c');
            
            applicant.XS_CurrentDesigination__c =
                (String) formData.get('Current_Designation__c');
            
            applicant.XS_EnterOrganisation__c  =
                (String) formData.get('Current_Organization__c');
            
            applicant.Other_Enquiry__c  =
                (String) formData.get('Query__c');
            
            
            applicant.Program_Master__c = programRec.Id;
            
            insert applicant;
            
            
            Lead_Program__c newLP = new Lead_Program__c();
            newLP.Lead__c = applicant.Id;
            newLP.Program__c = programRec.Id;
            newLP.Email__c = email;
            newLP.Phone__c = phone;
            
            insert newLP;
            
            return 'Successfully createad Lead with Id:'+applicant.Id+' and Lead Program Id:'+newLP.Id;
            
        }
        catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String,Boolean> getVisibilityConfig(String programCode) {
        
        Map<String, Boolean> visibilityMap = new Map<String, Boolean>();
        
        for (SPJIMR_Web2Lead_Field_Visibility__mdt md : [
            SELECT FieldName__c, Is_Visible__c
            FROM SPJIMR_Web2Lead_Field_Visibility__mdt
            WHERE ProgramCode__c = :programCode
        ]) {
            visibilityMap.put(md.FieldName__c, md.Is_Visible__c);
        }
        
        return visibilityMap;
    }
    
    @AuraEnabled
    public static Map<String, Object> verifyToken(String token) {
        // It's highly recommended to move this key to a custom setting or custom metadata for security purposes.
        String SECRET_KEY = '6LeF5JcsAAAAAGjXTcrEprDPKdb-vc8pcAZjStJk';//replace the SECRET_KEY generated in step 1
        String RECAPTCHA_SERVICE_URL = 'https://www.google.com/recaptcha/api/siteverify';
        String response;
        Map<String, Object> result = new Map<String, Object>();
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint(RECAPTCHA_SERVICE_URL);
        request.setMethod('POST');
        // Properly formatting the body of the POST request.
        request.setBody('secret=' + EncodingUtil.urlEncode(SECRET_KEY, 'UTF-8') + '&response=' + EncodingUtil.urlEncode(token, 'UTF-8'));
        
        Http http = new Http();
        
        try {
            HttpResponse httpResponse = http.send(request);
            response = httpResponse.getBody();
            System.debug('Response: ' + response);
            
            result = (Map<String, Object>) JSON.deserializeUntyped(response);
            
            if (result.containsKey('success') && (Boolean) result.get('success')) {
                // Check the score and return success or error based on your score threshold.
                // Note: reCAPTCHA v3 uses a score. For v2, you may simply rely on the success boolean.
                Double score = (result.get('score') != null) ? (Double) result.get('score') : null;
                
                if (score != null && score >= 0.5) {
                    system.debug('Score satisfied and more than 0.5');
                    return new Map<String, Object>{'success' => true};
                }
                else {
                    system.debug('Score not satisfied and less than 0.5');
                    return new Map<String, Object>{'success' => false, 'message' => 'Verification failed: Score is too low or not applicable'};
                }
            }
            else {
                // If there's no 'success' key or if it's not true, return the failure message
                system.debug('There is no success key in result');
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Verification failed: ' + (result.containsKey('error-codes') ? String.valueOf(result.get('error-codes')) : 'Unknown error')
                };
            }
        }
        catch (Exception e) {
            return new Map<String, Object>{'success' => false, 'message' => 'Failed to verify reCAPTCHA token: ' + e.getMessage()};
        }
    }
}
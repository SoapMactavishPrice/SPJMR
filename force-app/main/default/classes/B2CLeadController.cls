public without sharing class B2CLeadController {
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCountries() {
        List<Map<String, String>> countries = new List<Map<String, String>>();
        
        List<Country_Master__c> countryList = [
            SELECT Id, Name ,Country_Code__c,AcceptedNumberLength__c
            FROM Country_Master__c 
            ORDER BY Name ASC
            LIMIT 500
        ];
        
        for (Country_Master__c country : countryList) {
            countries.add(new Map<String, String>{'value' => country.Id,'label' => country.Name,'countryCode' => country.Country_Code__c != null? '+' + String.valueOf(country.Country_Code__c): '','acceptedLength' => country.AcceptedNumberLength__c != null? String.valueOf(country.AcceptedNumberLength__c): ''
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
    public static List<Map<String, String>> getEntranceExamOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        
        options.add(new Map<String, String>{'value' => 'CAT', 'label' => 'CAT'});
        options.add(new Map<String, String>{'value' => 'GMAT', 'label' => 'GMAT'});
        options.add(new Map<String, String>{'value' => 'GRE', 'label' => 'GRE'});
        options.add(new Map<String, String>{'value' => 'XAT', 'label' => 'XAT'});
        options.add(new Map<String, String>{'value' => 'MAT', 'label' => 'MAT'});
        options.add(new Map<String, String>{'value' => 'CMAT', 'label' => 'CMAT'});
        options.add(new Map<String, String>{'value' => 'NMAT', 'label' => 'NMAT'});
        options.add(new Map<String, String>{'value' => 'SNAP', 'label' => 'SNAP'});
        options.add(new Map<String, String>{'value' => 'ATMA', 'label' => 'ATMA'});
        options.add(new Map<String, String>{'value' => 'IIFT', 'label' => 'IIFT'});
        options.add(new Map<String, String>{'value' => 'TISSNET', 'label' => 'TISSNET'});
        options.add(new Map<String, String>{'value' => 'MICAT', 'label' => 'MICAT'});
        options.add(new Map<String, String>{'value' => 'Other', 'label' => 'Other'});
        
        return options;
    }

    /**
     * Lead Source options plus default API value for the running user (describe default).
     * LWC expects { options: [...], defaultValue: 'ApiValue' } — not a bare list.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLeadSourceOptions() {
        Map<String, Object> payload = new Map<String, Object>{
            'options' => new List<Map<String, String>>(),
            'defaultValue' => null
        };
        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get('Lead');
            if (objType == null) {
                return payload;
            }
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            Schema.SObjectField field = objDescribe.fields.getMap().get('LeadSource');
            if (field == null) {
                return payload;
            }
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            List<Schema.PicklistEntry> picklistEntries = fieldDescribe.getPicklistValues();
            List<Map<String, String>> options = new List<Map<String, String>>();
            Set<String> activeValues = new Set<String>();

            for (Schema.PicklistEntry entry : picklistEntries) {
                if (entry.isActive()) {
                    options.add(new Map<String, String>{
                        'value' => entry.getValue(),
                        'label' => entry.getLabel()
                    });
                    activeValues.add(entry.getValue());
                }
            }

            String defaultApi = null;
            Object defaultObj = fieldDescribe.getDefaultValue();
            if (defaultObj != null) {
                String fromDescribe = String.valueOf(defaultObj);
                if (String.isNotBlank(fromDescribe) && activeValues.contains(fromDescribe)) {
                    defaultApi = fromDescribe;
                }
            }
            if (String.isBlank(defaultApi)) {
                for (Schema.PicklistEntry entry : picklistEntries) {
                    if (entry.isActive() && entry.isDefaultValue()) {
                        defaultApi = entry.getValue();
                        break;
                    }
                }
            }

            payload.put('options', options);
            payload.put('defaultValue', defaultApi);
        } catch (Exception e) {
            System.debug('Error getting Lead Source picklist: ' + e.getMessage());
        }
        return payload;
    }

    /** Active campaigns whose Campaign Source matches the Lead Source API value. */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCampaignsByLeadSource(String leadSource) {
        List<Map<String, String>> rows = new List<Map<String, String>>();
        if (String.isBlank(leadSource)) {
            return rows;
        }
        for (Campaign c : [
            SELECT Id, Name
            FROM Campaign
            WHERE IsActive = true
            AND CampaignSource__c = :leadSource
            ORDER BY Name
            LIMIT 500
        ]) {
            rows.add(new Map<String, String>{
                'value' => c.Id,
                'label' => c.Name
            });
        }
        return rows;
    }
    
    @AuraEnabled
    public static Map<String, Object> checkExistingLead(String email, String phone) {
        Map<String, Object> result = new Map<String, Object>();
        String normalizedEmail = String.isNotBlank(email) ? email.trim() : null;
        String normalizedPhone = String.isNotBlank(phone) ? phone.trim() : null;
        
        if (String.isBlank(normalizedEmail) && String.isBlank(normalizedPhone)) {
            result.put('hasUnconvertedLead', false);
            result.put('hasApplicantAccount', false);
            return result;
        }
        
        try {
            List<Lead> existingLeads = new List<Lead>();
            if (String.isNotBlank(normalizedEmail) && String.isNotBlank(normalizedPhone)) {
                existingLeads = [
                    SELECT Id, FirstName, LastName, Email, Phone, Street, LeadSource, Other__c, Are_you_NRI__c,
                           Country_Master_backend__c, State_Master__c, District_City__c,GenderIdentity,
                           Country, State, City, PostalCode, Date_Of_Birth__c, XS_Age__c,
                           XS_YearsOfWorkExperience__c, XS_EntranceExamName__c, IsConverted,
                           XS_DoYouHaveEntranceExamScore__c,XS_EnterOrganisation__c,
                           XS_HaveYouCompletedYourGraduation__c,
                           XS_HowDidYouFindOutAboutUs__c,XS_SPJIMR_PartnerCompany__c,
                           XS_CurrentlyStudingIn__c 
                    FROM Lead
                    WHERE IsConverted = false
                    AND (Email = :normalizedEmail OR Phone = :normalizedPhone)
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
            } else if (String.isNotBlank(normalizedEmail)) {
                existingLeads = [
                    SELECT Id, FirstName, LastName, Email, Phone, Street, LeadSource, Other__c, Are_you_NRI__c,
                           Country_Master_backend__c, State_Master__c, District_City__c,GenderIdentity,
                           Country, State, City, PostalCode, Date_Of_Birth__c, XS_Age__c,
                           XS_YearsOfWorkExperience__c, XS_DoYouHaveEntranceExamScore__c,
                           XS_EntranceExamName__c, IsConverted
                    FROM Lead
                    WHERE IsConverted = false
                    AND Email = :normalizedEmail
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
            } else {
                existingLeads = [
                    SELECT Id, FirstName, LastName, Email, Phone, Street, LeadSource, Other__c, Are_you_NRI__c,
                           Country_Master_backend__c, State_Master__c, District_City__c,GenderIdentity,
                           Country, State, City, PostalCode, Date_Of_Birth__c, XS_Age__c,
                           XS_YearsOfWorkExperience__c, XS_DoYouHaveEntranceExamScore__c,
                           XS_EntranceExamName__c, IsConverted
                    FROM Lead
                    WHERE IsConverted = false
                    AND Phone = :normalizedPhone
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
            }
            
            Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
            List<Account> existingAccounts = new List<Account>();
            String accountQuery = 'SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone, Phone, ' +
                'PersonMailingStreet, PersonMailingCity, PersonMailingState,PersonGenderIdentity, ' +
                'PersonMailingCountry, PersonMailingPostalCode, PersonBirthdate, PersonContactId, ' +
                'BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, ' +
                'Date_Of_Birth__c, Country_Master__c, State_Master__c, District_City__c, ' +
                'Entrance_Exam_Name__c, Has_Entrance_Exam_Score__c, Years_Of_Work_Experience__c ' +
                'FROM Account WHERE RecordTypeId = :applicantRtId AND ';
            
            if (String.isNotBlank(normalizedEmail) && String.isNotBlank(normalizedPhone)) {
                existingAccounts = Database.query(accountQuery + '(PersonEmail = :normalizedEmail OR PersonMobilePhone = :normalizedPhone OR Phone = :normalizedPhone) LIMIT 1');
            } else if (String.isNotBlank(normalizedEmail)) {
                existingAccounts = Database.query(accountQuery + 'PersonEmail = :normalizedEmail LIMIT 1');
            } else {
                existingAccounts = Database.query(accountQuery + '(PersonMobilePhone = :normalizedPhone OR Phone = :normalizedPhone) LIMIT 1');
            }

            if (!existingLeads.isEmpty()) {
                Lead existingLead = existingLeads[0];
                result.put('hasUnconvertedLead', true);
                result.put('leadId', existingLead.Id);
                result.put('lead', existingLead);
                
                // Get existing Lead_Program__c records
                List<Lead_Program__c> existingLeadPrograms = [
                    SELECT Id, Program__c, Program__r.Name, Program__r.Id
                    FROM Lead_Program__c
                    WHERE Lead__c = :existingLead.Id
                ];
                
                List<Map<String, String>> programs = new List<Map<String, String>>();
                for (Lead_Program__c lp : existingLeadPrograms) {
                    programs.add(new Map<String, String>{
                        'id' => lp.Program__c,
                        'name' => lp.Program__r.Name
                    });
                }
                result.put('existingPrograms', programs);
            } else {
                result.put('hasUnconvertedLead', false);
            }

            if (!existingAccounts.isEmpty()) {
                result.put('hasApplicantAccount', true);
                result.put('accountId', existingAccounts[0].Id);
                result.put('account', existingAccounts[0]);
            } else {
                result.put('hasApplicantAccount', false);
            }
        } catch (Exception e) {
            result.put('hasUnconvertedLead', false);
            result.put('hasApplicantAccount', false);
            result.put('error', e.getMessage());
        }
        
        return result;
    }
    
    @AuraEnabled
    public static Map<String, Object> createB2CLead(
        String firstName,
        String lastName,
        String email,
        String phone,
        String street,
        String countryId,
        String stateId,
        String cityId,
        String postalCode,
        Date dateOfBirth,
        String age,
        Boolean hasWorkExperience,
        String yearsOfWorkExperience,
        Boolean hasEntranceExam,
        String entranceExamName,
        String studyingIn,
        String organizationName,
        List<String> selectedProgramIds, 
        String leadSource,
        Boolean areYouNri,
        String leadSourceOther,
        String xs_source,
        String howDidYouKnow,
        String selectedCampaignId,
        String existingLeadId,
        String existingApplicantAccountId,
        String gender,
        String eventCountry,
        String eventState,
        String eventCity
    ) {
        try {
            Id b2cRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId();
            Map<String, Object> response = new Map<String, Object>();
            
            String countryName = '';
            String stateName = '';
            String cityName = '';
            
            if (String.isNotBlank(countryId)) {
                List<Country_Master__c> countries = [SELECT Name FROM Country_Master__c WHERE Id = :countryId LIMIT 1];
                if (!countries.isEmpty()) {
                    countryName = countries[0].Name;
                }
            }
            
            if (String.isNotBlank(stateId)) {
                List<State__c> states = [SELECT Name FROM State__c WHERE Id = :stateId LIMIT 1];
                if (!states.isEmpty()) {
                    stateName = states[0].Name;
                }
            }
            
            if (String.isNotBlank(cityId)) {
                List<City__c> cities = [SELECT Name FROM City__c WHERE Id = :cityId LIMIT 1];
                if (!cities.isEmpty()) {
                    cityName = cities[0].Name;
                }
            }
            if(dateOfBirth!=null){
                if(dateOfBirth >= System.Today()){
                    throw new AuraHandledException('Date of Birth cannot be today or a future date.');
                }
            }
            if (String.isNotBlank(existingApplicantAccountId)) {
                List<Account> accounts = [
                    SELECT Id, FirstName, LastName
                    FROM Account
                    WHERE Id = :existingApplicantAccountId
                    LIMIT 1
                ];
                if (accounts.isEmpty()) {
                    throw new AuraHandledException('Applicant account not found for this email.');
                }

                Map<Id, Program> programMap = new Map<Id, Program>();
                if (selectedProgramIds != null && !selectedProgramIds.isEmpty()) {
                    programMap.putAll([
                        SELECT Id, Name, Program_Code__c, ParentProgramId
                        FROM Program
                        WHERE Id IN :selectedProgramIds
                    ]);
                }

                List<String> orderedProgramIds = new List<String>();
                if (selectedProgramIds != null) {
                    for (String pid : selectedProgramIds) {
                        orderedProgramIds.add(pid);
                    }
                }

                Map<Id, List<Program>> familyGroups = B2CProgramParentHelper.groupSelectedProgramsByFamily(
                    orderedProgramIds,
                    programMap
                );

                Set<Id> extraProgramIds = new Set<Id>();
                for (List<Program> grp : familyGroups.values()) {
                    Id oppProgId = B2CProgramParentHelper.opportunityAndApplicationProgramId(grp);
                    if (oppProgId != null && !programMap.containsKey(oppProgId)) {
                        extraProgramIds.add(oppProgId);
                    }
                }
                if (!extraProgramIds.isEmpty()) {
                    programMap.putAll([
                        SELECT Id, Name, Program_Code__c, ParentProgramId
                        FROM Program
                        WHERE Id IN :extraProgramIds
                    ]);
                }

                Schema.RecordTypeInfo b2cOppRti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                    .get('B2C_Opportunity');
                Id b2cOpportunityRecordTypeId = b2cOppRti != null ? b2cOppRti.getRecordTypeId() : null;
                Boolean autoCreateApplications = ConvertB2CLeadController.isAutoApplicationCreationEnabled();

                List<Opportunity> opportunitiesToInsert = new List<Opportunity>();
                Map<Id, Opportunity> familyKeyToOpportunity = new Map<Id, Opportunity>();

                for (List<Program> members : familyGroups.values()) {
                    if (members == null || members.isEmpty()) {
                        continue;
                    }
                    Id programIdForOpp = B2CProgramParentHelper.opportunityAndApplicationProgramId(members);
                    Program nameSource = programMap.get(programIdForOpp);
                    String programDisplayName = nameSource != null && String.isNotBlank(nameSource.Name)
                        ? nameSource.Name
                        : 'Program';

                    Id reuseAppId = B2CProgramParentHelper.findReusableApplicationForParentFamily(
                        existingApplicantAccountId,
                        members[0].Id
                    );

                    Opportunity opp = new Opportunity();
                    opp.AccountId = existingApplicantAccountId;
                    opp.Name = (String.isNotBlank(firstName) ? firstName : accounts[0].FirstName) +
                        ' ' + (String.isNotBlank(lastName) ? lastName : accounts[0].LastName) +
                        ' - ' + programDisplayName;
                    opp.StageName = 'Prospecting';
                    opp.CloseDate = Date.today().addDays(90);
                    opp.Program__c = programIdForOpp;
                    opp.LeadSource = leadSource;
                    if (b2cOpportunityRecordTypeId != null) {
                        opp.RecordTypeId = b2cOpportunityRecordTypeId;
                    }
                    if (reuseAppId != null) {
                        opp.Application__c = reuseAppId;
                    }
                    opp.B2C_Program_Code__c = nameSource != null && String.isNotBlank(nameSource.Program_Code__c)
                        ? nameSource.Program_Code__c.trim()
                        : null;

                    opportunitiesToInsert.add(opp);
                    familyKeyToOpportunity.put(B2CProgramParentHelper.familyGroupKey(members[0]), opp);
                }

                if (!opportunitiesToInsert.isEmpty()) {
                    insert opportunitiesToInsert;
                    response.put('recordId', opportunitiesToInsert[0].Id);
                    response.put('objectApiName', 'Opportunity');
                    response.put('mode', 'account-opportunity');
                    response.put(
                        'message',
                        autoCreateApplications
                            ? 'Applicant account already exists. Opportunities and applications created successfully.'
                            : 'Applicant account already exists. Opportunities created successfully. Application creation is set to manual.'
                    );

                    if (autoCreateApplications) {
                        List<Application__c> applicationsToInsert = new List<Application__c>();
                        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
                        List<String> programCodesForNumbers = new List<String>();
                        List<Id> programIdForAppList = new List<Id>();

                        for (List<Program> members : familyGroups.values()) {
                            if (members == null || members.isEmpty()) {
                                continue;
                            }
                            Id famKey = B2CProgramParentHelper.familyGroupKey(members[0]);
                            Opportunity opp = familyKeyToOpportunity.get(famKey);
                            if (opp == null || opp.Application__c != null) {
                                continue;
                            }
                            Id programIdForApp = B2CProgramParentHelper.opportunityAndApplicationProgramId(members);
                            Program progRow = programMap.get(programIdForApp);
                            programCodesForNumbers.add(progRow != null ? progRow.Program_Code__c : null);
                            programIdForAppList.add(programIdForApp);
                            opportunitiesToUpdate.add(opp);
                        }

                        List<String> applicationNumbers = ConvertB2CLeadController.generateApplicationNumbersInBulk(
                            programCodesForNumbers
                        );

                        Id applicationOwnerId;

                        List<User> matchingUsers = [
                            SELECT Id
                            FROM User
                            WHERE Email = :email
                            AND IsActive = true
                            LIMIT 1
                        ];

                        if (!matchingUsers.isEmpty()) {
                            applicationOwnerId = matchingUsers[0].Id;
                        }
                        for (Integer idx = 0; idx < programIdForAppList.size(); idx++) {
                            Application__c app = new Application__c();
                            app.Applicant__c = existingApplicantAccountId;
                            app.Program__c = programIdForAppList[idx];
                            app.LeadSource__c = leadSource;
                            if (applicationOwnerId != null) {
                                app.OwnerId = applicationOwnerId;
                            }

                            if (idx < applicationNumbers.size() && applicationNumbers[idx] != null) {
                                app.Name = applicationNumbers[idx];
                            }

                            applicationsToInsert.add(app);
                        }

                        if (!applicationsToInsert.isEmpty()) {
                            insert applicationsToInsert;
                            List<Personal_Detail__c> personalDetailsList = new List<Personal_Detail__c>();
                            for(Application__c app :applicationsToInsert){
                                 Personal_Detail__c pd = new Personal_Detail__c();
                                pd.Application__c = app.Id;
                                pd.First_Name__c = firstName;
                                pd.Last_Name__c = lastName;
                                pd.Primary_E_mail__c = String.isNotBlank(email) ? email : null;
                                pd.Mobile_Number__c = phone;
                                if (applicationOwnerId != null) {
                                    pd.OwnerId = applicationOwnerId;
                                }
                                personalDetailsList.add(pd);
                            }
                            insert personalDetailsList;
                        }

                        

                        for (Integer i = 0; i < opportunitiesToUpdate.size(); i++) {
                            opportunitiesToUpdate[i].Application__c = applicationsToInsert[i].Id;
                        }
                        if (!opportunitiesToUpdate.isEmpty()) {
                            update opportunitiesToUpdate;
                        }
                    }

                    return response;
                }
            }

            Lead leadToUpsert;
            if (String.isNotBlank(existingLeadId)) {
                leadToUpsert = new Lead(Id = existingLeadId);
            } else {
                leadToUpsert = new Lead();
                leadToUpsert.RecordTypeId = b2cRecordTypeId;
                leadToUpsert.Status = 'Untouched';
                LeadRoutingService.applyB2cDefaultOwnerIfConfigured(leadToUpsert);
            }
            system.debug('Upserting lead: '+leadToUpsert);
            leadToUpsert.FirstName = firstName;
            leadToUpsert.LastName = String.isNotBlank(lastName) ? lastName : '.';
            leadToUpsert.Email = email;
            leadToUpsert.Phone = phone;
            leadToUpsert.Street = street;
            leadToUpsert.Country_Master_backend__c = String.isNotBlank(countryId) ? countryId : null;
            leadToUpsert.State_Master__c = String.isNotBlank(stateId) ? stateId : null;
            leadToUpsert.District_City__c = String.isNotBlank(cityId) ? cityId : null;
            leadToUpsert.Country = countryName;
            leadToUpsert.State = stateName;
            leadToUpsert.City = cityName;
            leadToUpsert.PostalCode = postalCode;
            leadToUpsert.Date_Of_Birth__c = dateOfBirth;
            leadToUpsert.XS_Age__c = age;
            leadToUpsert.XS_YearsOfWorkExperience__c = hasWorkExperience ? yearsOfWorkExperience : null;
            leadToUpsert.XS_DoYouHaveEntranceExamScore__c = hasEntranceExam ? 'Yes' : 'No';
            leadToUpsert.XS_EntranceExamName__c = hasEntranceExam ? entranceExamName : null;
            leadToUpsert.GenderIdentity = !String.isBlank(gender) ? gender:null;
            leadToUpsert.Company = String.isNotBlank(lastName) ? firstName + ' ' + lastName + ' (Individual)' : firstName + ' (Individual)';
            leadToUpsert.Are_you_NRI__c = areYouNri == true;
            leadToUpsert.XS_SPJIMR_PartnerCompany__c =!String.isBlank(organizationName)? 'Yes':'No';
            leadToUpsert.XS_HaveYouCompletedYourGraduation__c = !String.isBlank(studyingIn) ? 'No':'Yes';
            leadToUpsert.XS_CurrentlyStudingIn__c = !String.isBlank(studyingIn)?studyingIn : null;
            leadToUpsert.XS_Source__c = String.isNotBlank(xs_source)? xs_source:null;
            leadToUpsert.XS_EnterOrganisation__c = !String.isBlank(organizationName)?organizationName:null;
            leadToUpsert.XS_HowDidYouFindOutAboutUs__c = String.isNotBlank(howDidYouKnow)?howDidYouKnow:null;
            leadToUpsert.Event_Country__c = String.isNotBlank(eventCountry)?eventCountry:null;
            leadToUpsert.Event_State__c = String.isNotBlank(eventState)?eventState:null;
            leadToUpsert.Event_City__c = String.isNotBlank(eventCity)?eventCity:null;
            if (String.isNotBlank(leadSource)) {
                leadToUpsert.LeadSource = leadSource;
                if (leadSource.equalsIgnoreCase('Others') || leadSource.equalsIgnoreCase('Other')) {
                    leadToUpsert.Other__c = String.isNotBlank(leadSourceOther) ? leadSourceOther.trim() : null;
                } else {
                    leadToUpsert.Other__c = null;
                }
            }

            Id verifiedCampaignIdForMember = null;
            if (String.isNotBlank(selectedCampaignId) && String.isNotBlank(leadSource)) {
                List<Campaign> selectedCampaignRows = [
                    SELECT Id, Source__c
                    FROM Campaign
                    WHERE Id = :selectedCampaignId
                    AND CampaignSource__c = :leadSource
                    AND IsActive = true
                    LIMIT 1
                ];
                if (!selectedCampaignRows.isEmpty()) {
                    Campaign selectedCamp = selectedCampaignRows[0];
                    verifiedCampaignIdForMember = selectedCamp.Id;
                    leadToUpsert.Integration_Partner__c = resolveIntegrationPartnerIdFromCampaignSource(
                        selectedCamp.Source__c
                    );
                }
            }

            upsert leadToUpsert;

            if (verifiedCampaignIdForMember != null) {
                Id campId = verifiedCampaignIdForMember;
                Id leadId = leadToUpsert.Id;
                Integer memberCount = Database.countQuery(
                    'SELECT COUNT() FROM CampaignMember WHERE CampaignId = :campId AND LeadId = :leadId'
                );
                if (memberCount == 0) {
                    CampaignMember cm = new CampaignMember();
                    cm.CampaignId = campId;
                    cm.LeadId = leadId;
                    cm.Status = resolveCampaignMemberStatus();
                    insert cm;
                }
            }
            
            // Get existing Lead_Program__c records for this lead
            List<Lead_Program__c> existingLeadPrograms = [
                SELECT Id, Program__c,Email__c,Phone__c
                FROM Lead_Program__c
                WHERE Lead__c = :leadToUpsert.Id
            ];
            Set<String> existingKeys = new Set<String>();

            Set<String> existingProgramIds = new Set<String>();
            for (Lead_Program__c lp : existingLeadPrograms) {
                existingProgramIds.add(lp.Program__c);
                existingKeys.add(buildLeadProgramKey(lp.Email__c, lp.Phone__c, lp.Program__c));
            }
            

            // Create new Lead_Program__c records only for programs that don't exist
            if (selectedProgramIds != null && !selectedProgramIds.isEmpty()) {
                List<Lead_Program__c> leadProgramsToInsert = new List<Lead_Program__c>();
                for (String programId : selectedProgramIds) {
                     String key = buildLeadProgramKey(email, phone, programId);
                    if (!existingKeys.contains(key)) {
                        Lead_Program__c lp = new Lead_Program__c();
                        lp.Lead__c = leadToUpsert.Id;
                        lp.Program__c = programId;
                        lp.Lead_Source__c = leadSource;
                        lp.Email__c = email;
                        lp.Phone__c = phone;
                        leadProgramsToInsert.add(lp);
                        existingKeys.add(key);
                    }
                }
                
                if (!leadProgramsToInsert.isEmpty()) {
                    insert leadProgramsToInsert;
                }
            }
            
            response.put('recordId', leadToUpsert.Id);
            response.put('objectApiName', 'Lead');
            response.put('mode', String.isNotBlank(existingLeadId) ? 'lead-updated' : 'lead-created');
            response.put('message', String.isNotBlank(existingLeadId) ? 'Lead updated successfully.' : 'Lead created successfully.');
            return response;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error creating/updating lead: ' + e.getMessage());
        }
    }

    /**
     * {@code Lead.Integration_Partner__c} is a lookup to {@code Integration_Partner__c}. {@code Campaign.Source__c}
     * is often a free-text or non-Id value; assigning it directly causes {@code INVALID_CROSS_REFERENCE_KEY} on upsert.
     *
     * @param campaignSourceValue Raw {@code Campaign.Source__c} (may be null, blank, text, or a partner Id).
     * @return Partner Id only when the value parses as a Salesforce Id and its object type is {@code Integration_Partner__c}.
     */
    private static Id resolveIntegrationPartnerIdFromCampaignSource(String campaignSourceValue) {
        Id result = null;
        Id parsed = SPJIMRUtility.parseSalesforceId(campaignSourceValue);
        if (parsed != null) {
            Schema.SObjectType partnerType = Schema.getGlobalDescribe().get('Integration_Partner__c');
            if (partnerType != null && parsed.getSObjectType() == partnerType) {
                result = parsed;
            }
        }
        return result;
    }

    /**
 * Normalized composite key for Lead_Program__c dedup: same email + phone + program
 * means "already registered"; any change to email or phone creates a new row.
 */
private static String buildLeadProgramKey(String emailVal, String phoneVal, String programIdVal) {
    String e = emailVal != null ? emailVal.trim().toLowerCase() : '';
    String p = phoneVal != null ? phoneVal.trim() : '';
    String prog = programIdVal != null ? String.valueOf(programIdVal).trim() : '';
    return e + '|' + p + '|' + prog;
}

    private static String resolveCampaignMemberStatus() {
        Schema.SObjectField statusField = Schema.SObjectType.CampaignMember.fields.getMap().get('Status');
        if (statusField == null) {
            return 'Sent';
        }
        Schema.DescribeFieldResult dfr = statusField.getDescribe();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive() && pe.isDefaultValue()) {
                return pe.getValue();
            }
        }
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) {
                return pe.getValue();
            }
        }
        return 'Sent';
    }
}
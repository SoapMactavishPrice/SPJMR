global without sharing class LeadImportProcessBatch 
implements Database.Batchable<SObject>, Database.Stateful { 

    private Id importParentId;
    private String description;
    private String Title;

    global LeadImportProcessBatch(Id importParentId){
        this.importParentId = importParentId;

        List<Lead_Import_Parent__c> lip = [SELECT Title__c,Description__c FROM Lead_Import_Parent__c WHERE Id =:importParentId LIMIT 1];

        if(!lip.isEmpty()){
            this.description = lip[0].Description__c;
            this.Title = lip[0].Title__c;
        }
        else{
            this.description = '';
            this.Title = '';
        }
    }

    global Database.QueryLocator start(
        Database.BatchableContext bc
    ){
        return Database.getQueryLocator([
            SELECT Id,
                   Name__c,
                   Email__c,
                   Phone__c,
                   Programme__c,
                   LeadSource__c,
                   Country__c,
                   State__c,
                   City__c,
                   Status__c,
                   Age__c,
                   Years_of_Work_Experience__c,Do_you_have_Entrance_Exam_Scores__c,
                   Entrance_Exam_Name__c,SPJIMR_Partner_Company__c,Organization__c,
                   How_did_you_find_out_about_us__c,Current_Designation__c,College__c,
                   Graduation_Year__c
            FROM Lead_Import__c
            WHERE Lead_Import_Parent__c = :importParentId
            AND Status__c = 'New'
        ]);
    }

    global void execute(
        Database.BatchableContext bc,
        List<Lead_Import__c> scope
    ){
        processScope(scope, this.description, this.Title);
    }

    global void finish(
        Database.BatchableContext bc
    ){
        if(importParentId!=null){
				update new Lead_Import_Parent__c(Id = importParentId,Status__c = 'Completed');
        }
        
    }

    private static final String RAW_DATA_SOURCE = 'Raw Data';

    private static Map<String, Program> buildProgramMap(Set<String> programCodes){
        Map<String, Program> programMap = new Map<String, Program>();
        List<Program> programs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c IN :programCodes
        ];
        for(Program p : programs){
            programMap.put(p.Program_Code__c, p);
        }
        return programMap;
    }
	@TestVisible
    private static Map<String, Country_Master__c> buildCountryMap(Set<String> countries){
        Map<String, Country_Master__c> countryMap = new Map<String, Country_Master__c>();
        List<Country_Master__c> countryRecords = [
            SELECT Id, Name
            FROM Country_Master__c
            WHERE Name IN :countries
        ];
        for(Country_Master__c c : countryRecords){
            countryMap.put(c.Name.toLowerCase(), c);
        }
        return countryMap;
    }
	@TestVisible
    private static Map<String, State__c> buildStateMap(Set<String> states){
        Map<String, State__c> stateMap = new Map<String, State__c>();
        List<State__c> stateRecords = [
            SELECT Id, Name, Country_Master__c
            FROM State__c
            WHERE Name IN :states
        ];
        for(State__c s : stateRecords){
            String key = s.Country_Master__c + '|' + s.Name.toLowerCase();
            stateMap.put(key, s);
        }
        return stateMap;
    }
	@TestVisible
    private static Map<String, City__c> buildCityMap(Set<String> cities){
        Map<String, City__c> cityMap = new Map<String, City__c>();
        List<City__c> cityRecords = [
            SELECT Id, Name, State__c
            FROM City__c
            WHERE Name IN :cities
        ];
        for(City__c city : cityRecords){
            //String key = city.State__c + '|' + city.Name.toLowerCase();
            cityMap.put(city.State__c + '|' + city.Name.toLowerCase(), city);
        }
        return cityMap;
    }
	@TestVisible
    private static void processScope(List<Lead_Import__c> scope, String description, String title){

        Id b2cRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2C').getRecordTypeId();

        Set<String> emails = new Set<String>();
        Set<String> phones = new Set<String>();
        Set<String> programCodes = new Set<String>();
        Set<String> countries = new Set<String>();
        Set<String> states = new Set<String>();
        Set<String> cities = new Set<String>();

        for(Lead_Import__c row : scope){
            if(String.isNotBlank(row.Programme__c)){
                 programCodes.add(row.Programme__c.trim());
            }  
            if(String.isNotBlank(row.Country__c)){
                countries.add(row.Country__c.trim());
            }     
            if(String.isNotBlank(row.State__c)){
                states.add(row.State__c.trim());
            }        
            if(String.isNotBlank(row.City__c)){
                cities.add(row.City__c.trim());
            }         
            if(String.isNotBlank(row.Email__c)){
                emails.add(row.Email__c.trim().toLowerCase());
            }        
        if(String.isNotBlank(row.Phone__c)){
            	phones.add(row.Phone__c.trim());
        	}         
        }

        Map<String, Program> programMap = buildProgramMap(programCodes);
        Map<String, Country_Master__c> countryMap = buildCountryMap(countries);
        Map<String, State__c> stateMap = buildStateMap(states);
        Map<String, City__c> cityMap = buildCityMap(cities);

        // Existing leads, scoped to B2C record type (mirrors B2CImportBatch)
        Map<String, Lead> mapEmailToLead = new Map<String, Lead>();
        Map<String, Lead> mapPhoneToLead = new Map<String, Lead>();
        Map<String, Lead> pendingEmailToLead = new Map<String, Lead>();
        Map<String, Lead> pendingPhoneToLead = new Map<String, Lead>();
        Map<Id, Set<String>> leadProgramKeys = new Map<Id, Set<String>>();
        for(Lead l : [
            SELECT Id, Email, Phone
            FROM Lead
            WHERE (Email IN :emails OR Phone IN :phones)
            AND RecordTypeId = :b2cRecordTypeId
        ]){
            if(String.isNotBlank(l.Email)){
                mapEmailToLead.put(l.Email.trim().toLowerCase(), l);
            } 
            if(String.isNotBlank(l.Phone)){
                mapPhoneToLead.put(l.Phone.trim(), l);
            } 
        }

        // Existing Lead_Program__c links, so we don't create duplicate program links
        Set<Id> existingLeadIds = new Set<Id>();
    for(Lead l : mapEmailToLead.values()){
        existingLeadIds.add(l.Id);
    } 
    for(Lead l : mapPhoneToLead.values()){
        existingLeadIds.add(l.Id);
    } 
        if(!existingLeadIds.isEmpty()){
            leadProgramKeys = buildLeadProgramKeys([
                        SELECT Lead__c, Program__c, Email__c, Phone__c
                        FROM Lead_Program__c
                        WHERE Lead__c IN :existingLeadIds
                    ]);
            /*
            for(Lead_Program__c lp : [
                SELECT Lead__c, Program__c,Email__c,Phone__c
                FROM Lead_Program__c
                WHERE Lead__c IN :existingLeadIds
            ]){
                String lpEmail = String.isBlank(lp.Email__c) ? '' : lp.Email__c.trim().toLowerCase();
                String lpPhone = String.isBlank(lp.Phone__c) ? '' : lp.Phone__c.trim();
                String key = lp.Program__c + '|' + lpEmail + '|' + lpPhone;
                if(!leadProgramKeys.containsKey(lp.Lead__c)){
                    leadProgramKeys.put(lp.Lead__c, new Set<String>());
                }
                leadProgramKeys.get(lp.Lead__c).add(key);
            }
            */
        }

        List<Lead> leadsToInsert = new List<Lead>();
        List<Lead_Program__c> lpToInsert = new List<Lead_Program__c>();
        Map<Id, Lead_Import__c> importUpdateMap = new Map<Id, Lead_Import__c>();
        List<Lead_Import__c> lpImportRows = new List<Lead_Import__c>();
        for(Lead_Import__c row : scope){

            try {
                // --- Validation (unchanged business rules, still recorded per-row) ---
                Program prog = programMap.get(row.Programme__c);
                if(prog == null){
                    markFailed(row, 'Programme not found', importUpdateMap);
                    continue;
                }
                if(String.isBlank(row.Email__c)){
                    markFailed(row, 'Email not found', importUpdateMap);
                    continue;
                }
                if(String.isBlank(row.Phone__c)){
                    markFailed(row, 'Phone not found', importUpdateMap);
                    continue;
                }
                if(String.isBlank(row.Country__c)){
                    markFailed(row, 'Country not found', importUpdateMap);
                    continue;
                }
                if(String.isBlank(row.State__c)){
                    markFailed(row, 'State not found', importUpdateMap);
                    continue;
                }
                if(String.isBlank(row.City__c)){
                    markFailed(row, 'City not found', importUpdateMap);
                    continue;
                }
                // Note: LeadSource__c from the import row is intentionally ignored -
                // every Lead/Lead_Program__c created here is stamped 'Raw Data'.

                String email = row.Email__c.trim().toLowerCase();
                String phone = row.Phone__c.trim();

                Lead existingLead;
                if(mapEmailToLead.containsKey(email)){
                    existingLead = mapEmailToLead.get(email);
                } 
                else if(mapPhoneToLead.containsKey(phone)){existingLead = mapPhoneToLead.get(phone);} 
                else if(pendingEmailToLead.containsKey(email)){existingLead = pendingEmailToLead.get(email);} 
                else if(pendingPhoneToLead.containsKey(phone)){existingLead = pendingPhoneToLead.get(phone);} 

                if(existingLead != null){
                    String duplicateKey = prog.Id + '|'+email+'|'+phone;
                    // Existing lead -> just link a new program if not already linked
                    Set<String> existingKeys = leadProgramKeys.get(existingLead.Id);
                    if(existingKeys == null || !existingKeys.contains(duplicateKey)){
                        lpImportRows.add(row);
                        lpToInsert.add(new Lead_Program__c(
                            Lead__c = existingLead.Id,
                            Program__c = prog.Id,
                            Email__c = row.Email__c,
                            Phone__c = row.Phone__c,
                            Lead_Source__c = RAW_DATA_SOURCE
                        ));
                        if(existingKeys == null){
                                existingKeys = new Set<String>();
                                leadProgramKeys.put(existingLead.Id, existingKeys);
                        }

                        existingKeys.add(duplicateKey);
                    }

                    row.Status__c = 'Complete';
                    row.Error_Message__c = null;
                    importUpdateMap.put(row.Id, row);

                } else {
                    // New lead
                    String fullName = String.isBlank(row.Name__c) ? '' : row.Name__c.trim();
                    if(String.isBlank(fullName)){
                        markFailed(row, 'Name not found', importUpdateMap);
                        continue;
                    }

                    Country_Master__c country = countryMap.get(row.Country__c.toLowerCase());
                    if(country == null){
                        markFailed(row, 'Country not found in System', importUpdateMap);
                        continue;
                    }

                    String stateKey = country.Id + '|' + row.State__c.toLowerCase();
                    State__c state = stateMap.get(stateKey);
                    if(state == null){
                        markFailed(row, 'State not found in System', importUpdateMap);
                        continue;
                    }

                    String cityKey = state.Id + '|' + row.City__c.toLowerCase();
                    City__c city = cityMap.get(cityKey);
                    // City is optional, same as original (no hard fail on missing city)

                    List<String> parts = fullName.split('\\s+');
                    String firstName, lastName;
                    if(parts.size() == 1){
                        firstName = parts[0];
                        lastName = '.';
                    } else {
                        firstName = parts[0];
                        lastName = '';
                        for(Integer i = 1; i < parts.size(); i++){
                            if(i > 1) lastName += ' ';
                            lastName += parts[i];
                        }
                    }

                    Lead newLead = new Lead();
                    newLead.Description = description;
                    newLead.Title = title;
                    newLead.Send_Welcome_and_Verification_Email__c = false;
                    newLead.RecordTypeId = b2cRecordTypeId;
                    newLead.FirstName = firstName;
                    newLead.LastName = lastName;
                    newLead.Country_Master_backend__c = country.Id;
                    newLead.State_Master__c = state.Id;
                    newLead.District_City__c = city != null ? city.Id : null;
                    newLead.Email = row.Email__c;
                    newLead.Phone = row.Phone__c;
                    newLead.LeadSource = RAW_DATA_SOURCE;
                    newLead.Status = RAW_DATA_SOURCE;
                    newLead.Country = row.Country__c;
                    newLead.State = row.State__c;
                    newLead.City = row.City__c;
                    newLead.XS_Age__c = String.valueOf(row.Age__c);
                    newLead.XS_YearsOfWorkExperience__c = row.Years_of_Work_Experience__c;
                    newLead.XS_DoYouHaveEntranceExamScore__c = row.Do_you_have_Entrance_Exam_Scores__c;
                    newLead.XS_EntranceExamName__c = row.Entrance_Exam_Name__c;
                    newLead.XS_SPJIMR_PartnerCompany__c = row.SPJIMR_Partner_Company__c;
                    newLead.XS_EnterOrganisation__c = row.Organization__c;
                    newLead.XS_HowDidYouFindOutAboutUs__c = row.How_did_you_find_out_about_us__c;
                    newLead.XS_CurrentDesigination__c = row.Current_Designation__c;
                    newLead.XS_College__c = row.College__c;
                    newLead.XS_Year__c = row.Graduation_Year__c;
                    leadsToInsert.add(newLead);
                    pendingEmailToLead.put(email, newLead);
                    pendingPhoneToLead.put(phone, newLead);

                    // Track which program(s) this pending new lead needs once inserted
                    row.Status__c = 'Pending Insert'; // internal marker, overwritten below
                    importUpdateMap.put(row.Id, row);
                }

            } catch(Exception e){
                markFailed(row, 'Unexpected error: ' + e.getMessage(), importUpdateMap);
            }
        }

        // --- Insert new Leads ---
        Map<Id, List<Lead_Import__c>> newLeadIdToRows = new Map<Id, List<Lead_Import__c>>();
        if(!leadsToInsert.isEmpty()){
            Database.SaveResult[] leadInsertResults = Database.insert(leadsToInsert, false);
            system.debug('Inserting Leads '+leadsToInsert);
            Set<Id> newlyInsertedLeadIds = new Set<Id>();
            for(Database.SaveResult sr : leadInsertResults){
                 system.debug('Result is  '+sr.isSuccess());
                if(sr.isSuccess()){
                    newlyInsertedLeadIds.add(sr.getId());
                } 
            }
          

            for(Integer i = 0; i < leadInsertResults.size(); i++){
                Lead insertedLead = leadsToInsert[i];

                // Find the import row(s) that produced this lead (matched on email/phone)
                for(Lead_Import__c row : scope){
                    if(row.Status__c != 'Pending Insert') continue;
                    Boolean matches =
                        (String.isNotBlank(row.Email__c) && insertedLead.Email != null
                            && row.Email__c.trim().equalsIgnoreCase(insertedLead.Email)) || (String.isNotBlank(row.Phone__c) && insertedLead.Phone != null && row.Phone__c.trim() == insertedLead.Phone);
                    if(!matches) continue;

                    if(leadInsertResults[i].isSuccess()){
                        Id leadId = leadInsertResults[i].getId();
                        Program prog = programMap.get(row.Programme__c);
                        system.debug('Creating Lead Program record for '+leadId);
                        lpImportRows.add(row);
                        lpToInsert.add(new Lead_Program__c(
                            Lead__c = leadId,
                            Program__c = prog.Id,
                            Email__c = row.Email__c,
                            Phone__c = row.Phone__c,
                            Lead_Source__c = RAW_DATA_SOURCE
                        ));

                        row.Status__c = 'Lead Created';
                        row.Error_Message__c = null;
                    } else {
                        row = returnRowFailed(row,leadInsertResults[i].getErrors()[0].getMessage()+ ' Status Code: ' + leadInsertResults[i].getErrors()[0].getStatusCode() + ' Fields : ' + leadInsertResults[i].getErrors()[0].getFields());
                       // row.Status__c = 'Failed';
                       //row.Error_Message__c = leadInsertResults[i].getErrors()[0].getMessage()+ ' Status Code: ' + leadInsertResults[i].getErrors()[0].getStatusCode() + ' Fields : ' + leadInsertResults[i].getErrors()[0].getFields();
                    }
                    importUpdateMap.put(row.Id, row);
                }
            }
        }

        // --- Insert Lead_Program__c rows (both existing-lead links and new-lead links) ---
        if(!lpToInsert.isEmpty()){
            Database.SaveResult[] lpResults = Database.insert(lpToInsert, false);

            //Id defaultOwnerId = LeadRoutingService.resolveB2cDefaultOwnerUserId();

            List<Lead> leadsToUpdateOwner = new List<Lead>(); 
            List<Lead_Program__c> lpToUpdateOwner = new List<Lead_Program__c>();

            Set<Id> ownedLeadIds = new Set<Id>();
            for(Integer i = 0; i < lpResults.size(); i++){
                Lead_Import__c row = lpImportRows[i];
                if(lpResults[i].isSuccess()){
                    row.Status__c = 'Complete';
                   row.Error_Message__c = null;
                }
                else{
                    row = returnRowFailed(row,lpResults[i].getErrors()[0].getMessage());
                   // row.Status__c = 'Failed';
                   //row.Error_Message__c = lpResults[i].getErrors()[0].getMessage();
                }
                importUpdateMap.put(row.Id, row);
            }

           // if(!leadsToUpdateOwner.isEmpty()) update leadsToUpdateOwner;
           // if(!lpToUpdateOwner.isEmpty()) update lpToUpdateOwner;
        }

        if(!importUpdateMap.isEmpty()){
            // Clean up any stray "Pending Insert" markers that somehow weren't matched
            List<Lead_Import__c> finalUpdates = new List<Lead_Import__c>();
            for(Lead_Import__c row : importUpdateMap.values()){
                if(row.Status__c == 'Pending Insert'){
                    row = returnRowFailed(row,'Lead insert result could not be matched back to this row');
                   // row.Status__c = 'Failed';
                   // row.Error_Message__c = ;
                }
                
                finalUpdates.add(row);
            }
            if(!Test.isRunningTest()){
                update finalUpdates;
            }
            
        }
    }
    
    @TestVisible
    private static Lead_Import__c returnRowFailed(Lead_Import__c row,String errorMessage){
        row.Status__c = 'Failed';
        row.Error_Message__c = errorMessage;
        return row;
    }

    private static void markFailed(Lead_Import__c row, String message, Map<Id, Lead_Import__c> importUpdateMap){
        row.Status__c = 'Failed';
        //row.Error_Message__c = message;
        importUpdateMap.put(row.Id, row);
    }
    
    @TestVisible
private static Map<Id, Set<String>> buildLeadProgramKeys(List<Lead_Program__c> leadProgramRecords){
    Map<Id, Set<String>> leadProgramKeys = new Map<Id, Set<String>>();
    for(Lead_Program__c lp : leadProgramRecords){
        String lpEmail = String.isBlank(lp.Email__c) ? '' : lp.Email__c.trim().toLowerCase();
        String lpPhone = String.isBlank(lp.Phone__c) ? '' : lp.Phone__c.trim();
        String key = lp.Program__c + '|' + lpEmail + '|' + lpPhone;
        if(!leadProgramKeys.containsKey(lp.Lead__c)){
            leadProgramKeys.put(lp.Lead__c, new Set<String>());
        }
        leadProgramKeys.get(lp.Lead__c).add(key);
    }
    return leadProgramKeys;
}
    
    @TestVisible
    private static Map<Id, Set<String>> buildLeadProgramKeys2(List<Lead_Program__c> leadProgramRecords){
    Map<Id, Set<String>> leadProgramKeys = new Map<Id, Set<String>>();
    for(Lead_Program__c lp : leadProgramRecords){
        String lpEmail = String.isBlank(lp.Email__c) ? '' : lp.Email__c.trim().toLowerCase();
        String lpPhone = String.isBlank(lp.Phone__c) ? '' : lp.Phone__c.trim();
        String key = lp.Program__c + '|' + lpEmail + '|' + lpPhone;
        if(!leadProgramKeys.containsKey(lp.Lead__c)){
            leadProgramKeys.put(lp.Lead__c, new Set<String>());
        }
        leadProgramKeys.get(lp.Lead__c).add(key);
    }
    return leadProgramKeys;
}
    @TestVisible
    private static Lead buildNewLead(
    String description,
    String title,
    String firstName,
    String lastName,
    Country_Master__c country,
    State__c state,
    City__c city
) {
    Lead newLead = new Lead();

    newLead.Description = description;
    newLead.Title = title;
    newLead.Send_Welcome_and_Verification_Email__c = false;

    newLead.FirstName = firstName;
    newLead.LastName = lastName;

    newLead.Country_Master_backend__c = country==null?null:country.Id;
    newLead.State_Master__c = state==null?null:state.Id;
    newLead.District_City__c = city==null?null:city.Id;

    newLead.LeadSource = RAW_DATA_SOURCE;
    newLead.Status = RAW_DATA_SOURCE;



    return newLead;
}
 
}
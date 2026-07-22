global without sharing class LeadImportProcessBatch
implements Database.Batchable<SObject>, Database.Stateful {
    
    private Id importParentId;
    private String description;
    private String Title;
    global LeadImportProcessBatch(Id importParentId){
        
        this.importParentId = importParentId;
        
        Lead_Import_Parent__c lip = [SELECT Title__c,Description__c 
        FROM Lead_Import_Parent__c WHERE Id =:importParentId LIMIT 1];
        
        if(lip!=null){
            this.description = lip.Description__c;
            this.Title = lip.Title__c;
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
                    How_did_you_find_out_about_us__c,Current_Designation__c
            FROM Lead_Import__c
            WHERE Lead_Import_Parent__c = :importParentId
            AND Status__c = 'New'
        ]);
    }
    
    global void execute(
        Database.BatchableContext bc,
    List<Lead_Import__c> scope
    ){
        processScope(scope,this.description,this.Title);
    }
    
    global void finish(
        Database.BatchableContext bc
    ){
        
        update new Lead_Import_Parent__c(
            Id = importParentId,
        Status__c = 'Completed'
            );
    }


    private static Map<String, Program> buildProgramMap(Set<String> programCodes){
    
    Map<String, Program> programMap = new Map<String, Program>();
    
    List<Program> programs = [
        SELECT Id,
               Program_Code__c
        FROM Program
        WHERE Program_Code__c IN :programCodes
    ];
    
    for(Program p : programs){
        programMap.put(p.Program_Code__c, p);
    }
    
    return programMap;
}

private static Map<String, Country_Master__c> buildCountryMap(Set<String> countries){
    
    Map<String, Country_Master__c> countryMap = new Map<String, Country_Master__c>();
    
    List<Country_Master__c> countryRecords = [
        SELECT Id,
               Name
        FROM Country_Master__c
        WHERE Name IN :countries
    ];
    
    for(Country_Master__c c : countryRecords){
        countryMap.put(c.Name.toLowerCase(), c);
    }
    
    return countryMap;
}

private static Map<String, State__c> buildStateMap(Set<String> states){
    
    Map<String, State__c> stateMap = new Map<String, State__c>();
    
    List<State__c> stateRecords = [
        SELECT Id,
               Name,
               Country_Master__c
        FROM State__c
        WHERE Name IN :states
    ];
    
    for(State__c s : stateRecords){
        String key = s.Country_Master__c + '|' + s.Name.toLowerCase();
        stateMap.put(key, s);
    }
    
    return stateMap;
}

private static Map<String, City__c> buildCityMap(Set<String> cities){
    
    Map<String, City__c> cityMap = new Map<String, City__c>();
    
    List<City__c> cityRecords = [
        SELECT Id,
               Name,
               State__c
        FROM City__c
        WHERE Name IN :cities
    ];
    
    for(City__c city : cityRecords){
        String key = city.State__c + '|' + city.Name.toLowerCase();
        cityMap.put(key, city);
    }
    
    return cityMap;
}
    
    private static void processScope(List<Lead_Import__c> scope,String description,String title){
        
        Set<String> emails = new Set<String>();
        Set<String> phones = new Set<String>();
        Map<Id, Lead_Import__c> importUpdateMap =
            new Map<Id, Lead_Import__c>();
        Map<String, List<Lead_Import__c>> pendingPrograms =
            new Map<String, List<Lead_Import__c>>();
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
                emails.add(
                    row.Email__c.trim().toLowerCase()
                    );
            }
            
            if(String.isNotBlank(row.Phone__c)){
                phones.add(
                    row.Phone__c.trim()
                    );
            }
            
            String key;
            
            if(String.isNotBlank(row.Email__c)){
                key = 'EMAIL|' + row.Email__c.trim().toLowerCase();
            }
            else{
                key = 'PHONE|' + row.Phone__c.trim();
            }
        }
        
        Map<String, Program> programMap = buildProgramMap(programCodes);
        Map<String, Country_Master__c> countryMap = buildCountryMap(countries);
        Map<String, State__c> stateMap = buildStateMap(states);
        Map<String, City__c> cityMap = buildCityMap(cities);
                
        
        Map<String, Lead> scopeLeadMap = new Map<String, Lead>();
        
        Map<String, Lead> emailMap =
            new Map<String, Lead>();
        
        Map<String, Lead> phoneMap =
            new Map<String, Lead>();
        
        for(Lead l : [
            
                SELECT Id,
                       Email,
                       Phone
                FROM Lead
                WHERE Email IN :emails
                   OR Phone IN :phones
            ]){
            
            if(String.isNotBlank(l.Email)){
                emailMap.put(
                    l.Email.toLowerCase(),
                l
                    );
            }
            
            if(String.isNotBlank(l.Phone)){
                phoneMap.put(
                    l.Phone,
                l
                    );
            }
            if(String.isNotBlank(l.Email)){
                scopeLeadMap.put(
                    'EMAIL|' + l.Email.toLowerCase(),
                l
                    );
            }
            
            if(String.isNotBlank(l.Phone)){
                scopeLeadMap.put(
                    'PHONE|' + l.Phone,
                l
                    );
            }
        }
        List<Lead> leadsToInsert =
            new List<Lead>();
        
        Map<Integer, Lead_Import__c> leadIndexMap =
            new Map<Integer, Lead_Import__c>();
        Map<Integer, Lead_Import__c> lpIndexMap =
            new Map<Integer, Lead_Import__c>();
        Integer lpIndex = 0;
        Integer index = 0;
        Map<String, Integer> pendingLeadIndexByKey = new Map<String, Integer>();
        List<Lead_Program__c> leadProgramsToInsert = new List<Lead_Program__c>();
        for(Lead_Import__c row : scope){
            String key;
            
            if(String.isNotBlank(row.Email__c)){
                key = 'EMAIL|' + row.Email__c.trim().toLowerCase();
            }
            else{
                key = 'PHONE|' + row.Phone__c.trim();
            }
            Program programRecord =
                programMap.get(row.Programme__c);
            
            if(programRecord == null){
                
                row.Status__c = 'Failed';
                row.Error_Message__c =
                    'Programme not found';
                importUpdateMap.put(
                    row.Id,
                row);
                
                continue;
            }
            if(String.isBlank(row.Email__c)){
                row.Error_Message__c = 'Email not found';
                row.Status__c = 'Failed';
                importUpdateMap.put(
                    row.Id,
                row
                    );
                continue;
            }
            if(String.isBlank(row.Phone__c)){
                row.Error_Message__c = 'Phone not found';
                row.Status__c = 'Failed';
                importUpdateMap.put(
                    row.Id,
                row
                    );
                continue;
            }
            if(String.isBlank(row.LeadSource__c)){
                row.Error_Message__c = 'Lead Source not found';
                row.Status__c = 'Failed';
                importUpdateMap.put(
                    row.Id,
                row
                    );
                continue;
            }
            if(String.isBlank(row.Country__c)){
                row.Status__c = 'Failed';
                row.Error_Message__c = 'Country not found';
                importUpdateMap.put(
                    row.Id,
                row
                    );
                continue;
            }
            if(String.isBlank(row.State__c)){
                row.Status__c = 'Failed';
                row.Error_Message__c = 'State not found';
                importUpdateMap.put(
                    row.Id,
                row
                    );
                continue;
            }
            if(String.isBlank(row.City__c)){
                row.Status__c = 'Failed';
                row.Error_Message__c = 'City not found';
                importUpdateMap.put(
                    row.Id,
                row
                    );
                continue;
            }
            Lead existingLead;
            
            if(String.isNotBlank(row.Email__c)){
                existingLead =
                    scopeLeadMap.get(
                    'EMAIL|' +
                    row.Email__c.trim().toLowerCase()
                    );
            }
            
            if(
                existingLead == null &&
                String.isNotBlank(row.Phone__c)
            ){
                existingLead =
                    scopeLeadMap.get(
                    'PHONE|' +
                    row.Phone__c
                    );
            }
            if(existingLead == null){
                
                Lead l = new Lead();
                l.Description = description;
                l.Title = title;
                l.Send_Welcome_and_Verification_Email__c = false;
                l.RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2C').getRecordTypeId();
                String fullName =
                    String.isBlank(row.Name__c)
                    ? ''
                    : row.Name__c.trim();
                
                if(String.isBlank(fullName)){
                    row.Status__c = 'Failed';
                    row.Error_Message__c = 'Name not found';
                    importUpdateMap.put(
                        row.Id,
                    row
                        );
                    continue;
                }
                
                List<String> parts =
                    fullName.split('\\s+');
                
                if(parts.size() == 1){
                    
                    l.First_Name__c = parts[0];
                    l.LastName = '.';
                    
                }
                else if(parts.size() > 1){
                    
                    l.First_Name__c = parts[0];
                    
                    String lastName = '';
                    
                    for(Integer i = 1; i < parts.size(); i++){
                        
                        if(i > 1){
                            lastName += ' ';
                        }
                        
                        lastName += parts[i];
                    }
                    
                    l.LastName = lastName;
                }
                else{
                    
                    l.LastName = '.';
                }
                
                Country_Master__c country =
                    countryMap.get(
                    row.Country__c.toLowerCase()
                    );
                
                if(country == null){
                    
                    row.Status__c = 'Failed';
                    importUpdateMap.put(
                        row.Id,
                    row
                        );
                    row.Error_Message__c =
                        'Country not found in System';
                    
                    continue;
                }
                
                l.Country_Master_backend__c =
                    country.Id;
                
                String stateKey =
                    country.Id +
                    '|' +
                    row.State__c.toLowerCase();
                
                State__c state =
                    stateMap.get(stateKey);
                
                if(state == null){
                    
                    row.Status__c = 'Failed';
                    importUpdateMap.put(
                        row.Id,
                    row
                        );
                    row.Error_Message__c =
                        'State not found in System';
                    
                    continue;
                }
                
                l.State_Master__c =
                    state.Id;
                
                String cityKey =
                    state.Id +
                    '|' +
                    row.City__c.toLowerCase();
                
                City__c city =
                    cityMap.get(cityKey);
                
                // if(city == null){
                    
                    //     row.Status__c = 'Failed';
                    //     importUpdates.add(row);
                    //     row.Error_Message__c =
                    //         'City not found';
                    
                    //     continue;
                // }
                
                l.District_City__c =
                    city!=null?city.Id:null;
                
                
                l.Email = row.Email__c;
                
                l.Phone = row.Phone__c;
                l.LeadSource = 'Raw Data';
                l.Status = 'Raw Data';
                l.Country = row.Country__c;
                l.State = row.State__c;
                l.City = row.City__c;
                l.XS_Age__c = String.valueOf(row.Age__c);
                l.XS_YearsOfWorkExperience__c = row.Years_of_Work_Experience__c;
                l.XS_DoYouHaveEntranceExamScore__c = row.Do_you_have_Entrance_Exam_Scores__c;
                l.XS_EntranceExamName__c = row.Entrance_Exam_Name__c;
                l.XS_SPJIMR_PartnerCompany__c = row.SPJIMR_Partner_Company__c;
                l.XS_EnterOrganisation__c = row.Organization__c;
                l.XS_HowDidYouFindOutAboutUs__c = row.How_did_you_find_out_about_us__c;
                l.XS_CurrentDesigination__c = row.Current_Designation__c;
                scopeLeadMap.put(key, l);
                leadsToInsert.add(l);
                
                leadIndexMap.put(index,row);
                if(String.isNotBlank(l.Email)){
                    scopeLeadMap.put(
                        'EMAIL|' + l.Email.toLowerCase(),
                    l
                        );
                }
                
                if(String.isNotBlank(l.Phone)){
                    scopeLeadMap.put(
                        'PHONE|' + l.Phone,
                    l
                        );
                }
                
                index++;
            }
            else{
                if(existingLead.Id == null){
                    
                    if(!pendingPrograms.containsKey(key)){
                        pendingPrograms.put(
                            key,
                        new List<Lead_Import__c>()
                            );
                    }
                    
                    pendingPrograms.get(key).add(row);
                } else {
                    
                    Lead_Program__c lp = new Lead_Program__c();
                    
                    lp.Lead_Source__c = 'Raw Data';
                    lp.Program__c =
                        programMap.get(row.Programme__c).Id;
                    lp.Email__c = row.Email__c;
                    lp.Phone__c = row.Phone__c;
                    lp.Lead__c = existingLead.Id;
                    
                    leadProgramsToInsert.add(lp);
                    
                    lpIndexMap.put(lpIndex,row);
                    lpIndex++;
                }
            }
        }
        Database.SaveResult[] leadInsertresults = new List<Database.SaveResult>();
        if(!leadsToInsert.isEmpty()){
            leadInsertresults =
                Database.insert(
                leadsToInsert,
            false
                );
            
            
            for(Integer i=0;i<leadInsertresults.size();i++){
                
                Lead_Import__c row =
                    leadIndexMap.get(i);
                
                if(leadInsertresults[i].isSuccess()){
                    
                    Id leadId =
                        leadInsertresults[i].getId();
                    Lead insertedLead = leadsToInsert[i];
                    
                    String key;
                    
                    if(String.isNotBlank(insertedLead.Email)){
                        key = 'EMAIL|' + insertedLead.Email.toLowerCase();
                    }
                    else{
                        key = 'PHONE|' + insertedLead.Phone;
                    }
                    
                    if(pendingPrograms.containsKey(key)){
                        
                        for(
                            Lead_Import__c pendingRow :
                            pendingPrograms.get(key)
                        ){
                            
                            Lead_Program__c extraLp =
                                new Lead_Program__c();
                            
                            extraLp.Lead__c = leadId;
                            
                            extraLp.Program__c =
                                programMap.get(
                                pendingRow.Programme__c
                                ).Id;
                            
                            extraLp.Lead_Source__c =
                                'Raw Data';
                            
                            extraLp.Email__c =
                                pendingRow.Email__c;
                            
                            extraLp.Phone__c =
                                pendingRow.Phone__c;
                            
                            leadProgramsToInsert.add(extraLp);
                            
                            lpIndexMap.put(
                                lpIndex,
                            pendingRow
                                );
                            
                            lpIndex++;
                        }
                    }
                    
                    Lead_Program__c lp =
                        new Lead_Program__c();
                    
                    lp.Lead__c = leadId;
                    
                    lp.Program__c =
                        programMap.get(
                        row.Programme__c
                        ).Id;
                    
                    lp.Lead_Source__c =
                        'Raw Data';
                    
                    lp.Email__c =
                        row.Email__c;
                    
                    lp.Phone__c =
                        row.Phone__c;
                    
                    leadProgramsToInsert.add(lp);
                    
                    lpIndexMap.put(
                        lpIndex,
                    row
                        );
                    
                    lpIndex++;
                    row.Status__c =
                        'Lead Created';
                    
                }else{
                    
                    row.Status__c =
                        'Failed';
                    
                    row.Error_Message__c =
                        leadInsertresults[i]
                        .getErrors()[0]
                        .getMessage()+ ' Status Code: '+leadInsertresults[i]
                        .getErrors()[0]
                        .getStatusCode()
                        + ' Fields : '+leadInsertresults[i]
                        .getErrors()[0]
                        .getFields();
                }
                
                importUpdateMap.put(
                    row.Id,
                row
                    );
            }
            
        }
        if(!leadProgramsToInsert.isEmpty()){
            Database.SaveResult[] lpResults = Database.insert(
                leadProgramsToInsert,
            false
                );
            
            Id defaultOwnerId = LeadRoutingService.resolveB2cDefaultOwnerUserId();
            
            List<Lead> leadsToUpdate = new List<Lead>();
            List<Lead_Program__c> leadProgramsToUpdate = new List<Lead_Program__c>();
            
            for (Integer i = 0; i < leadInsertresults.size(); i++) {
                if (leadInsertresults[i].isSuccess()) {
                    leadsToUpdate.add(new Lead(
                        Id = leadInsertresults[i].getId(),
                    OwnerId = defaultOwnerId
                        ));
                }
            }
            
            for (Integer i = 0; i < lpResults.size(); i++) {
                if (lpResults[i].isSuccess()) {
                    leadProgramsToUpdate.add(new Lead_Program__c(
                        Id = lpResults[i].getId(),
                    OwnerId = defaultOwnerId
                        ));
                }
            }
            
            if (!leadsToUpdate.isEmpty()) {
                update leadsToUpdate;
            }
            
            if (!leadProgramsToUpdate.isEmpty()) {
                update leadProgramsToUpdate;
            }
            
            for(Integer i = 0; i < lpResults.size(); i++){
                
                Lead_Import__c row =
                    lpIndexMap.get(i);
                
                if(row == null){
                    continue;
                }
                
                if(lpResults[i].isSuccess()){
                    
                    row.Status__c =
                        'Complete';
                    
                    row.Error_Message__c = null;
                }
                else{
                    
                    row.Status__c =
                        'Failed';
                    
                    row.Error_Message__c =
                        lpResults[i]
                        .getErrors()[0]
                        .getMessage();
                }
                
                importUpdateMap.put(
                    row.Id,
                row
                    );
            }
        }
        if(!importUpdateMap.isEmpty()){
            
            update importUpdateMap.values();
        }
        
        
    }
}
global class B2CImportBatch implements Database.Batchable<sObject> {
    
    global Database.QueryLocator start(Database.BatchableContext BC) {
        String query = 'SELECT Id, Name, CreatedDate, Name__c, Email__c,'+
            'Phone__c, Country__c, State__c, City__c, Years_of_Work_Experience__c,'+
            'Do_you_have_Entrance_Exam_Scores__c, Entrance_Exam_Name__c, SPJIMR_Partner_Company__c,'+
            'Organization__c, How_did_you_find_out_about_us__c, Current_Designation__c, Age__c,'+
            'College__c, Graduation_Year__c, Programme__c, Status__c, LeadSource__c,Send_Welcome_and_Verification_Email__c '+
            'FROM Lead_Import__c WHERE Status__c = \'Pending\'';
        
        return Database.getQueryLocator(query);
    }
    
    global void execute(Database.BatchableContext BC, List<Lead_Import__c> scope) {
        
        List<Lead_Import__c> importsToUpdate = new List<Lead_Import__c>();
        Set<String> emailSet = new Set<String>();
        Set<String> phoneSet = new Set<String>();
        Set<String> programCodes = new Set<String>();
        Set<String> countryNames = new Set<String>();
        Set<String> stateNames = new Set<String>();
        Set<String> cityNames = new Set<String>();
        
        Id b2cRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId();
        
        for (Lead_Import__c ld : scope) {
            if (ld.Email__c != null) emailSet.add(ld.Email__c.trim());
            if (ld.Phone__c != null) phoneSet.add(ld.Phone__c.trim());
            if (ld.Programme__c != null) programCodes.add(ld.Programme__c.trim());
            if (ld.Country__c != null) countryNames.add(ld.Country__c.trim());
            if (ld.State__c != null) stateNames.add(ld.State__c.trim());
            if (ld.City__c != null) cityNames.add(ld.City__c.trim());
        }
        
        Map<String, Lead> mapEmailToLead = new Map<String, Lead>();
        Map<String, Lead> mapPhoneToLead = new Map<String, Lead>();
        Map<String, Lead> pendingEmailToLead = new Map<String, Lead>();
        Map<String, Lead> pendingPhoneToLead = new Map<String, Lead>();
        
        for (Lead l : [
            SELECT Id, Email, Phone,Send_Welcome_and_Verification_Email__c
            FROM Lead
            WHERE (Email IN :emailSet OR Phone IN :phoneSet)
            AND RecordTypeId = :b2cRecordTypeId
        ]) {
            if (l.Email != null) mapEmailToLead.put(l.Email.trim(), l);
            if (l.Phone != null) mapPhoneToLead.put(l.Phone.trim(), l);
        }
        
        Map<String, Program> programCodeToProgram = new Map<String, Program>();
        Map<String, Country_Master__c> mapCountryNameToCountry = new Map<String, Country_Master__c>();
        Map<String, State__c> mapStateKeyToState = new Map<String, State__c>();
        Map<String, City__c> mapCityKeyToCity = new Map<String, City__c>();
        
        for (Country_Master__c c : [
            SELECT Id, Name FROM Country_Master__c
            WHERE Name IN :countryNames
        ]) {
            mapCountryNameToCountry.put(normalize(c.Name), c);
        }
        
        for (State__c s : [
            SELECT Id, Name, Country_Master__c FROM State__c
            WHERE Name IN :stateNames
        ]) {
            String key = normalize(s.Name) + '|' + s.Country_Master__c;
            mapStateKeyToState.put(key, s);
        }
        
        for (City__c c : [
            SELECT Id, Name, State__c FROM City__c
            WHERE Name IN :cityNames
        ]) {
            String key = normalize(c.Name) + '|' + c.State__c;
            mapCityKeyToCity.put(key, c);
        }
        
        for (Program p : [
            SELECT Id, Program_Code__c FROM Program
            WHERE Program_Code__c IN :programCodes
        ]) {
            programCodeToProgram.put(p.Program_Code__c.trim(), p);
        }
        
        Set<Id> leadIds = new Set<Id>();
        for (Lead l : mapEmailToLead.values()) leadIds.add(l.Id);
        for (Lead l : mapPhoneToLead.values()) leadIds.add(l.Id);
        
        Map<Id, Set<Id>> leadIdToProgramIds = new Map<Id, Set<Id>>();
        
        if (!leadIds.isEmpty()) {
            for (Lead_Program__c lp : [
                SELECT Lead__c, Program__c
                FROM Lead_Program__c
                WHERE Lead__c IN :leadIds
            ]) {
                if (!leadIdToProgramIds.containsKey(lp.Lead__c)) {
                    leadIdToProgramIds.put(lp.Lead__c, new Set<Id>());
                }
                leadIdToProgramIds.get(lp.Lead__c).add(lp.Program__c);
            }
        }
        
        List<Lead> leadsToInsert = new List<Lead>();
        List<Lead_Program__c> lpToInsert = new List<Lead_Program__c>();
        Set<Id> newLeadIds = new Set<Id>();
        Set<string> setEntranceExamNames = new Set<string>();
        Set<string> setLeadSourceNames = new Set<string>();
        Schema.DescribeFieldResult fieldResultEntranceExam = Lead.Entrance_Exam__c.getDescribe();
List<Schema.PicklistEntry> entries = fieldResultEntranceExam.getPicklistValues();
for (Schema.PicklistEntry entry : entries) {
    System.debug(entry.getLabel() + ' : ' + entry.getValue());
    setEntranceExamNames.add(entry.getValue());
}

Schema.DescribeFieldResult fieldResultLeadSource = Lead.LeadSource.getDescribe();
 entries = fieldResultLeadSource.getPicklistValues();
for (Schema.PicklistEntry entry : entries) {
    System.debug(entry.getLabel() + ' : ' + entry.getValue());
    setLeadSourceNames.add(entry.getValue());
}
        for (Lead_Import__c ld : scope) {
            
            Boolean isSuccess = false;
            
            try {
                
                String email = ld.Email__c != null ? ld.Email__c.trim() : null;
                String phone = ld.Phone__c != null ? ld.Phone__c.trim() : null;
                String programCode = ld.Programme__c != null ? ld.Programme__c.trim() : null;
                String lpSource = ld.LeadSource__c;
                String countryName = ld.Country__c != null ? ld.Country__c.trim() : null;
                String stateName = ld.State__c != null ? ld.State__c.trim() : null;
                String cityName = ld.City__c != null ? ld.City__c.trim() : null;
                system.debug('Send Email is '+ld.Send_Welcome_and_Verification_Email__c);
                Boolean sendEmail=false;
                sendEmail = 'yes'.equalsIgnoreCase(ld.Send_Welcome_and_Verification_Email__c);
                system.debug('Send Email boolean is '+sendEmail);
                Lead existingLead;
                
                if (email != null && mapEmailToLead.containsKey(email)) {
                    existingLead = mapEmailToLead.get(email);
                } else if (phone != null && mapPhoneToLead.containsKey(phone)) {
                    existingLead = mapPhoneToLead.get(phone);
                } else if (email != null && pendingEmailToLead.containsKey(email)) {
                    existingLead = pendingEmailToLead.get(email);
                } else if (phone != null && pendingPhoneToLead.containsKey(phone)) {
                    existingLead = pendingPhoneToLead.get(phone);
                }
                
                Program prog = programCodeToProgram.get(programCode);
                
                Id countryId, stateId, cityId;
                
                Country_Master__c country = mapCountryNameToCountry.get(normalize(countryName));
                
                if (country != null) {
                    countryId = country.Id;
                    
                    String stateKey = normalize(stateName) + '|' + country.Id;
                    State__c state = mapStateKeyToState.get(stateKey);
                    
                    if (state != null) {
                        stateId = state.Id;
                        
                        String cityKey = normalize(cityName) + '|' + state.Id;
                        City__c city = mapCityKeyToCity.get(cityKey);
                        
                        if (city != null) {
                            cityId = city.Id;
                        }
                    }
                }
                
                if (prog == null) continue;
                
                if (existingLead != null) {
                    system.debug('Found Existing Lead '+existingLead);
                    
                    
                    Set<Id> existingPrograms = leadIdToProgramIds.get(existingLead.Id);
                    
                    if (existingPrograms == null || !existingPrograms.contains(prog.Id)) {
                        lpToInsert.add(new Lead_Program__c(
                            Lead__c = existingLead.Id,
                        Program__c = prog.Id,
                        Email__c = email,
                        Phone__c = phone,
                        Lead_Source__c = lpSource
                            ));
                        
                        if (!leadIdToProgramIds.containsKey(existingLead.Id)) {
                            leadIdToProgramIds.put(existingLead.Id, new Set<Id>());
                        }
                        leadIdToProgramIds.get(existingLead.Id).add(prog.Id);
                    }
                    
                    isSuccess = true;
                } else {
                    
                    List<String> formatName = ld.Name__c != null ? ld.Name__c.trim().split(' ') : new List<String>();
                    
                    String fname;
                    String lname;
                    String entranceExam = ld.Entrance_Exam_Name__c;
                    String workExp = ld.Years_of_Work_Experience__c;
                    String partnerComp = ld.SPJIMR_Partner_Company__c;
                    String entranceExamScores = ld.Do_you_have_Entrance_Exam_Scores__c;
                    String organization = ld.Organization__c;
                    String designation = ld.Current_Designation__c;
                    String college = ld.College__c;
                    String gradYear = ld.Graduation_Year__c;
                    Integer age = ld.Age__c!=null?Integer.valueOf(ld.Age__c):null;
                    String howDidyouFind = ld.How_did_you_find_out_about_us__c;
                    if (formatName.size() == 1) {
                        fname = formatName[0];
                        lname = '.';
                    } else if (formatName.size() >= 2) {
                        fname = formatName[0];
                        lname = formatName[formatName.size() - 1];
                    } else {
                        fname = 'Unknown';
                        lname = '.';
                    }
                    
                    Lead newLead = new Lead(
                        FirstName = fname,
                    LastName = lname,
                    Email = email,
                    Phone = phone,
                    RecordTypeId = b2cRecordTypeId,
                    LeadSource = setLeadSourceNames.contains(ld.LeadSource__c)?ld.LeadSource__c:null,
                    Country_Master_backend__c = countryId,
                    State_Master__c = stateId,
                    District_City__c = cityId,
                    XS_DoYouHaveEntranceExamScore__c = String.isNotBlank(ld.Do_you_have_Entrance_Exam_Scores__c)?'Yes':'No',
                    XS_YearsOfWorkExperience__c=String.isNotBlank(workExp)?workExp:'',
                    XS_SPJIMR_PartnerCompany__c = String.isNotBlank(partnerComp)?partnerComp:'',
                    XS_EnterOrganisation__c = String.isNotBlank(organization)?organization:'',
                    XS_EntranceExamName__c = setEntranceExamNames.contains(entranceExam)?entranceExam:'',
                    XS_Year__c = String.isNotBlank(gradYear)?gradYear:'', 
                    XS_College__c = String.isNotBlank(college)?college:'',
                    XS_Age__c=age!=null?String.valueOf(age):'',
                    XS_HowDidYouFindOutAboutUs__c = String.isNotBlank(howDidyouFind)?howDidyouFind:'',
                    XS_CurrentDesigination__c = String.isNotBlank(designation)?designation:'',
                    Send_Welcome_and_Verification_Email__c=sendEmail
                        );
                    
                    leadsToInsert.add(newLead);
                    
                    if (email != null) pendingEmailToLead.put(email, newLead);
                    if (phone != null) pendingPhoneToLead.put(phone, newLead);
                    
                    isSuccess = true;
                }
                
            } catch (Exception e) {
                System.debug('Error for record ' + ld.Id + ' : ' + e.getMessage());
            }
            
            if (isSuccess) {
                importsToUpdate.add(new Lead_Import__c(
                    Id = ld.Id,
                Status__c = 'Complete'
                    ));
            }
        }
        
        if (!leadsToInsert.isEmpty()) {
            insert leadsToInsert;
            
            for (Lead l : leadsToInsert) {
                newLeadIds.add(l.Id);
                if (l.Email != null) mapEmailToLead.put(l.Email.trim(), l);
                if (l.Phone != null) mapPhoneToLead.put(l.Phone.trim(), l);
            }
            
            for (Lead_Import__c ld : scope) {
                String email = ld.Email__c != null ? ld.Email__c.trim() : null;
                String phone = ld.Phone__c != null ? ld.Phone__c.trim() : null;
                String programCode = ld.Programme__c != null ? ld.Programme__c.trim() : null;
                String lpSource = ld.LeadSource__c;
                
                Program prog = programCodeToProgram.get(programCode);
                if (prog == null) continue;
                
                Lead l;
                
                if (email != null && mapEmailToLead.containsKey(email)) {
                    l = mapEmailToLead.get(email);
                } else if (phone != null && mapPhoneToLead.containsKey(phone)) {
                    l = mapPhoneToLead.get(phone);
                }
                
                if (l == null || !newLeadIds.contains(l.Id)) continue;
                
                lpToInsert.add(new Lead_Program__c(
                    Lead__c = l.Id,
                Program__c = prog.Id,
                Email__c = email,
                Phone__c = phone,
                Lead_Source__c = lpSource
                    ));
                
                if (!leadIdToProgramIds.containsKey(l.Id)) {
                    leadIdToProgramIds.put(l.Id, new Set<Id>());
                }
                leadIdToProgramIds.get(l.Id).add(prog.Id);
            }
        }
        
        
        
        if (!lpToInsert.isEmpty()) {
            insert lpToInsert;
        }
        
        if (!importsToUpdate.isEmpty()) {
            update importsToUpdate;
        }
    }
    
    global void finish(Database.BatchableContext bc) {
        Id defaultOwnerId = LeadRoutingService.resolveB2cDefaultOwnerUserId();
        if (defaultOwnerId != null) {
            List<User> defaultLeadOwner = [SELECT Id, Email FROM User WHERE Id = :defaultOwnerId LIMIT 1];
            if (!defaultLeadOwner.isEmpty() && defaultLeadOwner[0].Email != null) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new String[] { defaultLeadOwner[0].Email });
                mail.setSubject('Lead Import Job Completed');
                mail.setPlainTextBody('The Lead import batch job has finished successfully.');
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            }
        }
        System.debug('Import Done');
    }
    
    private static String normalize(String val){
        return val == null ? null : val.trim().toLowerCase();
    }
}
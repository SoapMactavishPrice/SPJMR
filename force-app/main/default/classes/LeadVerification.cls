public without sharing class LeadVerification implements Queueable{
    
    public String assigneeId;
    
   @AuraEnabled
public static Map<String,String> verifyLead(String leadId){

    Map<String,String> result = new Map<String,String>();

    try {

        if(!Auth.CommunitiesUtil.isGuestUser() || Auth.CommunitiesUtil.isInternalUser()){
            result.put('REGISTERED_OR_LOGGEDIN','You are already logged in');
            return result;
        }

        Lead l = [
            SELECT Id, Email, IsConverted, ConvertedAccountId,Program_Master__c,Name
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        if(String.isBlank(l.Email)){
            result.put('ERROR','Lead email missing');
            return result;
        }

        String email = l.Email;

        /* ----------------------------------
           STEP 1: Check if User already exists
        ----------------------------------- */
        List<User> existingUser = [
            SELECT Id FROM User
            WHERE Email = :email AND IsActive = true
            LIMIT 1
        ];

        if(!existingUser.isEmpty()){
            result.put('REGISTERED_OR_LOGGEDIN','Your Email has already been Verified.');
            return result;
        }

        /* ----------------------------------
           STEP 2: Check if Person Account exists
        ----------------------------------- */
        List<Account> existingAccount = [
            SELECT Id FROM Account
            WHERE PersonEmail = :email
            LIMIT 1
        ];

        if(!existingAccount.isEmpty()){
             Map<String,String> userResult = createCommunityUser(existingAccount[0].Id);

    if(userResult.containsKey('SUCCESS')){
        return ensureApplicationCreated(existingAccount[0].Id, leadId);
    }

    return userResult;
        }

        /* ----------------------------------
           STEP 3: Lead not converted → Convert
        ----------------------------------- */
        if(!l.IsConverted){

            l.Is_Verified__c = true;
            update l;

            return convertLead(new List<Lead>{l}, null);
        }

        /* ----------------------------------
           STEP 4: Lead converted but no Account found
        ----------------------------------- */
        if(l.IsConverted && l.ConvertedAccountId != null){
            return createCommunityUser(l.ConvertedAccountId);
        }

        result.put('ERROR','No matching record found.');
        return result;

    } catch(Exception e){
        throw new AuraHandledException(e.getMessage());
    }
}


private static Map<String,String> ensureApplicationCreated(String accountId, String leadId){

    Map<String,String> resultMap = new Map<String,String>();

    Lead l = [
        SELECT Program_Master__c
        FROM Lead
        WHERE Id = :leadId
        LIMIT 1
    ];

    if(l.Program_Master__c == null){
        resultMap.put('ERROR','No Program found on Lead.');
        return resultMap;
    }

    List<Application__c> existingApps = [
        SELECT Id FROM Application__c
        WHERE Applicant__c = :accountId
        AND Program__c = :l.Program_Master__c
        LIMIT 1
    ];

    if(!existingApps.isEmpty()){
        resultMap.put('SUCCESS','User exists and Application already created.');
        return resultMap;
    }

    // Application missing → Create it
    return insertGrade(accountId, new Set<Id>{l.Program_Master__c});
}

    
    public static Map<String,String> convertLead(List<Lead> List_existingLeads,String Id_ExistingAccount){
        Map<String,String> resultMap = new Map<String,String>();
        try {
            List<Account> existingAccount = [SELECT Id,Owner.UserRole.Name 
            FROM Account WHERE Id=:Id_ExistingAccount LIMIT 1];
            if(existingAccount.size()>0){
                if(existingAccount[0].Owner.UserRole.Name == null){
                    throw new AuraHandledException('Account Owner Should have a role!');
                }
            }
            
            //Lead convertLead = [SELECT Id,IsConverted,convertedAccountId,Program_Master__c FROM Lead WHERE Id=:LeadId AND LastName!=null LIMIT 1];
            //List<Account> list_existingAccount = [SELECT Id FROM Account WHERE PersonEmail = :email LIMIT 1];
            Set<Id> set_ProgramIds = new Set<Id>();
            Database.LeadConvert[] convertList = new Database.LeadConvert[0];
            String convertedStatus = [SELECT Id,MasterLabel FROM LeadStatus WHERE IsConverted=true LIMIT 1].MasterLabel;
            for(Lead l:List_existingLeads){
                
                Database.LeadConvert lc = new Database.LeadConvert();
                set_ProgramIds.add(l.Program_Master__c);
                lc.setAccountId(Id_ExistingAccount != null?Id_ExistingAccount:null);
                //Id_ExistingAccount == null? lc.setAccountId(null):lc.setAccountId(Id_ExistingAccount);
                
                lc.setConvertedStatus(convertedStatus);
                lc.setLeadId(l.Id);
                lc.setDoNotCreateOpportunity(true);
                if(Id_ExistingAccount == null){
                    Database.LeadConvertResult result = Database.convertLead(lc);
                    if(result.isSuccess()){
                        Id_ExistingAccount = result.getAccountId();
                        system.debug('Lead Converted: Creating User with PersonAccount '+Id_ExistingAccount);
                        resultMap = createCommunityUser(Id_ExistingAccount);
                        if(resultMap.containsKey('SUCCESS')){
                            resultMap = insertGrade(Id_ExistingAccount, new Set<Id>{l.Program_Master__c});
                            if(List_existingLeads.size()==1){
                                return resultMap;
                            }
                        }
                    }
                    else{
                        resultMap.put('ERROR','Could not convert This Lead '+result.getErrors());
                        
                        return resultMap;
                    }
                }
                else{
                    convertList.add(lc);
                }
                
                
                
            }
            
            
            if(!convertList.isEmpty()){
                List<Database.LeadConvertResult> lcr = Database.convertLead(convertList);
                Boolean errorFlag = false;
                Integer i=0;
                for(Database.LeadConvertResult lr:lcr){
                    if(!lr.isSuccess()){
                        
                        if(!errorFlag){
                            errorFlag = true;
                            
                        }
                        
                        resultMap.put('ERROR '+i,'Lead Conversion Failed '+lr.getErrors());
                        i+=1;
                    }
                }
                if(!errorFlag){
                    resultMap = insertGrade(Id_ExistingAccount, set_ProgramIds);
                    return resultMap;
                }
                
            }
            
            
            
            
            
            resultMap.put('ERROR','Lead Not Found');
            return resultMap;
            
        } catch (Exception e) {
            system.debug('Error is this => '+e.getMEssage());
            system.debug('Error at Line '+e.getLineNumber());
            
            resultMap.put('ERROR','Lead Conversion Failed '+e.getMessage() + ' at Line: '+e.getLineNumber());
            return resultMap;
            //throw new AuraHandledException(e.getMessage());
            
        }
    }
    
    
    
    public static Map<String,String> createCommunityUser(String accountId){
        Map<String,String> resultMap = new Map<String,String>();
        if(accountId != null){
            List<Account> listPersonAccount = [SELECT Id,FirstName,LastName, PersonEmail FROM Account WHERE Id=:accountId LIMIT 1];
            
            String nickname =createNickname(listPersonAccount[0].LastName,listPersonAccount[0].PersonEmail);
            
            String usernameValue = listPersonAccount[0].PersonEmail;
            //createUsername(listPersonAccount[0].LastName,listPersonAccount[0].PersonEmail);
            if(listPersonAccount.size()>0){
                nickname = String.join(listPersonAccount[0].PersonEmail.split('@'), '') +String.valueOf(Integer.valueOf(math.random()*10000));
                Profile login = [SELECT Id FROM Profile WHERE Name='SPJIMR Applicant' LIMIT 1];
                User u = new User(
                    LastName = listPersonAccount[0].LastName,
                FirstName = listPersonAccount[0].FirstName,
                Email = listPersonAccount[0].PersonEmail,
                CommunityNickname  = nickname,
                Username = usernameValue,
                ProfileId = login.Id
                    );
                try{
                    Id userId = Site.createExternalUser(u, accountId);
                    LeadVerification lvc = new LeadVerification(userId);
                    System.enqueueJob(lvc);
                    system.debug('Successfully created a user with Id '+userId);
                    resultMap.put('SUCCESS','User Created Successfully');
                    return resultMap;
                }catch(Site.ExternalUserCreateException e){
                    system.debug('Error creating user: '+e.getMessage());
                    resultMap.put('ERROR','Error creating user '+e.getMessage());
                    return resultMap;
                }
                
            }
            
        }
        if(resultMap.isEmpty()){
            resultMap.put('ERROR', 'No Related Account Found');
        }
        return resultMap;
    }
    
    private static Map<String,String> insertGrade(String accountId,Set<Id> set_programId){
        Map<String,String> resultMap = new Map<String,String>();
        Set<Id> set_existingGrades = new Set<Id>();
        // List<Account_Program_Batch_Selection__c> existingGradesList = [SELECT Id,Program_Name__c,Program_Name__r.Program_Code__c FROM Account_Program_Batch_Selection__c WHERE Student_Name__c =: accountId AND Program_Name__r.Program_Code__c<>NULL];
        // for(Account_Program_Batch_Selection__c grade: existingGradesList){
        //     set_existingGrades.add(grade.Program_Name__c);
        // }
        
        // List<Account_Program_Batch_Selection__c> List_insertGrade = new List<Account_Program_Batch_Selection__c>();
        // for(Id programId:set_programId){
        //     if(!set_existingGrades.contains(programId)){
        //         Account_Program_Batch_Selection__c grade = new Account_Program_Batch_Selection__c(Student_Name__c =accountId,
        //         Program_Name__c =  programId);
        //         List_insertGrade.add(grade);
        //     }
        // }
        
        // try{
        //     if(List_insertGrade.size()>0){
                //insert List_insertGrade;
                resultMap = createApplication(set_programId,accountId);
           // }
            resultMap.put('SUCCESS','Grades inserted Successfully');
            return resultMap;
        // }
        // catch(DMLException e){
        //     system.debug('Error Inserting Level/Grade '+e.getMessage());
        //     resultMap.put('ERROR','Error Inserting Level/Grade '+e.getMessage());
        //     return resultMap;
        // }
    }
    
    
    private static Map<String,String> createApplication(Set<Id> programIds,String accountId){
        Map<String,String> resultMap = new Map<String,String>();
        Account acc = [SELECT PersonEmail,Phone,LastName,FirstName FROM Account WHERE Id =: accountId LIMIT 1];
        // Set<Id> programIds = new Set<Id>();
        List<Application__c> newApplicationsList = new List<Application__c>();
        // for(Account_Program_Batch_Selection__c grade:list_Grades){
        //     programIds.add(grade.Program_Name__c);
        // }
        List<Program> listPrograms = [SELECT Id,Program_Code__c FROM Program WHERE Id IN:programIds AND Program_Code__c<>NULL];
        for(Program prg:listPrograms){
            Application__c newApplication = new Application__c();
            newApplication.Applicant__c = accountId;
            // newApplication.Email__c = acc.PersonEmail;
            // newApplication.Phone__c = acc.Phone;
            newApplication.Program__c = prg.Id;
            // newApplication.First_Name__c = acc.FirstName;
            // newApplication.Last_Name__c = acc.LastName;
            String newAppNumber = ApplicationFormHelper.generateApplicationNumberFromSequence(prg.Program_Code__c);
            //newApplication.Application_Number__c = newAppNumber;
            newApplication.Name = newAppNumber;
            newApplicationsList.add(newApplication);
        }
        if(newApplicationsList.size()>0){
            try{
                insert newApplicationsList;
                resultMap = insertApplicationRelatedRecords(newApplicationsList,listPrograms);
                
            }catch(DMLException e){
                system.debug('Error '+e.getMessage());
                resultMap.put('ERROR','Error while inserting Applications '+e.getMessage());
                
            }
            
            
        }
        return resultMap;
        
    }
    
    private static Decimal parseYearsOfExperience(String value) {
        if (String.isBlank(value)) {
            return 0;
        }
        
        if (value.contains('<')) {
            return 0;
        }
        String cleanedValue = value.replaceAll('[^0-9.]', '');
        
        try {
            return String.isNotBlank(cleanedValue) ? Decimal.valueOf(cleanedValue) : 0;
        } catch (Exception e) {
            return 0;
        }
    }
    
    private static map<String,String> insertApplicationRelatedRecords(List<Application__c> newApplicationsList, List<Program> listPrograms){
        map<String,String> resultMap = new map<String,String>();
        map<String,String> map_ApplicationToProgram = new Map<String,String>();
        map<String,Lead> map_ProgramToLead = new Map<String,Lead>();
        for(Application__c app:newApplicationsList){
            map_ApplicationToProgram.put(app.Id,app.Program__c);
        }
        List<Lead> leadsList = [SELECT XS_YearsOfWorkExperience__c, XS_State__c,Email,FirstName,LastName, Phone,
        XS_City__c, XS_EntranceExamName__c, XS_SPJIMR_PartnerCompany__c, XS_EnterOrganisation__c, Lead_Source__c, LeadSource, XS_Source__c, XS_CurrentDesigination__c, Age__c, XS_Age__c,Program_Master__c,
         XS_College__c, XS_Year__c, XS_HaveYouCompletedYourGraduation__c, XS_CurrentlyStudingIn__c,State,City FROM Lead WHERE Program_Master__c IN :map_ApplicationToProgram.values()];
        
        
        for(Lead l:leadsList){
            map_ProgramToLead.put(l.Program_Master__c,l);
        }
        
        List<Personal_Detail__c> insertPersonalDetails = new List<Personal_Detail__c>();
        
        List<Work_Experience__c> insertWorkExperience = new List<Work_Experience__c>();
        List<Information_Source__c> insertInformationSource = new List<Information_Source__c>();
        List<Professional_Qualification__c> insertProfessionalQualification = new List<Professional_Qualification__c>();
        
        for(Id AppId:map_ApplicationToProgram.keySet()){
            
            Personal_Detail__c  newPersonalDetail = new Personal_Detail__c(First_Name__c = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.FirstName,
            Last_Name__c = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.LastName,
            Primary_E_mail__c = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.Email,
            Age_as_on_Customisable_Date__c = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.Age__c,
            Application__c = AppId,
            Mobile_Number__c  = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.Phone
            // Corr_City__c=map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.XS_City__c,
            // Corr_State__c =map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.XS_State__c
                );
            
            // Address_Information_Application__c newAddressInfo = new Address_Information_Application__c(
            //     Application__c = AppId,
            // State__c = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.State,
            // City_Correspondence__c = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.City);
            
            
            Work_Experience__c newWorkExperience = new Work_Experience__c(
                Application__c	= AppId,    Do_You_Have_Any_Work_Experience__c = 'Yes',
            //             Total_Experience_In_Months__c  = Integer.valueOf(String.isNotBlank(map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.XS_YearsOfWorkExperience__c))
            // ? parseYearsOfExperience(map_ProgramToLead.get(map_ApplicationToProgram.get(AppId)).XS_YearsOfWorkExperience__c)
            // : 0,
            Designation__c = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.XS_CurrentDesigination__c,
            Working_with_SPJIMR_Partner_Company__c = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId)).XS_SPJIMR_PartnerCompany__c!=null?true:false,
            Name_of_Organisation__c = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.XS_EnterOrganisation__c
                );
            
            String infoSource1 = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId)).Lead_Source__c;
            String infoSource2 = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId)).LeadSource;
            String infoSource3 = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId)).XS_Source__c;
            
            String resSource = infoSource1;
            if (resSource == null) resSource = infoSource2;
            if (resSource == null) resSource = infoSource3;
            
            Information_Source__c infoSource = new Information_Source__c(
                Application__c = AppId,
            Lead__c = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.Id,
            How_Did_you_get_to_know_about_SPJIMR__c = resSource
                );
            
            Professional_Qualification__c newQualification = new Professional_Qualification__c(
                Application__c = AppId,
            Name_of_Institute__c = map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.XS_College__c/*,
            Year_of_Passing_pq__c = String.isNotBlank(map_ProgramToLead.get(map_ApplicationToProgram.get(AppId))?.XS_Year__c)
                ? Decimal.valueOf(map_ProgramToLead.get(map_ApplicationToProgram.get(AppId)).XS_Year__c)
                : 0*/ );
            
            insertPersonalDetails.add(newPersonalDetail);
            //insertAddressInfo.add(newAddressInfo);
            insertInformationSource.add(infoSource);
            insertWorkExperience.add(newWorkExperience);
           // insertProfessionalQualification.add(newQualification);
            
        }
        try{
            if(insertPersonalDetails.size()>0){
                insert insertPersonalDetails;
            }
            // if(insertAddressInfo.size()>0){
            //     insert insertAddressInfo;
            // }
            if(insertInformationSource.size()>0){
                insert insertInformationSource;
            }
            if(insertWorkExperience.size()>0){
                insert insertWorkExperience;
            }
            // if(insertProfessionalQualification.size()>0){
                 // insert insertProfessionalQualification;
            // }
            resultMap.put('SUCCESS',' Inserted Application,RelatedRecords and User');
            return resultMap;
            
        }catch(DmlException e){
            resultMap.put('ERROR',' Inserting Application related Records'+e.getMessage());
            return resultMap;
        }
        
        
    }
    
    
    
    private static String createNickname(String LastNameValue, String EmailValue){
        
        String res2 = LastNameValue.length() >= 2 ? LastNameValue.left(2) : '';
        String res3 = String.valueOf(Integer.valueOf(Math.random()*1000)) ;
        
        return res3+res2;
    }
    
    private static void assignPermissionSet(String assigneeId){
        PermissionSet ApplicantPermissionSet1 = [SELECT Id,Name FROM PermissionSet WHERE Name = 'ApplicantB2cLogin' LIMIT 1]; 
        PermissionSet ApplicantPermissionSet2 = [SELECT Id FROM PermissionSet WHERE Name = 'ApplicantB2cEducation' LIMIT 1];
                                            
                                                     
        
             PermissionSetAssignment p1 = new PermissionSetAssignment(AssigneeId=assigneeId,PermissionSetId = ApplicantPermissionSet1.Id);
             PermissionSetAssignment p2 = new PermissionSetAssignment(AssigneeId=assigneeId,PermissionSetId = ApplicantPermissionSet2.Id);
             List<PermissionSetAssignment> listInsertAssignments = new List<PermissionSetAssignment>{p1,p2};
             Insert listInsertAssignments;
        
       
    }
    
    
    
    public LeadVerification(String assigneeId) {
        this.assigneeId = assigneeId;
    }
    
    public void execute(QueueableContext context) {
        assignPermissionSet(this.assigneeId);
    }
    
    
    
    
}
public without sharing class ConvertB2CLeadController {
    
    public class ConversionResult {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String message;
        @AuraEnabled public String displayMessage;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public List<Id> opportunityIds;
        @AuraEnabled public List<Id> applicationIds;
    }

    private static Boolean autoApplicationCreationEnabledCache;

    public static Boolean isAutoApplicationCreationEnabled() {
        if (autoApplicationCreationEnabledCache != null) {
            return autoApplicationCreationEnabledCache;
        }

        autoApplicationCreationEnabledCache = true;
        List<SPJIMR_Feature_Flag__mdt> featureFlags = [
            SELECT Auto_Create_Application__c
            FROM SPJIMR_Feature_Flag__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        if (!featureFlags.isEmpty()) {
            autoApplicationCreationEnabledCache = featureFlags[0].Auto_Create_Application__c;
        }

        return autoApplicationCreationEnabledCache;
    }
    
    public static List<String> generateApplicationNumbersInBulk(List<String> programCodesList) {
        List<String> applicationNumbers = new List<String>();
        String intakeYear = String.valueOf(Date.today().year());
        
        Set<String> uniqueProgramCodes = new Set<String>();
        for (String code : programCodesList) {
            if (String.isNotBlank(code)) {
                uniqueProgramCodes.add(code);
            }
        }
        
        Map<String, Sequence_Master__c> existingSequences = new Map<String, Sequence_Master__c>();
        for (Sequence_Master__c seq : [
            SELECT Id, Last_Used_Number__c, Program_Code__c, Year__c
            FROM Sequence_Master__c
            WHERE Program_Code__c IN :uniqueProgramCodes
            AND Year__c = :intakeYear
        ]) {
            existingSequences.put(seq.Program_Code__c, seq);
        }
        
        List<Sequence_Master__c> sequencesToInsert = new List<Sequence_Master__c>();
        Set<String> processedNewCodes = new Set<String>();
        
        for (String programCode : programCodesList) {
            if (String.isBlank(programCode)) {
                applicationNumbers.add(null);
                continue;
            }
            
            Sequence_Master__c seqRecord;
            
            if (existingSequences.containsKey(programCode)) {
                seqRecord = existingSequences.get(programCode);
                seqRecord.Last_Used_Number__c = seqRecord.Last_Used_Number__c + 1;
            } else {
                if (!processedNewCodes.contains(programCode)) {
                    seqRecord = new Sequence_Master__c();
                    seqRecord.Name = programCode + '-' + intakeYear;
                    seqRecord.Program_Code__c = programCode;
                    seqRecord.Year__c = intakeYear;
                    seqRecord.Last_Used_Number__c = 1;
                    sequencesToInsert.add(seqRecord);
                    existingSequences.put(programCode, seqRecord);
                    processedNewCodes.add(programCode);
                } else {
                    seqRecord = existingSequences.get(programCode);
                    seqRecord.Last_Used_Number__c = seqRecord.Last_Used_Number__c + 1;
                }
            }
            
            String paddedNum = leftPadNumber(seqRecord.Last_Used_Number__c, 5);
            applicationNumbers.add(programCode + intakeYear + paddedNum);
        }
        
        if (!sequencesToInsert.isEmpty()) {
            insert sequencesToInsert;
        }
        
        List<Sequence_Master__c> sequencesToUpdate = new List<Sequence_Master__c>();
        for (Sequence_Master__c seq : existingSequences.values()) {
            if (seq.Id != null) {
                sequencesToUpdate.add(seq);
            }
        }
        if (!sequencesToUpdate.isEmpty()) {
            update sequencesToUpdate;
        }
        
        return applicationNumbers;
    }
    
    private static String leftPadNumber(Decimal num, Integer length) {
        if (num == null) num = 0;
        String numStr = String.valueOf(Integer.valueOf(num));
        while (numStr.length() < length) {
            numStr = '0' + numStr;
        }
        return numStr;
    }
    
    private static void insertApplicationRelatedRecords(List<Application__c> applications, Lead leadRecord, String email, String userId) {
        List<Personal_Detail__c> personalDetails = new List<Personal_Detail__c>();
        
        for (Application__c app : applications) {
            Personal_Detail__c pd = new Personal_Detail__c();
            pd.Application__c = app.Id;
            pd.First_Name__c = leadRecord.FirstName;
            pd.Last_Name__c = leadRecord.LastName;
            pd.Primary_E_mail__c = String.isNotBlank(email) ? email : leadRecord.Email;
            pd.Mobile_Number__c = leadRecord.Phone;
            pd.Age_as_on_Customisable_Date__c = String.isNotBlank(leadRecord.XS_Age__c) ? Decimal.valueOf(leadRecord.XS_Age__c) : null;
            pd.OwnerId = userId;
            personalDetails.add(pd);
            
        }
        
        if (!personalDetails.isEmpty()) {
            insert personalDetails;
        }

    }

    private static void insertApplicationRelatedRecordsFromAccount(
        List<Application__c> applications,
        Account accountRecord,
        String UserId
    ) {
        List<Personal_Detail__c> personalDetails = new List<Personal_Detail__c>();
       

        for (Application__c app : applications) {
            Personal_Detail__c pd = new Personal_Detail__c();
            pd.Application__c = app.Id;
            pd.First_Name__c = accountRecord.FirstName;
            pd.Last_Name__c = accountRecord.LastName;
            pd.Primary_E_mail__c = accountRecord.PersonEmail;
            pd.Mobile_Number__c = String.isNotBlank(accountRecord.PersonMobilePhone) ? accountRecord.PersonMobilePhone : accountRecord.Phone;
            pd.Age_as_on_Customisable_Date__c = null;
            pd.OwnerId = UserId;
            personalDetails.add(pd);
        }

        if (!personalDetails.isEmpty()) {
            insert personalDetails;
        }
        
    }
    
    @AuraEnabled
    public static ConversionResult convertB2CLead(Id leadId, String email) {
        ConversionResult result = new ConversionResult();
        result.opportunityIds = new List<Id>();
        result.applicationIds = new List<Id>();
        
        Savepoint sp = Database.setSavepoint();
        
        try {
            Lead leadRecord = [
                SELECT Id, FirstName, LastName, Email, Phone, Status, IsConverted,
                       Company, LeadSource, Date_Of_Birth__c, XS_Age__c,
                       XS_YearsOfWorkExperience__c, XS_EntranceExamName__c,
                       XS_DoYouHaveEntranceExamScore__c, Publisher_Name__c,
                       XS_HowDidYouFindOutAboutUs__c, Street, City, State, PostalCode, Country,
                       Country_Master_backend__c, Country_Master_backend__r.Name,
                       State_Master__c, State_Master__r.Name,
                       District_City__c, District_City__r.Name
                FROM Lead 
                WHERE Id = :leadId 
                LIMIT 1
            ];
            
            if (leadRecord.IsConverted) {
                result.isSuccess = false;
                result.message = 'Lead is already converted.';
                result.displayMessage = 'You have already verified, '+
                'please log into the application portal';
                return result;
            }
            
            List<Lead_Program__c> leadPrograms = [
                SELECT Id, Program__c, Program__r.Name, Program__r.Program_Code__c,
                       Program__r.ParentProgramId, Lead_Source__c,OwnerId
                FROM Lead_Program__c
                WHERE Lead__c = :leadId
            ];
            
            if (leadPrograms.isEmpty()) {
                result.isSuccess = false;
                result.message = 'No programs found for this lead. Please add at least one program before converting.';
                return result;
            }
            
            Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
            
            LeadStatus convertStatus = [
                SELECT Id, MasterLabel 
                FROM LeadStatus 
                WHERE IsConverted = true 
                LIMIT 1
            ];
            
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(leadId);
            lc.setConvertedStatus(convertStatus.MasterLabel);
            lc.setDoNotCreateOpportunity(true);
            
            Database.LeadConvertResult lcr = Database.convertLead(lc);
            
            if (!lcr.isSuccess()) {
                String errorMessages = '';
                for (Database.Error err : lcr.getErrors()) {
                    errorMessages += err.getMessage() + ' ';
                }
                result.isSuccess = false;
                result.message = 'Lead conversion failed: ' + errorMessages;
                return result;
            }
            
            result.accountId = lcr.getAccountId();
            result.contactId = lcr.getContactId();
            
            // First update: Change RecordType only (Person Account limitation)
            Account accRecordType = new Account(
                Id = lcr.getAccountId(),
                RecordTypeId = applicantRtId
            );
            update accRecordType;
            
            // Second update: Update all other fields
            Account acc = new Account(
                Id = lcr.getAccountId(),
                Phone = leadRecord.Phone,
                PersonMobilePhone = leadRecord.Phone,
                PersonEmail = String.isNotBlank(email) ? email : leadRecord.Email,
                PersonBirthdate = leadRecord.Date_Of_Birth__c,
                Date_Of_Birth__c = leadRecord.Date_Of_Birth__c,
                BillingStreet = leadRecord.Street,
                BillingCity = leadRecord.District_City__r != null ? leadRecord.District_City__r.Name : leadRecord.City,
                BillingState = leadRecord.State_Master__r != null ? leadRecord.State_Master__r.Name : leadRecord.State,
                BillingPostalCode = leadRecord.PostalCode,
                BillingCountry = leadRecord.Country_Master_backend__r != null ? leadRecord.Country_Master_backend__r.Name : leadRecord.Country,
                PersonMailingStreet = leadRecord.Street,
                PersonMailingCity = leadRecord.District_City__r != null ? leadRecord.District_City__r.Name : leadRecord.City,
                PersonMailingState = leadRecord.State_Master__r != null ? leadRecord.State_Master__r.Name : leadRecord.State,
                PersonMailingPostalCode = leadRecord.PostalCode,
                PersonMailingCountry = leadRecord.Country_Master_backend__r != null ? leadRecord.Country_Master_backend__r.Name : leadRecord.Country,
                Country_Master__c = leadRecord.Country_Master_backend__c,
                State_Master__c = leadRecord.State_Master__c,
                District_City__c = leadRecord.District_City__c,
                Entrance_Exam_Name__c = leadRecord.XS_EntranceExamName__c,
                Has_Entrance_Exam_Score__c = leadRecord.XS_DoYouHaveEntranceExamScore__c,
                Publisher_Name__c = leadRecord.Publisher_Name__c
                // Years_Of_Work_Experience__c = String.isNotBlank(leadRecord.XS_YearsOfWorkExperience__c) 
                //     ? Decimal.valueOf(leadRecord.XS_YearsOfWorkExperience__c) 
                //     : null
            );
            update acc;
              List<AccountShare> shares = new List<AccountShare>();
            Map<Id, Program> programById = new Map<Id, Program>();
            List<String> orderedProgramIds = new List<String>();
            List<String> programmeNames = new List<String>();
            for (Lead_Program__c lp : leadPrograms) {
                shares.add(new AccountShare(
                    AccountId = acc.Id,
                    UserOrGroupId = lp.OwnerId,
                    AccountAccessLevel = 'Read',
                    OpportunityAccessLevel = 'Read',
                    CaseAccessLevel = 'Read',
                    RowCause = Schema.AccountShare.RowCause.Manual
                ));
                programById.put(lp.Program__c, lp.Program__r);
                orderedProgramIds.add(String.valueOf(lp.Program__c));
                 if (lp.Program__r != null &&
                    String.isNotBlank(lp.Program__r.Name)) {
                    programmeNames.add(lp.Program__r.Name);
                }
            }
            programmeNames = new List<String>(new Set<String>(programmeNames));

String formattedProgrammeNames =
    ApplicantWelcomeEmailQueue.formatProgrammeList(programmeNames);
            if(!shares.isEmpty()){
                try{
                    insert shares;
                }
                catch(DMLException e){
                    system.debug('Cannot Insert Account Share Record: '+e.getMessage());
                }
            }

          
            Map<String, String> userResult = createCommunityUser(lcr.getAccountId(),formattedProgrammeNames);
            if (userResult.containsKey('ERROR')) {
                result.isSuccess = false;
                result.message =
                    'Lead converted but community user creation failed: ' + userResult.get('ERROR');
                return result;
            }
            
            
            Map<Id, List<Program>> familyGroups = B2CProgramParentHelper.groupSelectedProgramsByFamily(
                orderedProgramIds,
                programById
            );

            Set<Id> programIdsForNames = new Set<Id>();
            for (List<Program> grp : familyGroups.values()) {
                Id oppProgId = B2CProgramParentHelper.opportunityAndApplicationProgramId(grp);
                if (oppProgId != null) {
                    programIdsForNames.add(oppProgId);
                }
            }
            for (Id pid : programIdsForNames) {
                if (!programById.containsKey(pid)) {
                    for (Program row : [
                        SELECT Id, Name, Program_Code__c, ParentProgramId
                        FROM Program
                        WHERE Id = :pid
                        LIMIT 1
                    ]) {
                        programById.put(row.Id, row);
                    }
                }
            }

            Id b2cOppRtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                .get('B2C_Opportunity')
                .getRecordTypeId();

            List<Opportunity> opportunitiesToInsert = new List<Opportunity>();
            Map<Id, Opportunity> familyKeyToOpportunity = new Map<Id, Opportunity>();

            for (List<Program> members : familyGroups.values()) {
                if (members == null || members.isEmpty()) {
                    continue;
                }
                Id programIdForOpp = B2CProgramParentHelper.opportunityAndApplicationProgramId(members);
                Program nameSource = programById.get(programIdForOpp);
                String programDisplayName = nameSource != null && String.isNotBlank(nameSource.Name)
                    ? nameSource.Name
                    : 'Program';

                Id reuseAppId = B2CProgramParentHelper.findReusableApplicationForParentFamily(
                    lcr.getAccountId(),
                    members[0].Id
                );

                Opportunity opp = new Opportunity();
                opp.AccountId = lcr.getAccountId();
                opp.Name = leadRecord.FirstName + ' ' + leadRecord.LastName + ' - ' + programDisplayName;
                opp.StageName = 'Email Verified';
                opp.CloseDate = Date.today().addDays(90);
                opp.Program__c = programIdForOpp;
                Lead_Program__c sourceLp;
                for (Lead_Program__c lp : leadPrograms) {
                    if (lp.Program__c == members[0].Id) {
                        sourceLp = lp;
                        break;
                    }
                }
                opp.LeadSource = sourceLp != null && sourceLp.Lead_Source__c != null
                    ? sourceLp.Lead_Source__c
                    : leadRecord.LeadSource;
                opp.RecordTypeId = b2cOppRtId;
                if (reuseAppId != null) {
                    opp.Application__c = reuseAppId;
                }

                opp.B2C_Program_Code__c = nameSource != null && String.isNotBlank(nameSource.Program_Code__c)
                    ? nameSource.Program_Code__c.trim()
                    : null;

                opportunitiesToInsert.add(opp);
                familyKeyToOpportunity.put(B2CProgramParentHelper.familyGroupKey(members[0]), opp);
            }

            insert opportunitiesToInsert;
             EmailTemplate et = [
    SELECT Id
    FROM EmailTemplate
    WHERE DeveloperName = 'SPJIMR_New_User_VF'
    LIMIT 1
];
//             System.enqueueJob(
//     new ApplicantWelcomeEmailQueue(
//         (Id)userResult.get('USERID')
//     )
// );
    System.resetPasswordWithEmailTemplate((Id)userResult.get('USERID'), true, 'SPJIMR_New_User_VF');
            for (Opportunity opp : opportunitiesToInsert) {
                result.opportunityIds.add(opp.Id);
            }

            if (lcr.getContactId() != null) {
                List<OpportunityContactRole> ocrList = new List<OpportunityContactRole>();
                for (Opportunity opp : opportunitiesToInsert) {
                    OpportunityContactRole ocr = new OpportunityContactRole();
                    ocr.OpportunityId = opp.Id;
                    ocr.ContactId = lcr.getContactId();
                    ocr.IsPrimary = true;
                    ocr.Role = 'Decision Maker';
                    ocrList.add(ocr);
                }
                insert ocrList;
            }

            Boolean autoCreateApplications = isAutoApplicationCreationEnabled();
            Integer createdApplicationCount = 0;
            if (autoCreateApplications) {
                List<Application__c> applicationsToInsert = new List<Application__c>();
                List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
                List<String> programCodesForNumbers = new List<String>();
                List<Id> programIdForAppList = new List<Id>();
                List<Lead_Program__c> sourceLpPerApp = new List<Lead_Program__c>();

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
                    Program progRow = programById.get(programIdForApp);
                    programCodesForNumbers.add(progRow != null ? progRow.Program_Code__c : null);
                    programIdForAppList.add(programIdForApp);

                    Lead_Program__c sourceLp;
                    for (Lead_Program__c lp : leadPrograms) {
                        if (lp.Program__c == members[0].Id) {
                            sourceLp = lp;
                            break;
                        }
                    }
                    sourceLpPerApp.add(sourceLp);
                    opportunitiesToUpdate.add(opp);
                }

                List<String> applicationNumbers = generateApplicationNumbersInBulk(programCodesForNumbers);
                String userId = userResult.get('USERID');
                for (Integer idx = 0; idx < programIdForAppList.size(); idx++) {
                    Lead_Program__c sourceLp = idx < sourceLpPerApp.size() ? sourceLpPerApp[idx] : null;

                    Application__c app = new Application__c();
                    app.Applicant__c = lcr.getAccountId();
                    app.Program__c = programIdForAppList[idx];
                    app.LeadSource__c = sourceLp != null && sourceLp.Lead_Source__c != null
                        ? sourceLp.Lead_Source__c
                        : leadRecord.LeadSource;
                    app.HasExamScores__c = leadRecord.XS_DoYouHaveEntranceExamScore__c=='Yes'?
                    'Yes':'No';
                    
                    app.OwnerId = userId;
                    if (idx < applicationNumbers.size() && applicationNumbers[idx] != null) {
                        app.Name = applicationNumbers[idx];
                    }

                    applicationsToInsert.add(app);
                }

                if (!applicationsToInsert.isEmpty()) {
                    insert applicationsToInsert;
                    insertApplicationRelatedRecords(applicationsToInsert, leadRecord, email,userId);
                }

                for (Application__c app : applicationsToInsert) {
                    result.applicationIds.add(app.Id);
                }

                for (Integer i = 0; i < opportunitiesToUpdate.size(); i++) {
                    opportunitiesToUpdate[i].Application__c = applicationsToInsert[i].Id;
                }
                if (!opportunitiesToUpdate.isEmpty()) {
                    update opportunitiesToUpdate;
                }
                createdApplicationCount = applicationsToInsert.size();
            }

            result.isSuccess = true;
            if (autoCreateApplications) {
                result.message = 'Lead converted successfully! Created: 1 Account (Applicant), ' +
                    opportunitiesToInsert.size() + ' Opportunity(ies), and ' +
                    createdApplicationCount + ' Application(s). All linked together.';
                result.displayMessage = 'Your email has been verified successfully.'+
                 'Please check your inbox for your login credentials to begin your' +
                 ' application for the ' + formattedProgrammeNames+ ' at SPJIMR.';
            } else {
                result.message = 'Lead converted successfully! Created: 1 Account (Applicant) and ' +
                    opportunitiesToInsert.size() + ' Opportunity(ies). Application creation is set to manual.';
            }
            
        } catch (Exception e) {
            Database.rollback(sp);
            result.isSuccess = false;
            result.message = 'Error converting lead: ' + e.getMessage();
        }
        
        return result;
    }

    @AuraEnabled
    public static Map<String, Object> createApplicationForOpportunity(Id opportunityId) {
        Map<String, Object> response = new Map<String, Object>();
        Savepoint sp = Database.setSavepoint();

        try {
            Opportunity opp = [
                SELECT Id, Name, Program__c, Program__r.Program_Code__c, AccountId, LeadSource, Application__c
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];

            if (opp.Application__c != null) {
                response.put('isSuccess', false);
                response.put('message', 'Application is already linked with this Opportunity.');
                response.put('applicationId', opp.Application__c);
                return response;
            }

            Account acc = [
                SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone, Phone, Years_Of_Work_Experience__c
                FROM Account
                WHERE Id = :opp.AccountId
                LIMIT 1
            ];

            List<User> applicantUserList = [SELECT Id FROM User WHERE ContactId IN (SELECT PersonContactId 
            FROM Account 
            WHERE Id = :opp.AccountId)];
            String UserId = applicantUserList[0].Id;
            String applicationNumber;
            if (String.isNotBlank(opp.Program__r.Program_Code__c)) {
                List<String> applicationNumbers = generateApplicationNumbersInBulk(
                    new List<String>{ opp.Program__r.Program_Code__c }
                );
                applicationNumber = !applicationNumbers.isEmpty() ? applicationNumbers[0] : null;
            }

            Application__c app = new Application__c();
            app.Applicant__c = opp.AccountId;
            app.Program__c = opp.Program__c;
            app.LeadSource__c = opp.LeadSource;
            app.Name = applicationNumber;
            app.OwnerId = UserId;
            insert app;

            insertApplicationRelatedRecordsFromAccount(new List<Application__c>{ app }, acc,UserId);

            opp.Application__c = app.Id;
            update opp;

            response.put('isSuccess', true);
            response.put('message', 'Application and related records created successfully.');
            response.put('applicationId', app.Id);
            return response;
        } catch (Exception e) {
            Database.rollback(sp);
            response.put('isSuccess', false);
            response.put('message', 'Error creating application: ' + e.getMessage());
            return response;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLeadDetails(Id leadId) {
        Map<String, Object> details = new Map<String, Object>();
        
        try {
            Lead leadRecord = [
                SELECT Id, Name, FirstName, LastName, Email, Phone, Company, Status, IsConverted
                FROM Lead 
                WHERE Id = :leadId 
                LIMIT 1
            ];
            
            details.put('lead', leadRecord);
            details.put('isConverted', leadRecord.IsConverted);
            
            List<Lead_Program__c> leadPrograms = [
                SELECT Id, Program__c, Program__r.Name 
                FROM Lead_Program__c 
                WHERE Lead__c = :leadId
            ];
            
            List<Map<String, String>> programs = new List<Map<String, String>>();
            for (Lead_Program__c lp : leadPrograms) {
                programs.add(new Map<String, String>{
                    'id' => lp.Program__c,
                    'name' => lp.Program__r.Name
                });
            }
            details.put('programs', programs);
            details.put('programCount', leadPrograms.size());
            
        } catch (Exception e) {
            details.put('error', e.getMessage());
        }
        
        return details;
    }

    /**
     * Creates a community user for the given Person Account (internal CRM context; direct User insert).
     */
    public static Map<String, String> createCommunityUser(String accountId, String formattedProgrammeNames) {
        Map<String, String> resultMap = new Map<String, String>();
        if (accountId == null) {
            resultMap.put('ERROR', 'No Related Account Found');
            return resultMap;
        }

        List<Account> listPersonAccount = [
            SELECT Id, FirstName, LastName, PersonEmail, PersonContactId
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        if (listPersonAccount.isEmpty()) {
            resultMap.put('ERROR', 'Account not found');
            return resultMap;
        }

        if (String.isBlank(listPersonAccount[0].PersonContactId)) {
            resultMap.put('ERROR', 'Person Contact not found for this Account');
            return resultMap;
        }

        if (String.isBlank(listPersonAccount[0].PersonEmail)) {
            resultMap.put('ERROR', 'Person Email is required to create a community user');
            return resultMap;
        }

        List<User> existingUsers = [
            SELECT Id
            FROM User
            WHERE Email = :listPersonAccount[0].PersonEmail AND IsActive = true
            LIMIT 1
        ];

        if (!existingUsers.isEmpty()) {
            resultMap.put('SUCCESS', 'User already exists');
            resultMap.put('USERID',existingUsers[0].Id);
            return resultMap;
        }

        String nickname =
            String.join(listPersonAccount[0].PersonEmail.split('@'), '') +
            String.valueOf((Integer) (Math.random() * 10000));

        List<Profile> applicantProfiles = [
            SELECT Id
            FROM Profile
            WHERE Name = 'SPJIMR Applicant'
            LIMIT 1
        ];

        if (applicantProfiles.isEmpty()) {
            resultMap.put('ERROR', 'SPJIMR Applicant Profile not found');
            return resultMap;
        }

        Account pa = listPersonAccount[0];
        String aliasFirst = (pa.FirstName != null && pa.FirstName.length() > 0)
            ? pa.FirstName.substring(0, 1)
            : 'U';
        String aliasLast = (pa.LastName != null && pa.LastName.length() > 0)
            ? pa.LastName.substring(0, 1)
            : 'U';

        User u = new User(
            LastName = pa.LastName,
            FirstName = pa.FirstName,
            Email = pa.PersonEmail,
            CommunityNickname = nickname,
            Username = pa.PersonEmail,
            ProfileId = applicantProfiles[0].Id,
            ContactId = pa.PersonContactId,
            Alias = aliasFirst + aliasLast,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Programs_Applied__c = formattedProgrammeNames
        );

        try {
            insert u;
            System.enqueueJob(new PermissionSetAssigner(u.Id));
            System.debug('Successfully created a user with Id ' + u.Id);
            resultMap.put('SUCCESS', 'User Created Successfully');
            resultMap.put('USERID',u.Id);
            return resultMap;
        } catch (DmlException e) {
            System.debug('Error creating user: ' + e.getMessage());
            String errorMsg = 'Error creating user: ';
            for (Integer i = 0; i < e.getNumDml(); i++) {
                errorMsg += e.getDmlMessage(i) + ' ';
            }
            resultMap.put('ERROR', errorMsg);
            return resultMap;
        } catch (Exception e) {
            System.debug('Error creating user: ' + e.getMessage());
            resultMap.put('ERROR', 'Error creating user: ' + e.getMessage());
            return resultMap;
        }
    }

    private static void assignPermissionSet(String assigneeId) {
        List<PermissionSet> permissionSets = [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN ('ApplicantB2cLogin',
            'EducationCloudExprcCloudAccess',
            'ApplicantB2cEducation')
            LIMIT 3
        ];

        if (permissionSets.isEmpty() || permissionSets.size()<3) {
            system.debug('Not all Permission Sets Found!!! '+permissionSets);
            return;
        }
        List<PermissionSetAssignment> insertListPSet = new List<PermissionSetAssignment>();
        insertListPSet.add(new PermissionSetAssignment(
            AssigneeId = assigneeId,
            PermissionSetId = permissionSets[0].Id
        ));
        insertListPSet.add(new PermissionSetAssignment(
            AssigneeId = assigneeId,
            PermissionSetId = permissionSets[1].Id
        ));
        insertListPSet.add(new PermissionSetAssignment(
            AssigneeId = assigneeId,
            PermissionSetId = permissionSets[2].Id
        ));
        if(!insertListPSet.isEmpty()){
            insert insertListPSet;
        }
        // insert new PermissionSetAssignment(
        //     AssigneeId = assigneeId,
        //     PermissionSetId = permissionSets[0].Id
        // );
    }

    public class PermissionSetAssigner implements Queueable {
        private String assigneeId;

        public PermissionSetAssigner(Id assigneeId) {
            this.assigneeId = assigneeId != null ? String.valueOf(assigneeId) : null;
        }

        public void execute(QueueableContext context) {
            if (String.isNotBlank(assigneeId)) {
                assignPermissionSet(assigneeId);
            }
        }
    }
}
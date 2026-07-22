/**
 * Orchestrates B2B Lead conversion: loads lead context for the LWC and performs
 * post-convert Account/Opportunity/Contract setup after {@code Database.convertLead}.
 */
public with sharing class ConvertB2BLeadController {
     
    public class ConversionResult {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String message;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public List<Id> contractIds;
    }
    
    /**
     * Converts a B2B lead to Account/Contact via {@code Database.convertLead}, then creates
     * the main Opportunity and optional program contracts when MOU/contract is required.
     *
     * @param leadId Lead to convert.
     * @param isMouContractRequired When true, draft contracts are created (two per program) and linked to the main Opportunity; when false, no contracts are created.
     * @return Outcome with created record Ids or an error message.
     */
    @AuraEnabled
    public static ConversionResult convertB2BLead(Id leadId, Boolean isMouContractRequired) {
        ConversionResult result = new ConversionResult();
        result.contractIds = new List<Id>();
        
        Savepoint sp = Database.setSavepoint();
        
        try {
            Lead leadRecord = [
                SELECT Id, FirstName, LastName, Email, Phone, Status, IsConverted,
                       Company, LeadSource, Title, Industry, Website, NumberOfEmployees,
                       Street, City, State, PostalCode, Country, Description,
                       Opportunity_Name__c, Opportunity_Amount__c, 
                       Opportunity_Close_Date__c, Opportunity_Stage__c,
                       Is_MOU_Contract_Required__c,
                       Minimum_Number_of_Students__c, Maximum_Number_of_Students__c,
                       Country_Master_backend__c, State_Master__c, District_City__c
                FROM Lead 
                WHERE Id = :leadId 
                LIMIT 1
            ];
            
            if (leadRecord.IsConverted) {
                result.isSuccess = false;
                result.message = 'Lead is already converted.';
                return result;
            }

            Boolean mouRequired = isMouContractRequired == true;
            leadRecord.Is_MOU_Contract_Required__c = mouRequired;
            update leadRecord;
            
            

            List<Contact> leadContacts = [
                SELECT Id,FirstName,LastName,Email,Designation__c,
                Department_Master__c,Phone,MobilePhone,Is_Primary_Contact__c,
                (
                    SELECT Id,
                    Program__r.Name,
                    Program__c
                    FROM Lead_Programmes__r
                )
                FROM Contact 
                WHERE Lead__c = :leadId
            ];


            
            if (leadContacts.isEmpty()) {
                result.isSuccess = false;
                result.message = 'No programs found for this lead\'s. Please add at least one program before converting.';
                return result;
            }
            Contact primaryContact;
            for(Contact c:leadContacts){
                if(c.Is_Primary_Contact__c){
                    primaryContact = c;
                    break;
                }
            }
            Id businessRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Business').getRecordTypeId();
            
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
            // if(primaryContact!=null){
            //     lc.setContactId(primaryContact.Id);
            // }
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
            
            Account acc = new Account(
                Id = lcr.getAccountId(),
                RecordTypeId = businessRtId
            );
            update acc;

            Contact con = new Contact(
                Id = lcr.getContactId(),
                Is_Primary_Contact__c=true
            );
            update con;
            List<Contact> updateContacts = new List<Contact>();
            for(Contact lcs:leadContacts){

                // Contact c = new contact(AccountId = acc.Id,Phone=lcs.Phone__c,
                // FirstName = lcs.Name,LastName = lcs.Last_Name__c,MobilePhone = lcs.MobilePhone__c,
                // Email=lcs.Email__c, Title=lcs.Designation__c,
                // Department_Master__c = lcs.Department__c,Is_Primary_Contact__c=lcs.Primary_Contact__c);

                //lcs.Lead__c = null;
                lcs.AccountId = acc.Id;

                updateContacts.add(lcs);
            }
            update updateContacts;

            // for(Integer i=0; i<leadContacts.size(); i++){
            //     leadContactToContact.put(
            //         leadContacts[i].Id,
            //         updateContacts[i]
            //     );
            // }

            Pricebook2 standardPb = [
                SELECT Id
                FROM Pricebook2
                WHERE IsStandard = true
                LIMIT 1
            ];
            
            List<Opportunity> oppsToInsert = new List<Opportunity>();
            Map<Id, Opportunity> leadContactToOpp = new Map<Id, Opportunity>();

            for(Contact conRec : leadContacts){

                // Contact conRec = leadContactToContact.get(lcs.Id);

                Opportunity opp = new Opportunity(
                    AccountId = acc.Id,
                    
                    Name = conRec.FirstName + ' ' +
                        conRec.LastName + ' - ' +
                        leadRecord.Company,
                    Amount = leadRecord.Opportunity_Amount__c,
                    CloseDate = leadRecord.Opportunity_Close_Date__c != null
                        ? leadRecord.Opportunity_Close_Date__c
                        : Date.today().addDays(90),
                    StageName = String.isNotBlank(leadRecord.Opportunity_Stage__c)
                        ? leadRecord.Opportunity_Stage__c
                        : 'Prospecting',
                    Pricebook2Id = standardPb.Id,
                    LeadSource = leadRecord.LeadSource,
                    Description = leadRecord.Description
                );

                oppsToInsert.add(opp);
            }

        insert oppsToInsert;
                for(Integer i=0; i<leadContacts.size(); i++){
                leadContactToOpp.put(
                leadContacts[i].Id,
                oppsToInsert[i]
            );
        }

        List<Contract> contractsToInsert = new List<Contract>();

        for(Contact lcs : leadContacts){

            Opportunity opp = leadContactToOpp.get(lcs.Id);

            for(Lead_Program__c lp : lcs.Lead_Programmes__r){

                Contract contract1 = new Contract(
                    AccountId = acc.Id,
                    Status = 'Draft',
                    StartDate = Date.today(),
                    ContractTerm = 12,
                    Program_Course__c = lp.Program__c,
                    Minimum_Number_of_Students__c = leadRecord.Minimum_Number_of_Students__c,
                    Maximum_Number_of_Students__c = leadRecord.Maximum_Number_of_Students__c,
                    Description = 'Contract 1 for ' + lp.Program__r.Name
                );

                contractsToInsert.add(contract1);

                Contract contract2 = new Contract(
                    AccountId = acc.Id,
                    Status = 'Draft',
                    StartDate = Date.today(),
                    ContractTerm = 12,
                    Program_Course__c = lp.Program__c,
                    Minimum_Number_of_Students__c = leadRecord.Minimum_Number_of_Students__c,
                    Maximum_Number_of_Students__c = leadRecord.Maximum_Number_of_Students__c,
                    Description = 'Contract 2 for ' + lp.Program__r.Name
                );

                contractsToInsert.add(contract2);
            }
        }

                if(mouRequired && !contractsToInsert.isEmpty()){
            insert contractsToInsert;
        }
//             Contact chk = [
//     SELECT Id, Is_Primary_Contact__c
//     FROM Contact
//     WHERE Id = :lcr.getContactId()
// ];

// System.debug('Primary = ' + chk.Is_Primary_Contact__c);
//             String oppName = String.isNotBlank(leadRecord.Opportunity_Name__c) 
//                 ? leadRecord.Opportunity_Name__c 
//                 : leadRecord.Company + ' - Opportunity';
//             Pricebook2 standardPb = [
//             SELECT Id
//             FROM Pricebook2
//             WHERE IsStandard = true
//             LIMIT 1
//             ];
//             Opportunity mainOpp = new Opportunity();
//             mainOpp.AccountId = lcr.getAccountId();
//             mainOpp.Name = oppName;
//             mainOpp.Amount = leadRecord.Opportunity_Amount__c;
//             mainOpp.CloseDate = leadRecord.Opportunity_Close_Date__c != null 
//                 ? leadRecord.Opportunity_Close_Date__c 
//                 : Date.today().addDays(90);
//             mainOpp.StageName = String.isNotBlank(leadRecord.Opportunity_Stage__c) 
//                 ? leadRecord.Opportunity_Stage__c 
//                 : 'Prospecting';
//             mainOpp.LeadSource = leadRecord.LeadSource;
//             mainOpp.Description = leadRecord.Description;
            
//             mainOpp.Pricebook2Id = standardPb.Id;
//             insert mainOpp;
//             result.opportunityId = mainOpp.Id;
            
//             if (lcr.getContactId() != null) {
//                 OpportunityContactRole ocr = new OpportunityContactRole();
//                 ocr.OpportunityId = mainOpp.Id;
//                 ocr.ContactId = lcr.getContactId();
//                 ocr.IsPrimary = true;
//                 ocr.Role = 'Decision Maker';
//                 insert ocr;
//             }
            
//             Decimal minStudents = leadRecord.Minimum_Number_of_Students__c;
//             Decimal maxStudents = leadRecord.Maximum_Number_of_Students__c;
            
//             List<Contract> contractsToInsert = new List<Contract>();
            
//             if (mouRequired) {
//                 for (Lead_Program__c lp : leadPrograms) {
//                     Contract contract1 = new Contract();
//                     contract1.AccountId = lcr.getAccountId();
//                     contract1.Status = 'Draft';
//                     contract1.StartDate = Date.today();
//                     contract1.ContractTerm = 12;
//                     contract1.Program_Course__c = lp.Program__c;
//                     contract1.Minimum_Number_of_Students__c = minStudents;
//                     contract1.Maximum_Number_of_Students__c = maxStudents;
//                     contract1.Description = 'Contract 1 for ' + lp.Program__r.Name;
//                     contractsToInsert.add(contract1);
                    
//                     Contract contract2 = new Contract();
//                     contract2.AccountId = lcr.getAccountId();
//                     contract2.Status = 'Draft';
//                     contract2.StartDate = Date.today();
//                     contract2.ContractTerm = 12;
//                     contract2.Program_Course__c = lp.Program__c;
//                     contract2.Minimum_Number_of_Students__c = minStudents;
//                     contract2.Maximum_Number_of_Students__c = maxStudents;
//                     contract2.Description = 'Contract 2 for ' + lp.Program__r.Name;
//                     contractsToInsert.add(contract2);
//                 }
                
//                 insert contractsToInsert;
                
//                 for (Contract c : contractsToInsert) {
//                     result.contractIds.add(c.Id);
//                 }
                
//                 mainOpp.ContractId = contractsToInsert[0].Id;
//                 update mainOpp;
//             }
            
            result.isSuccess = true;
            if (contractsToInsert.isEmpty()) {
                result.message = 'Lead converted successfully! Created: 1 Account, and '+String.valueOf(oppsToInsert.size())+'  Opportunity(ies).';
            } else {
                result.message = 'Lead converted successfully! Created: 1 Account,'+String.valueOf(oppsToInsert.size())+'  Opportunity(ies), and ' + 
                               contractsToInsert.size() + ' Contract(s) (' + (contractsToInsert.size()/2) + ' per program).';
            }
            
        } catch (Exception e) {
            Database.rollback(sp);
            result.isSuccess = false;
            result.message =
        e.getMessage() +
        ' | LINE: ' + e.getLineNumber() +
        ' | STACK: ' + e.getStackTraceString();

         System.debug(result.message);
        }
        
        return result;
    }
    
    /**
     * Loads lead, program lines, and related display fields for the convert UI.
     *
     * @param leadId Lead record Id.
     * @return Map with {@code lead}, {@code programs}, counts, and optional {@code error} message.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLeadDetails(Id leadId) {
        Map<String, Object> details = new Map<String, Object>();
        
        try {
            Lead leadRecord = [
                SELECT Id, Name, FirstName, LastName, Email, Phone, Company, Status, IsConverted,
                       Opportunity_Amount__c, Opportunity_Close_Date__c,
                       Minimum_Number_of_Students__c, Maximum_Number_of_Students__c,
                       Is_MOU_Contract_Required__c
                FROM Lead 
                WHERE Id = :leadId 
                LIMIT 1
            ];
            
            details.put('lead', leadRecord);
            details.put('isConverted', leadRecord.IsConverted);
            details.put('company', leadRecord.Company);
            details.put('opportunityAmount', leadRecord.Opportunity_Amount__c);
            details.put('minStudents', leadRecord.Minimum_Number_of_Students__c);
            details.put('maxStudents', leadRecord.Maximum_Number_of_Students__c);
            details.put('isMouRequired', leadRecord.Is_MOU_Contract_Required__c);
            
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
}
public with sharing class ConvertLeadInvocable {
    
    public class ConvertLeadRequest {
        @InvocableVariable(label='Lead ID' required=true)
        public Id leadId;
        
        @InvocableVariable(label='MOU Contract Required' required=true)
        public Boolean isMouContractRequired;
    }
    
    public class ConvertLeadResult {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
        
        @InvocableVariable(label='Message')
        public String message;
        
        @InvocableVariable(label='Account ID')
        public Id accountId;
        
        @InvocableVariable(label='Contact ID')
        public Id contactId;
        
        @InvocableVariable(label='Opportunity ID')
        public Id opportunityId;
        
        @InvocableVariable(label='Contract ID')
        public Id contractId;
    }
    
    @InvocableMethod(label='Convert B2B Lead' description='Converts a B2B Lead to Account, Contact, and Opportunities based on selected Programs')
    public static List<ConvertLeadResult> convertLead(List<ConvertLeadRequest> requests) {
        List<ConvertLeadResult> results = new List<ConvertLeadResult>();
       Savepoint sp = Database.setSavepoint();
        for (ConvertLeadRequest request : requests) {
            ConvertLeadResult result = new ConvertLeadResult();
            
            try {
                // Get Lead with Opportunity fields
                Lead leadRecord = [
                    SELECT Id, Status, IsConverted, Company, LeadSource,
                           Opportunity_Name__c, Opportunity_Amount__c, 
                           Opportunity_Close_Date__c, Opportunity_Stage__c,
                           Is_MOU_Contract_Required__c,RecordType.DeveloperName,
                           Minimum_Number_of_Students__c, Maximum_Number_of_Students__c
                    FROM Lead 
                    WHERE Id = :request.leadId 
                    LIMIT 1
                ];
                
                if (leadRecord.IsConverted) {
                    result.isSuccess = false;
                    result.message = 'Lead is already converted.';
                    results.add(result);
                    continue;
                }
                
                // Get Opportunity values from Lead
                //String opportunityName = leadRecord.Opportunity_Name__c;
                Decimal opportunityAmount = leadRecord.Opportunity_Amount__c;
                Date closeDate = leadRecord.Opportunity_Close_Date__c;
                String stage = leadRecord.Opportunity_Stage__c;
                Boolean isMouContractRequired = request.isMouContractRequired;
                String leadSource = leadRecord.LeadSource;
                Decimal minStudents = leadRecord.Minimum_Number_of_Students__c;
                Decimal maxStudents = leadRecord.Maximum_Number_of_Students__c;
                
                // Get Programs from Lead_Program__c junction object
                List<Contact> leadContacts = [
    SELECT Id,
           FirstName,
           LastName,
           Email,
           Phone,
           MobilePhone,
           Title,
           Department_Master__c,
           Is_Primary_Contact__c,
           (
               SELECT Id,
                      Program__c,
                      Program__r.Name,
                      Program__r.Program_Code__c
               FROM Lead_Programmes__r
           )
    FROM Contact
    WHERE Lead__c = :request.leadId
];
                if(leadContacts.isEmpty()){
                    result.isSuccess = false;
                    result.message = 'At least one Lead Contact is required.';
                    results.add(result);
                    continue;
                }
                Set<Id> leadContactIds = new Set<Id>();
                for(Contact  leadCon:leadContacts){
                    leadContactIds.add(leadCon.Id);
                }
                List<Lead_Program__c> leadPrograms = [
                           SELECT Id,
                                Contact__c,
                                Program__c,
                                Program__r.Name,
                                Program__r.Program_Code__c
                            FROM Lead_Program__c
                            WHERE Contact__c IN :leadContactIds
                        ];
                
                List<String> programIds = new List<String>();
                Map<Id, String> programNameMap = new Map<Id, String>();
                Map<Id, String> programCodeMap = new Map<Id, String>();
                for (Lead_Program__c lp : leadPrograms) {
                    programIds.add(lp.Program__c);
                    programNameMap.put(lp.Program__c, lp.Program__r.Name);
                    programCodeMap.put(lp.Program__c, lp.Program__r.Program_Code__c);
                }
                
                // Get Account Record Type
                Id companyRtId = [SELECT Id FROM RecordType
                                WHERE SobjectType='Account'
                                AND DeveloperName='LeadCompany'
                                LIMIT 1].Id;
                
                // Get Converted Status
                LeadStatus convertStatus = [SELECT Id, MasterLabel FROM LeadStatus WHERE IsConverted = true AND MasterLabel = 'Partner' LIMIT 1];
                Contact primaryContact;
                
                for(Contact  leadContact : leadContacts){
                    if(leadContact.Is_Primary_Contact__c){
                        primaryContact = leadContact;
                        break;
                    }
                }
                // Convert Lead
                Database.LeadConvert lc = new Database.LeadConvert();
                lc.setLeadId(request.leadId);
                lc.setConvertedStatus(convertStatus.MasterLabel);
                lc.setDoNotCreateOpportunity(true);
                // if(primaryContact != null){
                //     lc.setContactId(primaryContact.Id);
                // }
                Database.LeadConvertResult lcr = Database.convertLead(lc);
                
                if (lcr.isSuccess()) {
                    result.accountId = lcr.getAccountId();
                    result.contactId = lcr.getContactId();
                    
                    // Force Account RecordType after conversion
                    update new Account(
                        Id = lcr.getAccountId(),
                    RecordTypeId = companyRtId
                        );
                    
                    
                    if(primaryContact == null && !leadContacts.isEmpty()){
                        primaryContact = leadContacts[0];
                    }
                    
                    delete new Contact(
                        Id = lcr.getContactId()
                    
                        );
                    
                    Boolean hasPrograms = !programIds.isEmpty();
                    
                    
                    Map<Id, List<Lead_Program__c>> contactPrograms =
                        new Map<Id, List<Lead_Program__c>>();
                    for(Lead_Program__c lp : leadPrograms){
                        
                        if(!contactPrograms.containsKey(lp.Contact__c)){
                            contactPrograms.put(
                                lp.Contact__c,
                            new List<Lead_Program__c>()
                                );
                        }
                        
                        contactPrograms.get(lp.Contact__c).add(lp);
                    }
                    
                    List<Contact> contactsToUpdate = new List<Contact>();
                    
                    
                    for(Contact leadContact : leadContacts){
                        contactsToUpdate.add(
                            new Contact(
                            Id = leadContact.Id,
                        AccountId = lcr.getAccountId()
                            )
                            );
                    }
                    
                    
                    update contactsToUpdate;
                    
                    
                    Integer contactIndex = 0;
                    
                    for(Contact  leadContact : leadContacts){
                        
                        if(primaryContact != null &&
                        leadContact.Id == primaryContact.Id){
                            continue;
                        }
                        
                        
                        contactIndex++;
                    }
                    
                    List<Opportunity> oppsToInsert = new List<Opportunity>();
                    
                    List<Pricebook2> priceBook = [SELECT Id
                                                    FROM Pricebook2
                                                    WHERE IsStandard = true
                                                    LIMIT 1];
                    Id standardPricebookId = Test.isRunningTest()?Test.getStandardPricebookId():priceBook[0].Id;
                             
                    Id b2bOppRt = Schema.SObjectType.Opportunity
                        .getRecordTypeInfosByDeveloperName()
                        .get('B2B_Opportunity')
                        .getRecordTypeId();
                    
                    for(Contact conRec : leadContacts){
                        
                        Opportunity opp = new Opportunity(
                            AccountId = lcr.getAccountId(),
                        Name = conRec.FirstName + ' ' +
                            conRec.LastName + ' - ' +
                            leadRecord.Company,
                        Amount = leadRecord.Opportunity_Amount__c,
                        CloseDate = leadRecord.Opportunity_Close_Date__c != null
                            ? leadRecord.Opportunity_Close_Date__c
                            : Date.today().addDays(30),
                        StageName = String.isNotBlank(leadRecord.Opportunity_Stage__c)
                            ? leadRecord.Opportunity_Stage__c
                            : 'Prospecting',
                        LeadSource = leadRecord.LeadSource,
                        Is_MOU_Contract_Required__c = isMouContractRequired,
                        Pricebook2Id = standardPricebookId,
                        RecordTypeId = b2bOppRt
                            );
                        
                        oppsToInsert.add(opp);
                    }
                    
                    insert oppsToInsert;
                    system.debug('Inserting Opportunities: '+oppsToInsert);
                    Map<Id, Opportunity> contactToOpp = new Map<Id, Opportunity>();
                    
                    for(Integer i = 0; i < leadContacts.size(); i++){
                        contactToOpp.put(
                            leadContacts[i].Id,
                        oppsToInsert[i]
                            );
                    }
                    
                    List<OpportunityContactRole> ocrs = new List<OpportunityContactRole>();
                    
                    for(Contact conRec : leadContacts){
                        
                        Opportunity opp = contactToOpp.get(conRec.Id);
                        
                        ocrs.add(
                            new OpportunityContactRole(
                            OpportunityId = opp.Id,
                        ContactId = conRec.Id,
                        IsPrimary = true,
                        Role = 'Decision Maker'
                            )
                            );
                    }
                    
                    insert ocrs;
                    
                    Set<String> requiredProgramCodes = new Set<String>();
                    
                    for(Lead_Program__c lp : leadPrograms){
                        if(String.isNotBlank(lp.Program__r.Program_Code__c)){
                            requiredProgramCodes.add(lp.Program__r.Program_Code__c);
                        }
                    }
                    
                    Map<String, PricebookEntry> programCodeToPbeMap =
                        new Map<String, PricebookEntry>();
                    
                    for(PricebookEntry pbe : [
    SELECT Id,
           UnitPrice,
           Product2.ProductCode
    FROM PricebookEntry
    WHERE Pricebook2Id = :standardPricebookId
    AND IsActive = true
    AND Product2.IsActive = true
    AND Product2.ProductCode IN :requiredProgramCodes
]){
                        programCodeToPbeMap.put(
                            pbe.Product2.ProductCode,
                        pbe
                            );
                    }
                    
                    
                    
                    List<OpportunityLineItem> lineItemsToInsert =
                        new List<OpportunityLineItem>();
                    
                    for(Contact conRec : leadContacts){
                        
                        Opportunity opp = contactToOpp.get(conRec.Id);
                        
                        List<Lead_Program__c> programs =
                            contactPrograms.get(conRec.Id);
                        
                        if(programs == null){
                            continue;
                        }
                        
                        for(Lead_Program__c lp : programs){
                            
                            String programCode = lp.Program__r.Program_Code__c;
                            
                            if(String.isBlank(programCode)){
                                Database.rollback(sp);
                                throw new AuraHandledException(
                                    'Program Code missing for Program: ' +
                                    lp.Program__r.Name
                                    );
                            }
                            
                            PricebookEntry pbe = programCodeToPbeMap.get(programCode);
                            
                            if(pbe == null){
                                    result.isSuccess = false;
                                    result.message = 'Error converting Lead: ' + 'Program "' + lp.Program__r.Name +
                                    '" is not mapped to an active Product in the Standard Pricebook. ' +
                                    'Program Code: ' + programCode;
                                    results.add(result);
                                    Database.rollback(sp);
                                     
                                    return results;
                            }
                            
                            lineItemsToInsert.add(
                                new OpportunityLineItem(
                                OpportunityId = opp.Id,
                            PricebookEntryId = pbe.Id,
                            Quantity = 1,
                            UnitPrice = pbe.UnitPrice
                                )
                                );
                        }
                    }
                    
                    if(!lineItemsToInsert.isEmpty()){
                        insert lineItemsToInsert;
                    }
                    
                    result.isSuccess = true;
                    
                    if(!oppsToInsert.isEmpty()){
                        result.opportunityId = oppsToInsert[0].Id;
                    }
                    
                    result.message =
                        'Lead converted successfully! Created: 1 Account, ' +
                        leadContacts.size() +
                        ' Contact(s), ' +
                        oppsToInsert.size() +
                        ' Opportunity(ies), and ' +
                        lineItemsToInsert.size() +
                        ' Opportunity Line Item(s).';
                    
                } else {
                    result.isSuccess = false;
                    String errorMessages = '';
                    for (Database.Error err : lcr.getErrors()) {
                        errorMessages += err.getMessage() + ' ';
                    }
                    result.message = 'Lead conversion failed: ' + errorMessages;
                }
                
            } catch (Exception e) {
                Database.rollback(sp);
                result.isSuccess = false;
                result.message = 'Error converting Lead: ' + e.getMessage();
            }
            
            results.add(result);
        }
        
        return results;
    }
}
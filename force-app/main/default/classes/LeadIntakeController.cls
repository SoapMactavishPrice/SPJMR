public with sharing class LeadIntakeController {

    public class IntakeResult {
        @AuraEnabled public String action;        // 'LEAD_CREATED', 'OPP_CREATED_EXISTING', 'OPP_CREATED_CONVERTED'
        @AuraEnabled public String leadId;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String contactId;
        @AuraEnabled public String opportunityId;
        @AuraEnabled public String message;
    }

    public class LeadInput {
        @AuraEnabled public String recordType;     // 'B2B' or 'B2C'
        @AuraEnabled public String salutation;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String company;
        @AuraEnabled public String title;
        @AuraEnabled public String industry;
        @AuraEnabled public Integer numberOfEmployees;
        @AuraEnabled public Decimal annualRevenue;
        @AuraEnabled public String website;
        @AuraEnabled public String leadSource;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String country;
        @AuraEnabled public String description;
        @AuraEnabled public String rating;
        @AuraEnabled public String programInterest;
        @AuraEnabled public String programType;
        @AuraEnabled public Date dateOfBirth;
        @AuraEnabled public String gender;
        @AuraEnabled public String linkedin;
        @AuraEnabled public String panNumber;
        @AuraEnabled public Boolean emailOptOut;
        @AuraEnabled public Decimal revenueEstimate;
        @AuraEnabled public String department;
    }

    @AuraEnabled
    public static Map<String, String> getRecordTypeIds() {
        Map<String, String> rtMap = new Map<String, String>();
        for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE SObjectType = 'Lead' AND IsActive = true]) {
            rtMap.put(rt.DeveloperName, rt.Id);
        }
        return rtMap;
    }

    @AuraEnabled
    public static Map<String, List<Map<String, String>>> getPicklistValues() {
        Map<String, List<Map<String, String>>> result = new Map<String, List<Map<String, String>>>();

        result.put('Salutation', getPicklistOptions(Lead.Salutation.getDescribe()));
        result.put('Industry', getPicklistOptions(Lead.Industry.getDescribe()));
        result.put('LeadSource', getPicklistOptions(Lead.LeadSource.getDescribe()));
        result.put('Rating', getPicklistOptions(Lead.Rating.getDescribe()));
        result.put('Country__c', getPicklistOptions(Lead.Country__c.getDescribe()));
        result.put('Program_Picklist__c', getPicklistOptions(Lead.Program_Picklist__c.getDescribe()));
        result.put('Program_Type__c', getPicklistOptions(Lead.Program_Type__c.getDescribe()));
        result.put('GenderIdentity', getPicklistOptions(Lead.GenderIdentity.getDescribe()));

        return result;
    }

    private static List<Map<String, String>> getPicklistOptions(Schema.DescribeFieldResult dfr) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) {
                options.add(new Map<String, String>{
                    'label' => pe.getLabel(),
                    'value' => pe.getValue()
                });
            }
        }
        return options;
    }

    @AuraEnabled
    public static IntakeResult submitLead(LeadInput input) {
        IntakeResult result = new IntakeResult();

        try {
            if (input.recordType == 'B2B') {
                return processB2B(input, result);
            } else {
                return processB2C(input, result);
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static IntakeResult processB2B(LeadInput input, IntakeResult result) {
        Account existingAccount = findMatchingAccount(input.company, input.email, input.website);

        if (existingAccount != null) {
            result.accountId = existingAccount.Id;
            result.accountName = existingAccount.Name;

            Contact existingContact = findMatchingContact(existingAccount.Id, input.email);
            if (existingContact != null) {
                result.contactId = existingContact.Id;
            } else {
                Contact newContact = new Contact(
                    AccountId = existingAccount.Id,
                    Salutation = input.salutation,
                    FirstName = input.firstName,
                    LastName = input.lastName,
                    Email = input.email,
                    Phone = input.phone,
                    Title = input.title,
                    Department = input.department
                );
                insert newContact;
                result.contactId = newContact.Id;
            }

            Opportunity opp = createOpportunity(
                existingAccount.Id,
                result.contactId,
                input,
                'Qualification'
            );
            result.opportunityId = opp.Id;
            result.action = 'OPP_CREATED_EXISTING';
            result.message = 'Company "' + existingAccount.Name + '" already exists. Opportunity created directly on existing Account.';
            return result;
        }

        Lead newLead = buildLead(input, 'B2B');
        insert newLead;
        result.leadId = newLead.Id;
        result.action = 'LEAD_CREATED';
        result.message = 'New B2B Lead created successfully. The lead will go through the qualification process.';
        return result;
    }

    private static IntakeResult processB2C(LeadInput input, IntakeResult result) {
        Contact existingPerson = findMatchingPerson(input.email, input.phone);

        if (existingPerson != null) {
            result.accountId = existingPerson.AccountId;
            result.accountName = existingPerson.Account.Name;
            result.contactId = existingPerson.Id;

            Opportunity existingOpp = findOpenOpportunity(existingPerson.AccountId);
            if (existingOpp != null) {
                result.opportunityId = existingOpp.Id;
                result.action = 'OPP_CREATED_EXISTING';
                result.message = 'This person already exists with an open Opportunity. Linked to existing record.';
                return result;
            }

            Opportunity opp = createOpportunity(
                existingPerson.AccountId,
                existingPerson.Id,
                input,
                'Prospecting'
            );
            result.opportunityId = opp.Id;
            result.action = 'OPP_CREATED_EXISTING';
            result.message = 'Person already exists. New Opportunity created on existing Person Account.';
            return result;
        }

        Lead newLead = buildLead(input, 'B2C');
        insert newLead;
        result.leadId = newLead.Id;
        result.action = 'LEAD_CREATED';
        result.message = 'New B2C Lead created successfully. The lead will go through engagement scoring.';
        return result;
    }

    @AuraEnabled
    public static IntakeResult convertLead(String leadId) {
        IntakeResult result = new IntakeResult();
        try {
            Lead ld = [SELECT Id, FirstName, LastName, Company, Email, Status FROM Lead WHERE Id = :leadId AND IsConverted = false LIMIT 1];

            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(leadId);
            lc.setConvertedStatus('Submitted');

            Account matchedAccount = findMatchingAccount(ld.Company, ld.Email, null);
            if (matchedAccount != null) {
                lc.setAccountId(matchedAccount.Id);
            }

            Database.LeadConvertResult lcr = Database.convertLead(lc);

            result.action = 'OPP_CREATED_CONVERTED';
            result.leadId = leadId;
            result.accountId = lcr.getAccountId();
            result.contactId = lcr.getContactId();
            result.opportunityId = lcr.getOpportunityId();
            result.message = 'Lead successfully converted! Account, Contact, and Opportunity have been created.';
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Conversion failed: ' + e.getMessage());
        }
    }

    private static Account findMatchingAccount(String companyName, String email, String website) {
        String emailDomain = '';
        if (String.isNotBlank(email) && email.contains('@')) {
            emailDomain = '%' + email.substringAfter('@') + '%';
        }

        List<Account> matches = new List<Account>();

        if (String.isNotBlank(companyName)) {
            matches = [
                SELECT Id, Name, Website, OwnerId
                FROM Account
                WHERE Name = :companyName
                LIMIT 1
            ];
        }

        if (matches.isEmpty() && String.isNotBlank(emailDomain)) {
            matches = [
                SELECT Id, Name, Website, OwnerId
                FROM Account
                WHERE Website LIKE :emailDomain
                LIMIT 1
            ];
        }

        if (matches.isEmpty() && String.isNotBlank(website)) {
            matches = [
                SELECT Id, Name, Website, OwnerId
                FROM Account
                WHERE Website = :website
                LIMIT 1
            ];
        }

        return matches.isEmpty() ? null : matches[0];
    }

    private static Contact findMatchingContact(String accountId, String email) {
        if (String.isBlank(email)) return null;
        List<Contact> contacts = [
            SELECT Id, Name, Email
            FROM Contact
            WHERE AccountId = :accountId AND Email = :email
            LIMIT 1
        ];
        return contacts.isEmpty() ? null : contacts[0];
    }

    private static Contact findMatchingPerson(String email, String phone) {
        List<Contact> matches = new List<Contact>();

        if (String.isNotBlank(email)) {
            matches = [
                SELECT Id, AccountId, Account.Name, FirstName, LastName, Email
                FROM Contact
                WHERE Email = :email
                LIMIT 1
            ];
        }

        if (matches.isEmpty() && String.isNotBlank(phone)) {
            matches = [
                SELECT Id, AccountId, Account.Name, FirstName, LastName, Email
                FROM Contact
                WHERE Phone = :phone
                LIMIT 1
            ];
        }

        return matches.isEmpty() ? null : matches[0];
    }

    private static Opportunity findOpenOpportunity(String accountId) {
        List<Opportunity> opps = [
            SELECT Id, Name, StageName
            FROM Opportunity
            WHERE AccountId = :accountId AND IsClosed = false
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return opps.isEmpty() ? null : opps[0];
    }

    private static Opportunity createOpportunity(String accountId, String contactId, LeadInput input, String stage) {
        String oppName = (input.recordType == 'B2B' ? input.company : input.firstName + ' ' + input.lastName)
                         + ' - '
                         + (String.isNotBlank(input.programInterest) ? input.programInterest : 'New Opportunity');

        Opportunity opp = new Opportunity(
            AccountId = accountId,
            Name = oppName,
            StageName = stage,
            CloseDate = Date.today().addDays(90),
            Description = input.description,
            LeadSource = input.leadSource,
            Amount = input.revenueEstimate
        );
        insert opp;

        if (String.isNotBlank(contactId)) {
            OpportunityContactRole ocr = new OpportunityContactRole(
                OpportunityId = opp.Id,
                ContactId = contactId,
                IsPrimary = true,
                Role = 'Decision Maker'
            );
            insert ocr;
        }

        return opp;
    }

    private static Lead buildLead(LeadInput input, String type) {
        Map<String, String> rtIds = getRecordTypeIds();

        Lead ld = new Lead(
            RecordTypeId = rtIds.get(type),
            Salutation = input.salutation,
            FirstName = input.firstName,
            LastName = input.lastName,
            Email = input.email,
            Phone = input.phone,
            Company = input.company,
            Title = input.title,
            Industry = input.industry,
            NumberOfEmployees = input.numberOfEmployees,
            AnnualRevenue = input.annualRevenue,
            Website = input.website,
            LeadSource = input.leadSource,
            Street = input.street,
            City = input.city,
            State = input.state,
            PostalCode = input.postalCode,
            Country = input.country,
            Description = input.description,
            Rating = input.rating,
            Program_Picklist__c = input.programInterest,
            Program_Type__c = input.programType,
            Date_Of_Birth__c = input.dateOfBirth,
            GenderIdentity = input.gender,
            Linkedin__c = input.linkedin,
            PAN_Number__c = input.panNumber,
            HasOptedOutOfEmail = input.emailOptOut != null ? input.emailOptOut : false,
            Revenue_Estimate__c = input.revenueEstimate,
            Department__c = input.department,
            Status = 'Untouched'
        );

        if (type == 'B2C' && String.isBlank(input.company)) {
            ld.Company = input.firstName + ' ' + input.lastName + ' (Individual)';
        }

        return ld;
    }
}
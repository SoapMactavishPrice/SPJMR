public without sharing class B2BLeadProcessController {
    private static Id getStandardPricebookId() {
        if(Test.isRunningTest()){
            return Test.getStandardPricebookId();
        }
        return [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
    }

    private static Map<Id, PricebookEntry> getProgramPricebookEntries(Set<Id> programIds, Id pricebookId) {
        Map<Id, PricebookEntry> programToPbe = new Map<Id, PricebookEntry>();
        if (programIds == null || programIds.isEmpty()) {
            return programToPbe;
        }

        Map<Id, Program> programsById = new Map<Id, Program>([
            SELECT Id, Name
            FROM Program
            WHERE Id IN :programIds
        ]);

        Set<String> programNames = new Set<String>();
        for (Program p : programsById.values()) {
            if (String.isNotBlank(p.Name)) {
                programNames.add(p.Name);
            }
        }

        Map<String, PricebookEntry> pbeByProductName = new Map<String, PricebookEntry>();
        if (!programNames.isEmpty()) {
            for (PricebookEntry pbe : [
                SELECT Id, UnitPrice, Product2.Name
                FROM PricebookEntry
                WHERE Pricebook2Id = :pricebookId
                AND IsActive = true
                AND Product2.IsActive = true
                AND Product2.Name IN :programNames
            ]) {
                if (!pbeByProductName.containsKey(pbe.Product2.Name)) {
                    pbeByProductName.put(pbe.Product2.Name, pbe);
                }
            }
        }

        for (Id programId : programsById.keySet()) {
            Program p = programsById.get(programId);
            if (p != null && pbeByProductName.containsKey(p.Name)) {
                programToPbe.put(programId, pbeByProductName.get(p.Name));
            }
        }

        return programToPbe;
    }

    /**
     * Opportunity record type for all B2B lead creation and conversion flows.
     *
     * @return B2B_Opportunity record type Id, or null if unavailable in the org.
     */
    public static Id getB2BOpportunityRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> byDevName = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();
        if (!byDevName.containsKey('B2B_Opportunity')) {
            return null;
        }
        Schema.RecordTypeInfo rti = byDevName.get('B2B_Opportunity');
        if (rti == null) {
            return null;
        }
        return rti.getRecordTypeId();
    }

    private static void applyB2BOpportunityRecordType(Opportunity opp) {
        Id rtId = getB2BOpportunityRecordTypeId();
        if (rtId != null) {
            opp.RecordTypeId = rtId;
        }
    }
    
    public class AccountCheckResult {
        @AuraEnabled public Boolean accountExists;
        @AuraEnabled public Boolean contactExists;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String scenario;
        
        // Account details
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountIndustry;
        @AuraEnabled public String accountWebsite;
        @AuraEnabled public Integer accountNumberOfEmployees;
        @AuraEnabled public Decimal accountAnnualRevenue;
        @AuraEnabled public String accountPhone;
        @AuraEnabled public String accountBillingStreet;
        @AuraEnabled public String accountBillingCity;
        @AuraEnabled public String accountBillingState;
        @AuraEnabled public String accountBillingPostalCode;
        @AuraEnabled public String accountBillingCountry;
        @AuraEnabled public String accountDescription;
        @AuraEnabled public String accountEmail;
        @AuraEnabled public String accountLinkedIn;
        // Contact details
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactFirstName;
        @AuraEnabled public String contactLastName;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public String contactPhone;
        @AuraEnabled public String contactMobilePhone;
        @AuraEnabled public String contactTitle;
        @AuraEnabled public String contactDepartment;
        @AuraEnabled public Id contactReportsToId;
        
        public AccountCheckResult() {
            this.accountExists = false;
            this.contactExists = false;
            this.scenario = 'CREATE_LEAD';
        }
    }

    /**
     * One row from {@link #searchCompanyMatches} for UI picklists (Lead or Account).
     */
    public class CompanyMatchRow {
        @AuraEnabled public String recordId;
        /** {@code Lead} or {@code Account}. */
        @AuraEnabled public String recordType;
        @AuraEnabled public String name;
        /** Secondary line (e.g. email, status, billing city). */
        @AuraEnabled public String subtitle;
    }

    /**
     * Grouped fuzzy company search results for B2B create flow.
     */
    public class CompanySearchResult {
        @AuraEnabled public List<CompanyMatchRow> leads;
        @AuraEnabled public List<CompanyMatchRow> accounts;

        public CompanySearchResult() {
            this.leads = new List<CompanyMatchRow>();
            this.accounts = new List<CompanyMatchRow>();
        }
    }

    /**
     * Lead field bundle for merging into the B2B form when user selects an existing Lead.
     */
    public class LeadMergePrefill {
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String mobilePhone;
        @AuraEnabled public String title;
        @AuraEnabled public String department;
        @AuraEnabled public String company;
        @AuraEnabled public String website;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String stateId;
        @AuraEnabled public String countryId;
        @AuraEnabled public String cityId{get;set;}
        @AuraEnabled public String postalCode;
        @AuraEnabled public String country;
        @AuraEnabled public String linkedIn;
        @AuraEnabled public String description;
        @AuraEnabled public String leadSource;
        @AuraEnabled public Boolean isMouContractRequired;
        @AuraEnabled public String reportingToContactId;
    }
    
    public class ProcessResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordType;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public Id leadId;
        
        public ProcessResult() {
            this.success = false;
        }
    }

    /**
     * Request body for {@link #mergeB2BLeadWithPrograms} (single parameter to satisfy Apex's 32-argument limit).
     */
    public class MergeB2BLeadRequest {
        @AuraEnabled public Id leadId {get; set;}
        @AuraEnabled public String lastName{get; set;}
        @AuraEnabled public String firstName{get; set;}
        @AuraEnabled public String company{get; set;}
        @AuraEnabled public String email{get; set;}
        @AuraEnabled public String phone{get; set;}
        @AuraEnabled public string designation{get;set;}
        @AuraEnabled public String mobilePhone{get; set;}
        @AuraEnabled public String title{get; set;}
        @AuraEnabled public String department{get; set;}
        @AuraEnabled public String linkedIn{get; set;}
        @AuraEnabled public String contactCountry{get; set;}
        @AuraEnabled public String contactState{get; set;}
        @AuraEnabled public String contactCity{get; set;}
        @AuraEnabled public String industry{get; set;}
        @AuraEnabled public String website{get; set;}
        @AuraEnabled public Integer numberOfEmployees{get; set;}
        @AuraEnabled public Decimal annualRevenue{get; set;}
        @AuraEnabled public String street{get; set;}
        @AuraEnabled public String city{get; set;}
        @AuraEnabled public String state{get; set;}
        @AuraEnabled public String postalCode{get; set;}
        @AuraEnabled public String country{get; set;}
        @AuraEnabled public String description{get; set;}
        @AuraEnabled public String leadSource{get; set;}
        @AuraEnabled public List<String> programIds{get; set;}
        @AuraEnabled public String eventRemarks{get; set;}
        @AuraEnabled public String companyEmail{get;set;}
        @AuraEnabled public String companyLinkedIn{get;set;}
        @AuraEnabled public String companyPhone{get;set;}
    }
    
    /**
     * Populates {@code result} from an Account and optional contact match by email and/or phone signals.
     *
     * @param acc Account row (full field set per B2B check query).
     * @param result Output DTO.
     * @param email Contact email to match on the account, if any.
     * @param matchPhone Optional combined phone string from the UI (e.g. {@code +91 22 1234}).
     * @param matchMobile Optional combined mobile string from the UI (e.g. {@code +91 9876543210}).
     */
    private static void applyAccountAndContactLookup(
        Account acc,
        AccountCheckResult result,
        String email,
        String matchPhone,
        String matchMobile
    ) {
        result.accountExists = true;
        result.accountId = acc.Id;
        result.accountName = acc.Name;
        result.accountIndustry = acc.Industry;
        result.accountWebsite = acc.Website;
        result.accountNumberOfEmployees = acc.NumberOfEmployees;
        result.accountAnnualRevenue = acc.AnnualRevenue;
        result.accountPhone = acc.Phone;
        result.accountBillingStreet = acc.BillingStreet;
        result.accountBillingCity = acc.BillingCity;
        result.accountBillingState = acc.BillingState;
        result.accountBillingPostalCode = acc.BillingPostalCode;
        result.accountBillingCountry = acc.BillingCountry;
        result.accountDescription = acc.Description;
        result.accountEmail = acc.PersonEmail;
        result.accountLinkedIn = acc.LinkedIn__c;
        if (String.isNotBlank(email)) {
            List<Contact> contacts = [
                SELECT Id, Name, FirstName, LastName, Email, Phone, MobilePhone, Title, Department, ReportsToId
                FROM Contact
                WHERE AccountId = :acc.Id
                AND Email = :email
                LIMIT 1
            ];

            if (!contacts.isEmpty()) {
                applyContactMatchToResult(contacts[0], result);
            } else {
                result.scenario = 'CREATE_CONTACT_AND_OPPORTUNITY';
            }
        } else {
            Contact con = findContactByPhoneSignals(acc.Id, matchPhone, matchMobile);
            if (con != null) {
                applyContactMatchToResult(con, result);
            } else {
                result.scenario = 'CREATE_CONTACT_AND_OPPORTUNITY';
            }
        }
    }

    private static void applyContactMatchToResult(Contact con, AccountCheckResult result) {
        result.contactExists = true;
        result.contactId = con.Id;
        result.contactName = con.Name;
        result.contactFirstName = con.FirstName;
        result.contactLastName = con.LastName;
        result.contactEmail = con.Email;
        result.contactPhone = con.Phone;
        result.contactMobilePhone = con.MobilePhone;
        result.contactTitle = con.Title;
        result.contactDepartment = con.Department;
        result.contactReportsToId = con.ReportsToId;
        result.scenario = 'CREATE_OPPORTUNITY_ONLY';
    }

    private static String phoneDigitsOnly(String raw) {
        if (String.isBlank(raw)) {
            return '';
        }
        String digits = '';
        for (Integer i = 0; i < raw.length(); i++) {
            String ch = raw.substring(i, i + 1);
            if (ch.isNumeric()) {
                digits += ch;
            }
        }
        return digits;
    }

    private static Boolean normalizedPhonesMatch(String inputDigits, String storedRaw) {
        if (String.isBlank(inputDigits)) {
            return false;
        }
        String storedDigits = phoneDigitsOnly(storedRaw);
        if (String.isBlank(storedDigits)) {
            return false;
        }
        if (inputDigits == storedDigits) {
            return true;
        }
        if (inputDigits.endsWith(storedDigits) || storedDigits.endsWith(inputDigits)) {
            return true;
        }
        if (inputDigits.length() >= 10 && storedDigits.length() >= 10) {
            if (
                inputDigits.substring(inputDigits.length() - 10) ==
                storedDigits.substring(storedDigits.length() - 10)
            ) {
                return true;
            }
        }
        return false;
    }

    /**
     * Finds a contact on the account whose Phone or MobilePhone matches the given UI strings (digit-normalized).
     */
    private static Contact findContactByPhoneSignals(Id accountId, String matchPhone, String matchMobile) {
        String normPhone = phoneDigitsOnly(matchPhone);
        String normMobile = phoneDigitsOnly(matchMobile);
        if (String.isBlank(normPhone) && String.isBlank(normMobile)) {
            return null;
        }
        List<Contact> candidates = [
            SELECT Id, Name, FirstName, LastName, Email, Phone, MobilePhone, Title, Department, ReportsToId
            FROM Contact
            WHERE AccountId = :accountId
            LIMIT 2000
        ];
        for (Contact c : candidates) {
            if (String.isNotBlank(normMobile)) {
                if (
                    normalizedPhonesMatch(normMobile, c.MobilePhone) ||
                    normalizedPhonesMatch(normMobile, c.Phone)
                ) {
                    return c;
                }
            }
            if (String.isNotBlank(normPhone)) {
                if (
                    normalizedPhonesMatch(normPhone, c.Phone) ||
                    normalizedPhonesMatch(normPhone, c.MobilePhone)
                ) {
                    return c;
                }
            }
        }
        return null;
    }

    /**
     * Strips SOQL LIKE wildcard characters from user input so patterns stay safe without ESCAPE.
     *
     * @param value Raw user input.
     * @return Sanitized substring for use inside {@code %...%} patterns.
     */
    private static String escapeLike(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('\\', ' ').replace('%', ' ').replace('_', ' ').trim();
    }

    /**
     * Simple relevance score for ordering fuzzy name matches (higher is better).
     *
     * @param name Field value (Company or Account Name).
     * @param term Normalized search term (trimmed).
     * @return Score from 0–100.
     */
    private static Integer matchScore(String name, String term) {
        if (String.isBlank(name) || String.isBlank(term)) {
            return 0;
        }
        String n = name.trim().toLowerCase();
        String t = term.trim().toLowerCase();
        if (n.equals(t)) {
            return 100;
        }
        if (n.startsWith(t)) {
            return 85;
        }
        if (n.contains(t)) {
            return 70;
        }
        return 0;
    }

    /**
     * Returns non-converted B2B Leads and Accounts whose name/company matches the typed term (LIKE + ordering).
     *
     * @param searchTerm User input; must be at least 2 characters after trim.
     * @return Separate lists for leads and accounts, each sorted by match score.
     */
    @AuraEnabled
    public static CompanySearchResult searchCompanyMatches(String searchTerm) {
        CompanySearchResult out = new CompanySearchResult();
        String term = searchTerm == null ? '' : searchTerm.trim();
        if (term.length() < 2) {
            return out;
        }

        String sanitized = escapeLike(term);
        if (String.isBlank(sanitized)) {
            return out;
        }
        String likePattern = '%' + sanitized + '%';

        Id b2bRtId = null;
        Map<String, Schema.RecordTypeInfo> byDev = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName();
        if (byDev.containsKey('B2B')) {
            Schema.RecordTypeInfo rti = byDev.get('B2B');
            if (rti != null && rti.isAvailable()) {
                b2bRtId = rti.getRecordTypeId();
            }
        }

        List<Lead> leadRows;
        if (b2bRtId != null) {
            leadRows = [
                SELECT Id, Company, Email, Status
                FROM Lead
                WHERE IsConverted = FALSE
                AND RecordTypeId = :b2bRtId
                AND Company LIKE :likePattern
                LIMIT 50
            ];
        } else {
            leadRows = [
                SELECT Id, Company, Email, Status
                FROM Lead
                WHERE IsConverted = FALSE
                AND Company LIKE :likePattern
                LIMIT 50
            ];
        }

        List<Account> accountRows = [
            SELECT Id, Name, BillingCity
            FROM Account
            WHERE Name LIKE :likePattern
            LIMIT 50
        ];

        List<CompanyMatchSortable> leadWrappers = new List<CompanyMatchSortable>();
        for (Lead l : leadRows) {
            CompanyMatchRow row = new CompanyMatchRow();
            row.recordId = l.Id;
            row.recordType = 'Lead';
            row.name = l.Company;
            String sub = '';
            if (String.isNotBlank(l.Email)) {
                sub = l.Email;
            }
            if (String.isNotBlank(l.Status)) {
                sub = String.isBlank(sub) ? l.Status : sub + ' · ' + l.Status;
            }
            row.subtitle = sub;
            leadWrappers.add(new CompanyMatchSortable(row, l.Company, term));
        }
        leadWrappers.sort();
        for (CompanyMatchSortable w : leadWrappers) {
            out.leads.add(w.row);
        }

        List<CompanyMatchSortable> accountWrappers = new List<CompanyMatchSortable>();
        for (Account a : accountRows) {
            CompanyMatchRow row = new CompanyMatchRow();
            row.recordId = a.Id;
            row.recordType = 'Account';
            row.name = a.Name;
            row.subtitle = a.BillingCity;
            accountWrappers.add(new CompanyMatchSortable(row, a.Name, term));
        }
        accountWrappers.sort();
        for (CompanyMatchSortable w : accountWrappers) {
            out.accounts.add(w.row);
        }

        return out;
    }

    /**
     * Sortable wrapper for ordering company match rows by fuzzy score then name.
     */
    @TestVisible
    private class CompanyMatchSortable implements Comparable {
        CompanyMatchRow row;
        Integer score;
        String sortKey;

       public CompanyMatchSortable(CompanyMatchRow r, String nameForScore, String term) {
            this.row = r;
            this.score = matchScore(nameForScore, term);
            this.sortKey = nameForScore == null ? '' : nameForScore.toLowerCase();
        }

        public Integer compareTo(Object other) {
            CompanyMatchSortable o = (CompanyMatchSortable) other;
            if (this.score != o.score) {
                return o.score - this.score;
            }
            if (this.sortKey < o.sortKey) {
                return -1;
            }
            if (this.sortKey > o.sortKey) {
                return 1;
            }
            return 0;
        }
    }

    @AuraEnabled(cacheable=true)
    public static AccountCheckResult checkAccountAndContact(
        String companyName,
        String email,
        String matchPhone,
        String matchMobile
    ) {
        AccountCheckResult result = new AccountCheckResult();

        if (String.isBlank(companyName)) {
            return result;
        }

        List<Account> accounts = [
            SELECT Id, Name, ParentId, Industry, Website, NumberOfEmployees, AnnualRevenue,
                    BillingStreet, BillingCity, BillingState,PersonEmail,Phone,LinkedIn__c,
                   BillingPostalCode, BillingCountry, Description
            FROM Account
            WHERE Name = :companyName
            LIMIT 1
        ];

        if (!accounts.isEmpty()) {
            applyAccountAndContactLookup(accounts[0], result, email, matchPhone, matchMobile);
        } else {
            result.scenario = 'CREATE_LEAD';
        }

        return result;
    }

    /**
     * Same as {@link #checkAccountAndContact} but resolves the Account by Id (e.g. user picked from fuzzy search).
     *
     * @param accountId Account selected in the UI.
     * @param email Contact email to match.
     * @param matchPhone Combined phone from UI for contact match when email is blank.
     * @param matchMobile Combined mobile from UI for contact match when email is blank.
     * @return Scenario and prefill fields for the details step.
     */
    @AuraEnabled(cacheable=true)
    public static AccountCheckResult checkAccountAndContactForAccountId(
        Id accountId,
        String email,
        String matchPhone,
        String matchMobile
    ) {
        AccountCheckResult result = new AccountCheckResult();
        if (accountId == null) {
            return result;
        }
        List<Account> accounts = [
            SELECT Id, Name, ParentId, Industry, Website, NumberOfEmployees, AnnualRevenue,
                   Phone, BillingStreet, BillingCity, BillingState,PersonEmail,LinkedIn__c,
                   BillingPostalCode, BillingCountry, Description
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (!accounts.isEmpty()) {
            applyAccountAndContactLookup(accounts[0], result, email, matchPhone, matchMobile);
        } else {
            result.scenario = 'CREATE_LEAD';
        }
        return result;
    }

    /**
     * Loads Lead fields to prefill the B2B form when merging into an existing Lead.
     *
     * @param leadId Lead Id (must be B2B / open; caller validates).
     * @return Field map for the form, or null if not found.
     */
    @AuraEnabled(cacheable=true)
    public static LeadMergePrefill getLeadMergePrefill(Id leadId) {
        if (leadId == null) {
            return null;
        }
        List<Lead> rows = [
            SELECT Id, FirstName, LastName, Email, Phone, MobilePhone, Title, Company, Website, Street, City, State,
                   PostalCode, Country, Industry, NumberOfEmployees, AnnualRevenue, LinkedIn__c, Description,
                   LeadSource, Is_MOU_Contract_Required__c,Country_Master_backend__c,
                   State_Master__c,District_City__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return null;
        }
        Lead l = rows[0];
        LeadMergePrefill p = new LeadMergePrefill();
        p.firstName = l.FirstName;
        p.lastName = l.LastName;
        p.email = l.Email;
        p.phone = l.Phone;
        p.mobilePhone = l.MobilePhone;
        p.title = l.Title;
        //p.department = l.Department_Master__c;
        p.company = l.Company;
        p.website = l.Website;
        p.street = l.Street;
        p.city = l.City;
        p.state = l.State;
        p.countryId = l.Country_Master_backend__c;
        p.stateId = l.State_Master__c;
        p.cityId = l.District_City__c;
        p.postalCode = l.PostalCode;
        p.country = l.Country;
        p.linkedIn = l.LinkedIn__c;
        p.description = l.Description;
        p.leadSource = l.LeadSource;
        p.isMouContractRequired = l.Is_MOU_Contract_Required__c;
        //p.reportingToContactId = l.Reporting_To__c != null ? String.valueOf(l.Reporting_To__c) : null;
        return p;
    }
    
    /**
     * Contacts on the account and on ancestor accounts (standard Account Parent field), for Reporting To.
     * Loads up to four parent levels in one query; contacts include Account.Name for UI labels.
     *
     * @param accountId Account whose hierarchy is used.
     * @param excludeContactId Optional contact to omit (e.g. current user contact).
     * @return Contacts ordered by name, up to 500 rows.
     */
    @AuraEnabled(cacheable=true)
    public static List<Contact> getAccountContacts(Id accountId, Id excludeContactId) {
        if (accountId == null) {
            return new List<Contact>();
        }
        List<Account> accRows = [
            SELECT
                Id,
                Parent.Id,
                Parent.Parent.Id,
                Parent.Parent.Parent.Id,
                Parent.Parent.Parent.Parent.Id
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (accRows.isEmpty()) {
            return new List<Contact>();
        }
        Set<Id> accountIds = new Set<Id>();
        Account cursor = accRows[0];
        accountIds.add(cursor.Id);
        Account ancestor = cursor.Parent;
        while (ancestor != null) {
            accountIds.add(ancestor.Id);
            ancestor = ancestor.Parent;
        }
        List<Contact> contacts = [
            SELECT Id, Name, FirstName, LastName, Email, Title, Account.Name
            FROM Contact
            WHERE AccountId IN :accountIds
            ORDER BY Name ASC
            LIMIT 500
        ];
        if (excludeContactId == null) {
            return contacts;
        }
        List<Contact> filtered = new List<Contact>();
        for (Contact c : contacts) {
            if (c.Id != excludeContactId) {
                filtered.add(c);
            }
        }
        return filtered;
    }

    public class CreateLeadRequestWrapper {

    @AuraEnabled public String lastName {get; set;}
    @AuraEnabled public String firstName {get; set;}
    @AuraEnabled public String company{get; set;}
    @AuraEnabled public String email{get; set;}
    @AuraEnabled public String phone{get; set;}
    @AuraEnabled public String mobilePhone{get; set;}
    @AuraEnabled public String title{get; set;}
    @AuraEnabled public String department{get; set;}
    @AuraEnabled public String linkedIn{get; set;}
    @AuraEnabled public String contactCountry{get; set;}
    @AuraEnabled public String contactState{get; set;}
    @AuraEnabled public String contactCity{get; set;}
    @AuraEnabled public String industry{get; set;}
    @AuraEnabled public String website{get; set;}
    @AuraEnabled public Integer numberOfEmployees{get; set;}
    @AuraEnabled public Decimal annualRevenue{get; set;}
    @AuraEnabled public String street{get; set;}
    @AuraEnabled public String city{get; set;}
    @AuraEnabled public String state{get; set;}
    @AuraEnabled public String postalCode{get; set;}
    @AuraEnabled public String country{get; set;}
    @AuraEnabled public String description{get; set;}
    @AuraEnabled public String leadSource{get; set;}
    @AuraEnabled public String isPrimary{get; set;}
    @AuraEnabled public List<String> programIds{get; set;}
    @AuraEnabled public String eventRemarks{get; set;}
    @AuraEnabled public String companyEmail{get;set;}
    @AuraEnabled public String companyLinkedIn{get;set;}
    @AuraEnabled public String companyPhone{get;set;}
}
    
    @AuraEnabled
    public static ProcessResult createLead(
        // String lastName, String firstName, String company, 
        //                                    String email, String phone, String mobilePhone, String title, 
        //                                    String department,
        //                                    String linkedIn, String contactCountry, String contactState, String contactCity,
        //                                    String industry, String website, Integer numberOfEmployees,
        //                                    Decimal annualRevenue, String street, String city,
        //                                    String state, String postalCode, String country,
        //                                    String description, String leadSource, Boolean isMouContractRequired,
        //                                    String opportunityName, 
        //                                    Decimal opportunityAmount, Date closeDate, String stage,
        //                                    Integer minNumberOfStudents, Integer maxNumberOfStudents,
        //                                    Id reportingToContactId,
        //                                    List<String> programIds, String eventRemarks
            CreateLeadRequestWrapper req) {
                System.debug(JSON.serializePretty(req));
        ProcessResult result = new ProcessResult();
        Savepoint sp = Database.setSavepoint();
        
        try {
            Id b2bRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2B').getRecordTypeId();
            system.debug('Req is '+req);
            String city = String.isNotBlank(req.contactCity)
                ? req.contactCity.trim()
                : req.city.trim();

            String state = String.isNotBlank(req.contactState)
                ? req.contactState.trim()
                : req.state.trim();

            String country = String.isNotBlank(req.contactCountry)
                ? req.contactCountry.trim()
                : req.country.trim();

            Id countryId;
            Id stateId;
            Id cityId;

            if (String.isNotBlank(country)) {
                List<Country_Master__c> countries = [
                    SELECT Id
                    FROM Country_Master__c
                    WHERE Name = :country
                    LIMIT 1
                ];
                if (!countries.isEmpty()) {
                    countryId = countries[0].Id;
                }
            }

            if (String.isNotBlank(state) && countryId != null) {
                List<State__c> states = [
                    SELECT Id
                    FROM State__c
                    WHERE Name = :state
                    AND Country_Master__c = :countryId
                    LIMIT 1
                ];
                if (!states.isEmpty()) {
                    stateId = states[0].Id;
                }
            }

            if (String.isNotBlank(city) && stateId != null) {
                List<City__c> cities = [
                    SELECT Id
                    FROM City__c
                    WHERE Name = :city
                    AND State__c = :stateId
                    LIMIT 1
                ];
                if (!cities.isEmpty()) {
                    cityId = cities[0].Id;
                }
            }
            Lead newLead = new Lead();
            newLead.RecordTypeId = b2bRecordTypeId;
            newLead.LastName = '.';
            newLead.FirstName = req.company;
            newLead.Industry = req.industry;
            newLead.Website = req.website;
            newLead.Company = req.company;

            newLead.Industry = req.industry;
            newLead.Website = req.website;
            
            newLead.NumberOfEmployees = req.numberOfEmployees;
            newLead.AnnualRevenue = req.annualRevenue;
            newLead.Street = req.street;
            newLead.City = String.isNotBlank(req.contactCity) ? req.contactCity : req.city;
            newLead.State = String.isNotBlank(req.contactState) ? req.contactState : req.state;
            newLead.PostalCode = req.postalCode;
            newLead.Country = String.isNotBlank(req.contactCountry) ? req.contactCountry : req.country;
            //newLead.Description = req.description;
            newLead.Country_Master_backend__c = countryId;
            newLead.State_Master__c = stateId;
            newLead.District_City__c = cityId;
            newLead.Is_MOU_Contract_Required__c = false;
            newLead.Status = 'Open - Not Contacted';
            newLead.Linkedin__c = String.isNotBlank(req.companyLinkedIn)?req.companyLinkedIn:'';
            newLead.Email = String.isNotBlank(req.companyEmail)?req.companyEmail:'';
            newLead.Phone = String.isNotBlank(req.companyPhone)?req.companyPhone:'';
            insert newLead;

            // Lead_Contact__c leadCon = new Lead_Contact__c();
            // leadCon.Lead__c = newLead.Id;
            // leadCon.Email__c = req.email;
            // leadCon.MobilePhone__c = req.mobilePhone;
            // leadCon.Primary_Contact__c = req.isPrimary=='true'?true:false;
            // leadCon.Designation__c = req.title;
            // leadCon.Department__c = req.department;
            // leadCon.LinkedIn__c = req.linkedIn;
            // leadCon.Lead_Source__c = req.leadSource;
            // leadCon.Event_Remarks__c = req.eventRemarks;
            // leadCon.Last_Name__c = req.lastName;
            // leadCon.Name = req.firstName;
            // insert leadCon;
            Contact leadCon = new Contact();
            leadCon.FirstName = req.firstName;
            leadCon.LastName = String.isNotBlank(req.lastName) ? req.lastName : '.';
            leadCon.Email = req.email;
            leadCon.MobilePhone = req.mobilePhone;
            leadCon.Title = req.title;
            leadCon.Phone = req.phone;
            leadCon.Description = req.description;
            leadCon.Department_Master__c = req.department;
            leadCon.LinkedIn__c = req.linkedIn;
            leadCon.LeadSource = req.leadSource;
            leadCon.Lead__c = newLead.Id;          
            leadCon.Is_Primary_Contact__c = req.isPrimary == 'true';
            leadCon.Event_Remarks__c = req.eventRemarks;
            insert leadCon;
            // Create Lead Program junction records
            if (req.programIds != null && !req.programIds.isEmpty()) {
                List<Lead_Program__c> leadPrograms = new List<Lead_Program__c>();
                for (String programId : req.programIds) {
                    Lead_Program__c lp = new Lead_Program__c();
                    lp.Contact__c = leadCon.Id;
                    lp.Program__c = programId;
                    leadPrograms.add(lp);
                }
                insert leadPrograms;
            }
            
            result.success = true;
            result.message = 'Lead created successfully. Convert the lead to create Account, Contact, and Opportunity.';
            result.recordId = newLead.Id;
            result.recordType = 'Lead';
            result.leadId = newLead.Id;
            
        } catch (Exception e) {
            
            system.debug('Exception '+e.getMessage());
            Database.rollback(sp);
            result.success = false;
            result.message = 'Error creating Lead: ' + e.getMessage();
        }
        
        return result;
    }

    /**
     * Updates an existing open B2B Lead and adds {@link Lead_Program__c} rows for programs not already linked.
     *
     * @param request Field bundle (required; avoids Apex 32-parameter limit).
     * @return Process result pointing at the Lead.
     */
    @AuraEnabled
    public static ProcessResult mergeB2BLeadWithPrograms(MergeB2BLeadRequest request) {
        ProcessResult result = new ProcessResult();
        Savepoint sp = Database.setSavepoint();

        try {
            if (request == null) {
                result.message = 'Request is required.';
                return result;
            }
            Id leadId = request.leadId;
            if (leadId == null) {
                result.message = 'Lead Id is required.';
                return result;
            }

            List<Lead> existingLeads = [
                SELECT Id, IsConverted, RecordType.DeveloperName
                FROM Lead
                WHERE Id = :leadId
                LIMIT 1
            ];
            if (existingLeads.isEmpty()) {
                result.message = 'Lead not found.';
                return result;
            }
            Lead existing = existingLeads[0];
            if (existing.IsConverted) {
                result.message = 'Cannot merge: Lead is already converted.';
                return result;
            }
            if (existing.RecordType == null || existing.RecordType.DeveloperName != 'B2B') {
                result.message = 'Cannot merge: Lead must use the B2B record type.';
                return result;
            }

            String city = String.isNotBlank(request.contactCity)
                ? request.contactCity.trim()
                : request.city.trim();

            String state = String.isNotBlank(request.contactState)
                ? request.contactState.trim()
                : request.state.trim();

            String country = String.isNotBlank(request.contactCountry)
                ? request.contactCountry.trim()
                : request.country.trim();

            Id countryId;
            Id stateId;
            Id cityId;

            if (String.isNotBlank(country)) {
                List<Country_Master__c> countries = [
                    SELECT Id
                    FROM Country_Master__c
                    WHERE Name = :country
                    LIMIT 1
                ];

                if (!countries.isEmpty()) {
                    countryId = countries[0].Id;
                }
            }

            if (String.isNotBlank(state) && countryId != null) {
                List<State__c> states = [
                    SELECT Id
                    FROM State__c
                    WHERE Name = :state
                    AND Country_Master__c = :countryId
                    LIMIT 1
                ];

                if (!states.isEmpty()) {
                    stateId = states[0].Id;
                }
            }

            if (String.isNotBlank(city) && stateId != null) {
                List<City__c> cities = [
                    SELECT Id
                    FROM City__c
                    WHERE Name = :city
                    AND State__c = :stateId
                    LIMIT 1
                ];

                if (!cities.isEmpty()) {
                    cityId = cities[0].Id;
                }
            }

            Lead toUpdate = new Lead(Id = leadId);
            
            
            toUpdate.Industry = request.industry;
            toUpdate.Website = request.website;
            toUpdate.NumberOfEmployees = request.numberOfEmployees;
            toUpdate.AnnualRevenue = request.annualRevenue;
            toUpdate.Street = request.street;
            toUpdate.City = String.isNotBlank(request.contactCity) ? request.contactCity : request.city;
            toUpdate.State = String.isNotBlank(request.contactState) ? request.contactState : request.state;
            toUpdate.PostalCode = request.postalCode;
            toUpdate.Country = String.isNotBlank(request.contactCountry) ? request.contactCountry : request.country;
            toUpdate.Country_Master_backend__c = countryId;
            toUpdate.State_Master__c = stateId;
            toUpdate.District_City__c = cityId;
            //toUpdate.Description = request.description;
            toUpdate.Email = String.isNotBlank(request.companyEmail)?request.companyEmail:toUpdate.Email;
            toUpdate.Phone = String.isNotBlank(request.companyPhone)?request.companyPhone:toUpdate.Phone;
            toUpdate.Linkedin__c = String.isNotBlank(request.companyLinkedIn)?request.companyLinkedIn:toUpdate.Linkedin__c;
            
            update toUpdate;


            // Lead_Contact__c newCon = new Lead_Contact__c();
            // newCon.Name = request.firstName;
            // newCon.Last_Name__c = request.lastName;
            // newCon.Email__c = request.Email;
            // newCon.Department__c = request.department;
            // newCon.Designation__c = request.designation;
            // newCon.Event_Remarks__c = request.eventRemarks;
            // newCon.LinkedIn__c = request.linkedIn;
            // newCon.MobilePhone__c = request.mobilePhone;
            // newCon.Phone__c = request.phone;
            // newCon.Primary_Contact__c = false;
            // newCon.Lead__c = toUpdate.Id;
            // newCon.Lead_Source__c = request.leadSource;
            // newCon.Event_Remarks__c = request.eventRemarks;
            // insert newCon;

            Contact newCon = new Contact();
            newCon.FirstName = request.firstName;
            newCon.LastName = String.isNotBlank(request.lastName) ? request.lastName : '.';
            newCon.Email = request.email;
            newCon.Department = request.department;
            newCon.Title = request.designation;
            newCon.LinkedIn__c = request.linkedIn;
            newCon.MobilePhone = request.mobilePhone;
            newCon.Phone = request.phone;
            newCon.Is_Primary_Contact__c = false;
            newCon.Lead__c = toUpdate.Id;    
            newCon.LeadSource = request.leadSource;
            newCon.Event_Remarks__c = request.eventRemarks;
            newCon.Description = request.description;
            insert newCon;
            

            if (request.programIds != null && !request.programIds.isEmpty()) {
                List<Lead_Program__c> toInsert = new List<Lead_Program__c>();
                for (String programId : request.programIds) {
                    if (String.isNotBlank(programId) ) {
                        Lead_Program__c junction = new Lead_Program__c();
                        junction.Contact__c = newCon.Id;
                        junction.Program__c = programId;
                        toInsert.add(junction);
                    }
                }
                if (!toInsert.isEmpty()) {
                    insert toInsert;
                }
            }

            result.success = true;
            result.message = 'Lead updated, Contact created and program(s) linked successfully.';
            result.recordId = leadId;
            result.recordType = 'Lead';
            result.leadId = leadId;
        } catch (Exception e) {
            system.debug('Exception e'+e.getMessage());
            Database.rollback(sp);
            result.success = false;
            result.message = 'Error updating Lead: ' + e.getMessage();
        }

        return result;
    }
    
    @AuraEnabled
    public static ProcessResult createContactAndOpportunity(Id accountId, String lastName, String firstName,
                                                            String email, String phone, String mobilePhone, String title,
                                                            String department,
                                                            String linkedIn, String contactCountry, String contactState, String contactCity,
                                                            Id reportsToId, String leadSource, Boolean isMouContractRequired,
                                                            String opportunityName, Decimal opportunityAmount,
                                                            Date closeDate, String stage, 
                                                            Integer minNumberOfStudents, Integer maxNumberOfStudents,
                                                            List<String> programIds) {
        ProcessResult result = new ProcessResult();
        Savepoint sp = Database.setSavepoint();
        
        try {
            // First check if Contact with this email already exists under this Account
            Contact existingContact;
            List<Contact> existingContacts = [
                SELECT Id, FirstName, LastName, Email, Phone, Title 
                FROM Contact 
                WHERE AccountId = :accountId AND Email = :email 
                LIMIT 1
            ];
            
            if (!existingContacts.isEmpty()) {
                existingContact = existingContacts[0];
                if (reportsToId != null || String.isNotBlank(department)) {
                    Contact contactToUpdate = new Contact(Id = existingContact.Id);
                    if (reportsToId != null) {
                        contactToUpdate.ReportsToId = reportsToId;
                        existingContact.ReportsToId = reportsToId;
                    }
                    if (String.isNotBlank(department)) {
                        contactToUpdate.Department_Master__c = department;
                    }
                    update contactToUpdate;
                }
            } else {
                // Create new Contact
                Contact newContact = new Contact();
                newContact.AccountId = accountId;
                newContact.LastName = lastName;
                newContact.FirstName = firstName;
                newContact.Email = email;
                newContact.Phone = phone;
                newContact.MobilePhone = mobilePhone;
                newContact.Title = title;
                newContact.LinkedIn__c = linkedIn;
                newContact.MailingCity = contactCity;
                newContact.MailingState = contactState;
                newContact.MailingCountry = contactCountry;
                newContact.ReportsToId = reportsToId;
                newContact.LeadSource = leadSource;
                newContact.Department_Master__c = department;
                insert newContact;
                existingContact = newContact;
            }
            
            List<Opportunity> opportunitiesToInsert = new List<Opportunity>();
            Map<Id, String> programNameMap = new Map<Id, String>();
            
            if (programIds != null && !programIds.isEmpty()) {
                List<Program> programs = [SELECT Id, Name FROM Program WHERE Id IN :programIds];
                for (Program prog : programs) {
                    programNameMap.put(prog.Id, prog.Name);
                }
            }
            
            // Find matching Slabs for each program based on student range
            Map<Id, Id> programToSlabMap = new Map<Id, Id>();
            if (minNumberOfStudents != null && maxNumberOfStudents != null && programIds != null && !programIds.isEmpty()) {
                List<Slab__c> matchingSlabs = [
                    SELECT Id, Program_Master__c, Start_Range__c, End_Range__c
                    FROM Slab__c
                    WHERE Program_Master__c IN :programIds
                    AND Start_Range__c <= :minNumberOfStudents
                    AND End_Range__c >= :maxNumberOfStudents
                ];
                for (Slab__c slab : matchingSlabs) {
                    programToSlabMap.put(slab.Program_Master__c, slab.Id);
                }
            }
            
            // Create Contracts (one per opportunity) if MOU Contract is required
            List<Contract> contractsToInsert = new List<Contract>();
            Map<String, Contract> programToContractMap = new Map<String, Contract>();
           /* if (isMouContractRequired == true) {
                if (programIds != null && !programIds.isEmpty()) {
                    for (String programId : programIds) {
                        Contract newContract = new Contract();
                        newContract.AccountId = accountId;
                        newContract.Status = 'Draft';
                        newContract.StartDate = Date.today();
                        newContract.ContractTerm = 12;
                        newContract.Minimum_Number_of_Students__c = minNumberOfStudents;
                        newContract.Maximum_Number_of_Students__c = maxNumberOfStudents;
                        if (programToSlabMap.containsKey(programId)) {
                            newContract.Slab__c = programToSlabMap.get(programId);
                        }
                        contractsToInsert.add(newContract);
                    }
                } else {
                    Contract newContract = new Contract();
                    newContract.AccountId = accountId;
                    newContract.Status = 'Draft';
                    newContract.StartDate = Date.today();
                    newContract.ContractTerm = 12;
                    newContract.Minimum_Number_of_Students__c = minNumberOfStudents;
                    newContract.Maximum_Number_of_Students__c = maxNumberOfStudents;
                    contractsToInsert.add(newContract);
                }
                insert contractsToInsert;
                
                // Map program IDs to their contracts
                if (programIds != null && !programIds.isEmpty()) {
                    Integer idx = 0;
                    for (String programId : programIds) {
                        programToContractMap.put(programId, contractsToInsert[idx]);
                        idx++;
                    }
                }
            }
            */
            // Create Opportunities with Contract reference (one contract per opportunity)
            if (programIds != null && !programIds.isEmpty()) {
                for (String programId : programIds) {
                    Opportunity newOpportunity = new Opportunity();
                    newOpportunity.AccountId = accountId;
                    if (isMouContractRequired == true && programToContractMap.containsKey(programId)) {
                        newOpportunity.ContractId = programToContractMap.get(programId).Id;
                    }
                    String progName = programNameMap.get(programId);
                    newOpportunity.Name = String.isNotBlank(opportunityName) 
                        ? opportunityName + ' - ' + progName 
                        : lastName + ' - ' + progName;
                    newOpportunity.Amount = opportunityAmount;
                    newOpportunity.CloseDate = closeDate != null ? closeDate : Date.today().addDays(30);
                    newOpportunity.StageName = String.isNotBlank(stage) ? stage : 'Prospecting';
                    newOpportunity.Program__c = programId;
                    newOpportunity.LeadSource = leadSource;
                    // Link Slab if found for this program
                    if (programToSlabMap.containsKey(programId)) {
                        newOpportunity.Slab__c = programToSlabMap.get(programId);
                    }
                    applyB2BOpportunityRecordType(newOpportunity);
                    opportunitiesToInsert.add(newOpportunity);
                }
            } else {
                Opportunity newOpportunity = new Opportunity();
                newOpportunity.AccountId = accountId;
                if (isMouContractRequired == true && !contractsToInsert.isEmpty()) {
                    newOpportunity.ContractId = contractsToInsert[0].Id;
                }
                newOpportunity.Name = String.isNotBlank(opportunityName) ? opportunityName : lastName + ' - Opportunity';
                newOpportunity.Amount = opportunityAmount;
                newOpportunity.CloseDate = closeDate != null ? closeDate : Date.today().addDays(30);
                newOpportunity.StageName = String.isNotBlank(stage) ? stage : 'Prospecting';
                newOpportunity.LeadSource = leadSource;
                applyB2BOpportunityRecordType(newOpportunity);
                opportunitiesToInsert.add(newOpportunity);
            }
            
            insert opportunitiesToInsert;
            
            List<OpportunityContactRole> ocrList = new List<OpportunityContactRole>();
            for (Opportunity opp : opportunitiesToInsert) {
                OpportunityContactRole ocr = new OpportunityContactRole();
                ocr.OpportunityId = opp.Id;
                ocr.ContactId = existingContact.Id;
                ocr.IsPrimary = true;
                ocr.Role = 'Decision Maker';
                ocrList.add(ocr);
            }
            
            insert ocrList;
            
            Integer oppCount = opportunitiesToInsert.size();
            Boolean contactWasCreated = existingContacts.isEmpty();
            result.success = true;
            if (contactWasCreated) {
                result.message = 'Contact and ' + oppCount + ' Opportunity(ies) created successfully under existing Account.';
            } else {
                result.message = oppCount + ' Opportunity(ies) created successfully under existing Account and Contact.';
            }
            result.recordId = opportunitiesToInsert[0].Id;
            result.recordType = 'Opportunity';
            result.accountId = accountId;
            result.contactId = existingContact.Id;
            result.opportunityId = opportunitiesToInsert[0].Id;
            
        } catch (Exception e) {
            Database.rollback(sp);
            result.success = false;
            result.message = 'Error creating Contact and Opportunity: ' + e.getMessage();
        }
        
        return result;
    }
    
    @AuraEnabled
    public static ProcessResult createOpportunityOnly(Id accountId, Id contactId, String leadSource,
                                                      Boolean isMouContractRequired, String opportunityName,
                                                      Decimal opportunityAmount, Date closeDate, String stage,
                                                      Integer minNumberOfStudents, Integer maxNumberOfStudents,
                                                      List<String> programIds, Id reportsToId, String department) {
        ProcessResult result = new ProcessResult();
        Savepoint sp = Database.setSavepoint();
        
        try {
            List<Opportunity> opportunitiesToInsert = new List<Opportunity>();
            Map<Id, String> programNameMap = new Map<Id, String>();
            
            if (programIds != null && !programIds.isEmpty()) {
                List<Program> programs = [SELECT Id, Name FROM Program WHERE Id IN :programIds];
                for (Program prog : programs) {
                    programNameMap.put(prog.Id, prog.Name);
                }
            }
            
            // Find matching Slabs for each program based on student range
            Map<Id, Id> programToSlabMap = new Map<Id, Id>();
            if (minNumberOfStudents != null && maxNumberOfStudents != null && programIds != null && !programIds.isEmpty()) {
                List<Slab__c> matchingSlabs = [
                    SELECT Id, Program_Master__c, Start_Range__c, End_Range__c
                    FROM Slab__c
                    WHERE Program_Master__c IN :programIds
                    AND Start_Range__c <= :minNumberOfStudents
                    AND End_Range__c >= :maxNumberOfStudents
                ];
                if(matchingSlabs.isEmpty()){
                    result.success = false;
                    result.message = 'No Matching Slabs Found for this programme';
                    return result;
                }
                for (Slab__c slab : matchingSlabs) {
                    programToSlabMap.put(slab.Program_Master__c, slab.Id);
                }
            }
            
            // Create Contracts (one per opportunity) if MOU Contract is required
            List<Contract> contractsToInsert = new List<Contract>();
            Map<String, Contract> programToContractMap = new Map<String, Contract>();
          /*  if (isMouContractRequired == true) {
                if (programIds != null && !programIds.isEmpty()) {
                    for (String programId : programIds) {
                        Contract newContract = new Contract();
                        newContract.AccountId = accountId;
                        newContract.Status = 'Draft';
                        newContract.StartDate = Date.today();
                        newContract.ContractTerm = 12;
                        newContract.Minimum_Number_of_Students__c = minNumberOfStudents;
                        newContract.Maximum_Number_of_Students__c = maxNumberOfStudents;
                        if (programToSlabMap.containsKey(programId)) {
                            newContract.Slab__c = programToSlabMap.get(programId);
                        }
                        contractsToInsert.add(newContract);
                    }
                } else {
                    Contract newContract = new Contract();
                    newContract.AccountId = accountId;
                    newContract.Status = 'Draft';
                    newContract.StartDate = Date.today();
                    newContract.ContractTerm = 12;
                    newContract.Minimum_Number_of_Students__c = minNumberOfStudents;
                    newContract.Maximum_Number_of_Students__c = maxNumberOfStudents;
                    contractsToInsert.add(newContract);
                }
                insert contractsToInsert;
                
                // Map program IDs to their contracts
                if (programIds != null && !programIds.isEmpty()) {
                    Integer idx = 0;
                    for (String programId : programIds) {
                        programToContractMap.put(programId, contractsToInsert[idx]);
                        idx++;
                    }
                }
            }
           */
            
            // Create Opportunities with Contract reference (one contract per opportunity)
            if (programIds != null && !programIds.isEmpty()) {
                for (String programId : programIds) {
                    Opportunity newOpportunity = new Opportunity();
                    newOpportunity.AccountId = accountId;
                    if (isMouContractRequired == true && programToContractMap.containsKey(programId)) {
                        newOpportunity.ContractId = programToContractMap.get(programId).Id;
                    }
                    String progName = programNameMap.get(programId);
                    newOpportunity.Name = String.isNotBlank(opportunityName) 
                        ? opportunityName + ' - ' + progName 
                        : 'Opportunity - ' + progName;
                    newOpportunity.Amount = opportunityAmount;
                    newOpportunity.CloseDate = closeDate != null ? closeDate : Date.today().addDays(30);
                    newOpportunity.StageName = String.isNotBlank(stage) ? stage : 'Prospecting';
                    newOpportunity.Program__c = programId;
                    newOpportunity.LeadSource = leadSource;
                    // Link Slab if found for this program
                    if (programToSlabMap.containsKey(programId)) {
                        newOpportunity.Slab__c = programToSlabMap.get(programId);
                    }
                    newOpportunity.Is_MOU_Contract_Required__c = isMouContractRequired == true;
                    applyB2BOpportunityRecordType(newOpportunity);
                    opportunitiesToInsert.add(newOpportunity);
                }
            } else {
                Opportunity newOpportunity = new Opportunity();
                newOpportunity.AccountId = accountId;
                if (isMouContractRequired == true && !contractsToInsert.isEmpty()) {
                    newOpportunity.ContractId = contractsToInsert[0].Id;
                }
                newOpportunity.Name = opportunityName;
                newOpportunity.Amount = opportunityAmount;
                newOpportunity.CloseDate = closeDate != null ? closeDate : Date.today().addDays(30);
                newOpportunity.StageName = String.isNotBlank(stage) ? stage : 'Prospecting';
                newOpportunity.LeadSource = leadSource;
                newOpportunity.Is_MOU_Contract_Required__c = isMouContractRequired == true;
                applyB2BOpportunityRecordType(newOpportunity);
                opportunitiesToInsert.add(newOpportunity);
            }
            
            insert opportunitiesToInsert;
            
            if (contactId != null && (reportsToId != null || String.isNotBlank(department))) {
                Contact contactToUpdate = new Contact(Id = contactId);
                if (reportsToId != null) {
                    contactToUpdate.ReportsToId = reportsToId;
                }
                if (String.isNotBlank(department)) {
                    contactToUpdate.Department = department;
                }
                update contactToUpdate;
            }

            if (contactId != null) {
                List<OpportunityContactRole> ocrList = new List<OpportunityContactRole>();
                for (Opportunity opp : opportunitiesToInsert) {
                    OpportunityContactRole ocr = new OpportunityContactRole();
                    ocr.OpportunityId = opp.Id;
                    ocr.ContactId = contactId;
                    ocr.IsPrimary = true;
                    ocr.Role = 'Decision Maker';
                    ocrList.add(ocr);
                }
                insert ocrList;
            }
            
            Integer oppCount = opportunitiesToInsert.size();
            result.success = true;
            result.message = oppCount + ' Opportunity(ies) created successfully for existing Account and Contact.';
            result.recordId = opportunitiesToInsert[0].Id;
            result.recordType = 'Opportunity';
            result.accountId = accountId;
            result.contactId = contactId;
            result.opportunityId = opportunitiesToInsert[0].Id;
            
        } catch (Exception e) {
            Database.rollback(sp);
            result.success = false;
            result.message = 'Error creating Opportunity: ' + e.getMessage();
        }
        
        return result;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getOpportunityStages() {
        List<Map<String, String>> stages = new List<Map<String, String>>();
        
        Schema.DescribeFieldResult fieldResult = Opportunity.StageName.getDescribe();
        List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
        
        for (Schema.PicklistEntry entry : picklistValues) {
            if (entry.isActive()) {
                Map<String, String> stageMap = new Map<String, String>();
                stageMap.put('label', entry.getLabel());
                stageMap.put('value', entry.getValue());
                stages.add(stageMap);
            }
        }
        
        return stages;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPrograms() {
        List<Map<String, String>> programs = new List<Map<String, String>>();
        
        List<Program> programList = [
            SELECT Id, Name, Programme_Type__c, Status__c
            FROM Program 
            WHERE Status__c = 'Active'
            ORDER BY Name ASC
            LIMIT 200
        ];
        
        for (Program prog : programList) {
            Map<String, String> progMap = new Map<String, String>();
            progMap.put('id', prog.Id);
            progMap.put('name', prog.Name);
            progMap.put('type', prog.Programme_Type__c != null ? prog.Programme_Type__c : '');
            programs.add(progMap);
        }
        
        return programs;
    }
    
    @AuraEnabled
    public static String getProgramName(Id programId) {
        if (programId == null) {
            return null;
        }
        List<Program> programs = [SELECT Id, Name FROM Program WHERE Id = :programId LIMIT 1];
        if (!programs.isEmpty()) {
            return programs[0].Name;
        }
        return null;
    }
    
   
    /* Returns all STD Codes of cities based on the parent country selected */
    @AuraEnabled(cacheable=true)
public static List<String> getStdCodesByCountry(Id countryId) {

    if (countryId == null) {
        return new List<String>();
    }

    List<City__c> cities = [
        SELECT STD_Code__c,State__r.Name
        FROM City__c
        WHERE State__r.Country_Master__c = :countryId
        AND STD_Code__c != null
    ];

    Set<String> stdCodes = new Set<String>();

    for (City__c city : cities) {
        if (String.isNotBlank(city.STD_Code__c)) {
            for (String code : city.STD_Code__c.split(';')) {
                stdCodes.add(code.trim() + ' - ' + city.State__r.Name);
            }
        }
    }

    return new List<String>(stdCodes);
}

/* Returns all STD Codes of cities based on the parent country selected */
    @AuraEnabled(cacheable=true)
public static List<Contact> checkLeadContacts(Id leadId,String email, String fname,String lname) {
    return [SELECT Id,Email,Phone,LastName,FirstName
    FROM Contact 
    WHERE Lead__c=:leadId 
    AND (Email=:email OR LastName=:lname OR FirstName=:fname)];

  
}
public class leadProgrammeWrapper{
   @AuraEnabled public String leadConId {get;set;}
   @AuraEnabled public string leadContactName {get;set;}
   @AuraEnabled public List<String> programmeApplied {get;set;}
   @AuraEnabled public string Designation {get;set;}
   @AuraEnabled public Boolean isPrimaryContact {get;set;}
   @AuraEnabled public string Email {get;set;}
}

@AuraEnabled(cacheable=true)
public static List<leadProgrammeWrapper> returnLeadProgrammes(Id recordId){
    if(String.isBlank(recordId)){
        return new List<leadProgrammeWrapper>();
    }
    Map<Id,Contact> leadConMap = new Map<Id,Contact>();
    List<leadProgrammeWrapper> result = new List<leadProgrammeWrapper>();
    Map<Id,List<String>> appliedProgrammes = new Map<Id,List<String>>();
    for(Contact lc: [SELECT Id,Name,FirstName,Email,LastName,Designation__c,Is_Primary_Contact__c
    FROM Contact WHERE Lead__c=:recordId]){
        leadConMap.put(lc.Id,lc);
    }
    if(!leadConMap.isEmpty()){
        
        
        for(Lead_Program__c lp: [SELECT Id,Program__r.Name,
            Contact__c FROM Lead_Program__c WHERE
        Contact__c IN :leadConMap.keySet()]){
            if(!appliedProgrammes.containsKey(lp.Contact__c)){
                appliedProgrammes.put(lp.Contact__c, new List<String>());
            }
            appliedProgrammes.get(lp.Contact__c).add(lp.Program__r.Name);
            
        }

        
    }

    if(!appliedProgrammes.isEmpty()){
        for(Id ldConId:leadConMap.keySet()){
            String fname = leadConMap.get(ldConId).FirstName==null?'':leadConMap.get(ldConId).FirstName;
            String lname = leadConMap.get(ldConId).LastName==null?'':leadConMap.get(ldConId).LastName;
            String name = fname + ' ' + lname;
            String email = leadConMap.get(ldConId).Email;
            Boolean isPrimary = leadConMap.get(ldConId).Is_Primary_Contact__c;
            String designation = leadConMap.get(ldConId).Designation__c;
            List<String> programmes = appliedProgrammes.get(ldConId);
            leadProgrammeWrapper s = new leadProgrammeWrapper();
            s.leadContactName = name;
            s.Email = email;
            s.leadConId = ldConId;
            s.isPrimaryContact = isPrimary;
            s.programmeApplied = programmes;
            s.Designation = designation;
                
            result.add(s);
        }
    }
    
    
    return result;
}

}
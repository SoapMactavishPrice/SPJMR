/** 
 * Builds Lead / Lead_Program__c rows from API payload and classifies the business scenario.
  */
public without sharing class LeadPublicAPIHelper {
    public enum Scenario {
        LEAD_CREATED,
        LEAD_EXISTING_NEW_PROGRAM,
        LEAD_EXISTING_PROGRAM_ALREADY_LINKED,
        APPLICANT_NEW_OPPORTUNITY,
        APPLICANT_OPPORTUNITY_ALREADY_EXISTS
    }

    public class ResultWrapper {
        public Id leadId;
        public Lead leadRecord;
        public Lead_Program__c leadProgram;
        public Scenario scenario;
    }

    public static String scenarioApiName(Scenario s) {
        return s == null ? null : String.valueOf(s);
    }

    public static String messageForScenario(Scenario s) {
        if (s == Scenario.LEAD_CREATED) {
            return LeadPublicAPIMessages.LEAD_CREATED;
        }
        if (s == Scenario.LEAD_EXISTING_NEW_PROGRAM) {
            return LeadPublicAPIMessages.LEAD_EXISTS_NEW_PROGRAM;
        }
        if (s == Scenario.LEAD_EXISTING_PROGRAM_ALREADY_LINKED) {
            return LeadPublicAPIMessages.LEAD_EXISTS_PROGRAM_ALREADY_LINKED;
        }
        if (s == Scenario.APPLICANT_NEW_OPPORTUNITY) {
            return LeadPublicAPIMessages.APPLICANT_NEW_OPPORTUNITY;
        }
        if (s == Scenario.APPLICANT_OPPORTUNITY_ALREADY_EXISTS) {
            return LeadPublicAPIMessages.APPLICANT_OPPORTUNITY_ALREADY_EXISTS;
        }
        return '';
    }

    /**
     * Prepares Lead upsert and optional Lead_Program__c for the non-applicant path.
     * Mutates {@code leadToPrograms} when a new program is linked so batch processing stays consistent.
     */
    public static ResultWrapper processLead(
        LeadPublicAPI.LeadWrapper lw,
        Map<String, Program> programMap,
        Map<String, Id> stateMap,
        Map<String, Id> cityMap,
        Id countryId,
        Id recordTypeId,
        Map<String, Lead> emailToLead,
        Map<String, Lead> phoneToLead,
        Map<Id, Set<Id>> leadToPrograms
    ) {
        Program prog = programMap.get(lw.Programme);
        if (prog == null) {
            throw new LeadPublicAPIException(LeadPublicAPIMessages.INVALID_PROGRAMME);
        }

        Lead existing = resolveExistingLead(lw, emailToLead, phoneToLead);

        Lead leadRow;
        ResultWrapper out = new ResultWrapper();

        if (existing == null) {
            leadRow = new Lead();
            leadRow.RecordTypeId = recordTypeId;
            leadRow.Status = 'Untouched';
            out.scenario = Scenario.LEAD_CREATED;
        } else {
            leadRow = new Lead(Id = existing.Id);
            out.scenario = Scenario.LEAD_EXISTING_NEW_PROGRAM;
        }

        applyWrapperToLead(leadRow, lw, countryId, stateMap, cityMap);

        Set<Id> programsForLead = existing != null ? leadToPrograms.get(existing.Id) : null;

        if (existing != null) {
            if (programsForLead != null && programsForLead.contains(prog.Id)) {
                out.leadProgram = null;
                out.scenario = Scenario.LEAD_EXISTING_PROGRAM_ALREADY_LINKED;
            } else {
                Lead_Program__c lp = baseLeadProgram(lw, prog.Id);
                out.leadProgram = lp;
                out.scenario = Scenario.LEAD_EXISTING_NEW_PROGRAM;
                Id leadKey = existing.Id;
                if (!leadToPrograms.containsKey(leadKey)) {
                    leadToPrograms.put(leadKey, new Set<Id>());
                }
                leadToPrograms.get(leadKey).add(prog.Id);
            }
        } else {
            Lead_Program__c lp = baseLeadProgram(lw, prog.Id);
            out.leadProgram = lp;
        }

        out.leadRecord = leadRow;
        return out;
    }

    private static Lead resolveExistingLead(
        LeadPublicAPI.LeadWrapper lw,
        Map<String, Lead> emailToLead,
        Map<String, Lead> phoneToLead
    ) {
        Lead existing = null;
        if (String.isNotBlank(lw.Email) && emailToLead.containsKey(lw.Email)) {
            existing = emailToLead.get(lw.Email);
        }
        if (existing == null && String.isNotBlank(lw.Phone) && phoneToLead.containsKey(lw.Phone)) {
            existing = phoneToLead.get(lw.Phone);
        }
        return existing;
    }

    private static void applyWrapperToLead(
        Lead target,
        LeadPublicAPI.LeadWrapper lw,
        Id countryId,
        Map<String, Id> stateMap,
        Map<String, Id> cityMap
    ) {
        String fn = String.isNotBlank(lw.FirstName) ? lw.FirstName : '';
        String ln = String.isNotBlank(lw.LastName) ? lw.LastName : '.';

        target.FirstName = lw.FirstName;
        target.LastName = ln;
        target.Email = lw.Email;
        target.Phone = lw.Phone;

        target.Country_Master_backend__c = countryId;
        if (lw.State != null && String.isNotBlank(lw.State.trim())) {
            Id stId = stateMap.get(lw.State.trim());
            target.State_Master__c = stId;
            target.State = lw.State.trim();
        }
        if (lw.City != null && String.isNotBlank(lw.City.trim())) {
            Id ctyId = cityMap.get(lw.City.trim());
            target.District_City__c = ctyId;
            target.City = lw.City.trim();
        }
        target.Country = 'India';

        if (String.isNotBlank(lw.Age)) {
            target.XS_Age__c = lw.Age;
        }
        if (String.isNotBlank(lw.YearsOfWorkExperience)) {
            target.XS_YearsOfWorkExperience__c = lw.YearsOfWorkExperience;
        }
        target.XS_DoYouHaveEntranceExamScore__c = normalizeYesNo(lw.DoYouHaveEntranceExamScore);
        if (String.isNotBlank(lw.EntranceExamName)) {
            target.XS_EntranceExamName__c = lw.EntranceExamName;
        }
        if (String.isNotBlank(lw.HowDidYouFindOutAboutUs)) {
            target.XS_HowDidYouFindOutAboutUs__c = lw.HowDidYouFindOutAboutUs;
        }
        if (String.isNotBlank(lw.Source)) {
            target.LeadSource = lw.Source;
        }

        target.XS_SPJIMR_PartnerCompany__c = lw.SPJIMR_PartnerCompany;
        target.XS_EnterOrganisation__c = lw.EnterOrganisation;
        target.XS_CurrentDesigination__c = lw.CurrentDesigination;
        target.XS_College__c = lw.College;
        target.XS_Year__c = lw.Year;
        target.XS_HaveYouCompletedYourGraduation__c = lw.HaveYouCompletedYourGraduation;
        target.XS_CurrentlyStudingIn__c = lw.CurrentlyStudingIn;
        target.UTMParameterIds__c = lw.UTMParameters;

        target.Company = String.isNotBlank(lw.LastName)
            ? fn + ' ' + ln + ' (Individual)'
            : fn + ' (Individual)';
    }
	@TestVisible
    private static String normalizeYesNo(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String v = raw.trim().toLowerCase();
        if (v == 'yes' || v == 'y' || v == 'true' || v == '1') {
            return 'Yes';
        }
        if (v == 'no' || v == 'n' || v == 'false' || v == '0') {
            return 'No';
        }
        return raw;
    }

    private static Lead_Program__c baseLeadProgram(LeadPublicAPI.LeadWrapper lw, Id programId) {
        return new Lead_Program__c(
            Program__c = programId,
            Email__c = lw.Email,
            Phone__c = lw.Phone
        );
    }
}
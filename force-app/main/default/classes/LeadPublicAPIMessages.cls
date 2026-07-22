/**
 * User-facing API messages for createLead scenarios.
 */
public with sharing class LeadPublicAPIMessages {
    public static final String LEAD_CREATED = 'Lead created successfully.';
    public static final String LEAD_EXISTS_NEW_PROGRAM =
        'Lead already exists. Adding new program to the lead.';
    public static final String LEAD_EXISTS_PROGRAM_ALREADY_LINKED =
        'Lead already exists. This program is already associated with the lead.';
    public static final String APPLICANT_NEW_OPPORTUNITY =
        'Applicant already exists with this data. Adding new opportunity related to that applicant.';
    public static final String APPLICANT_OPPORTUNITY_ALREADY_EXISTS =
        'Applicant already exists. An opportunity for this program is already present.';
    public static final String MISSING_REQUIRED_FIELDS = 'Missing required fields.';
    public static final String INVALID_PROGRAMME = 'Invalid programme code.';
}
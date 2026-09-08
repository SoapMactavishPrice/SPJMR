@IsTest
private class LeadPublicAPIMessagesTest {
    @IsTest
static void testLeadPublicAPIMessages() {

    System.assertEquals(
        'Lead created successfully.',
        LeadPublicAPIMessages.LEAD_CREATED
    );

    System.assertEquals(
        'Lead already exists. Adding new program to the lead.',
        LeadPublicAPIMessages.LEAD_EXISTS_NEW_PROGRAM
    );

    System.assertEquals(
        'Lead already exists. This program is already associated with the lead.',
        LeadPublicAPIMessages.LEAD_EXISTS_PROGRAM_ALREADY_LINKED
    );

    System.assertEquals(
        'Applicant already exists with this data. Adding new opportunity related to that applicant.',
        LeadPublicAPIMessages.APPLICANT_NEW_OPPORTUNITY
    );

    System.assertEquals(
        'Applicant already exists. An opportunity for this program is already present.',
        LeadPublicAPIMessages.APPLICANT_OPPORTUNITY_ALREADY_EXISTS
    );

    System.assertEquals(
        'Missing required fields.',
        LeadPublicAPIMessages.MISSING_REQUIRED_FIELDS
    );

    System.assertEquals(
        'Invalid programme code.',
        LeadPublicAPIMessages.INVALID_PROGRAMME
    );

    System.assertEquals(
        'Lead already exists. This program is already linked; the new phone number has been saved as an alternate contact number.',
        LeadPublicAPIMessages.LEAD_ALTERNATE_PHONE_UPDATED
    );

    System.assertEquals(
        'Applicant already exists. An opportunity for this program is already present; the new phone number has been saved as an alternate contact number.',
        LeadPublicAPIMessages.APPLICANT_ALTERNATE_PHONE_UPDATED
    );
}
}
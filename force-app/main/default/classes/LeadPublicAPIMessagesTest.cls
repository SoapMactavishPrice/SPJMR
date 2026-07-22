@IsTest
private class LeadPublicAPIMessagesTest {
    @IsTest
    static void constantsAreDefined() {
        System.assertNotEquals(null, LeadPublicAPIMessages.LEAD_CREATED);
        System.assertNotEquals(null, LeadPublicAPIMessages.LEAD_EXISTS_NEW_PROGRAM);
        System.assertNotEquals(null, LeadPublicAPIMessages.LEAD_EXISTS_PROGRAM_ALREADY_LINKED);
        System.assertNotEquals(null, LeadPublicAPIMessages.APPLICANT_NEW_OPPORTUNITY);
        System.assertNotEquals(null, LeadPublicAPIMessages.APPLICANT_OPPORTUNITY_ALREADY_EXISTS);
        System.assertNotEquals(null, LeadPublicAPIMessages.MISSING_REQUIRED_FIELDS);
        System.assertNotEquals(null, LeadPublicAPIMessages.INVALID_PROGRAMME);
    }
}
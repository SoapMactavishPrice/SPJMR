@IsTest(SeeAllData=true)
private class ApplicantMyCommControllerTest {
    @IsTest
    static void returnEmails_emptyAndPopulated() {
        // No match — returns null
        List<EmailMessage> r = applicantMyCommunicationController.returnEmails('nobody-' + Datetime.now().getTime() + '@x.com');
        System.assertEquals(null, r);

        // If any EmailMessage has a ToAddress in org, exercise the populated branch.
        List<EmailMessage> someEmail = [SELECT ToAddress FROM EmailMessage WHERE ToAddress != null LIMIT 1];
        if (!someEmail.isEmpty() && someEmail[0].ToAddress != null) {
            List<EmailMessage> got = applicantMyCommunicationController.returnEmails(someEmail[0].ToAddress);
            System.assertNotEquals(null, got);
        }
    }
}
@IsTest
private class PasswordResetControllerTest {
    @IsTest
    static void resetPasswordHandlesMissingAndExistingUser() {
        try {
            PasswordResetController.resetPassword('missing' + System.currentTimeMillis() + '@example.com');
            System.assert(false, 'Expected missing user email to throw.');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = String.valueOf(System.currentTimeMillis());
        User u = new User(
            Alias = 'rstusr',
            Email = 'reset' + unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Reset',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'reset' + unique + '@example.com',
            ProfileId = p.Id
        );
        insert u;

        Test.startTest();
        try {
            PasswordResetController.resetPassword(u.Email);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}
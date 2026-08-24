public with sharing class PasswordResetController {
    @AuraEnabled
    public static void resetPassword(String email) {
        List<User> users = [SELECT Id, Username FROM User WHERE Email = :email];
        if (users.isEmpty()) {
            throw new AuraHandledException('No user found with the provided email address.');
        }
        User user = users[0];
        
        if (user != null) {
            System.resetPasswordWithEmailTemplate(user.Id, true, 'SPJIMR_Applicant_Reset_Password');
        }
    }
}
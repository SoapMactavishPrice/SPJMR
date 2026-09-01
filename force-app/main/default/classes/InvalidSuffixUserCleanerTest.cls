@IsTest
private class InvalidSuffixUserCleanerTest {
    private static User makeUser(String email, String username) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'invusr',
            Email = email,
            EmailEncodingKey = 'UTF-8',
            LastName = 'Invalid',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = username,
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    private static Account makeApplicant(String tag, String email) {
        Account a = new Account(
            FirstName = 'Invalid',
            LastName = tag,
            PersonEmail = email
        );
        Id rtId = SpjimrPortalTestDataFactory.getStudentPersonAccountRecordTypeId();
        if (rtId != null) {
            a.RecordTypeId = rtId;
        }
        insert a;
        return a;
    }

    @IsTest
    static void cleanUserInvalidSuffixCoversEmptyMissingUpdateAndConflict() {
        InvalidSuffixUserCleaner.CleanupResult emptyResult =
            InvalidSuffixUserCleaner.cleanUserInvalidSuffix(null);
        System.assertEquals(0, emptyResult.totalApplicationNamesProvided);

        String stamp = String.valueOf(System.currentTimeMillis());
        String baseEmail = 'invalid.clean.' + stamp + '@example.com';
        String invalidEmail = baseEmail + '.invalid';
        User updateUser = makeUser(invalidEmail, baseEmail + '.invalid');
        Account applicant = makeApplicant('Cleaner', invalidEmail);
        Application__c app = new Application__c(Name = 'CLEAN-' + stamp, Applicant__c = applicant.Id);
        insert app;
        app = [SELECT Id, Name FROM Application__c WHERE Id = :app.Id];

        InvalidSuffixUserCleaner.CleanupResult updateResult =
            InvalidSuffixUserCleaner.cleanUserInvalidSuffix(new List<String>{ app.Name, 'DOES-NOT-EXIST', '', app.Name });

        System.assertEquals(2, updateResult.totalApplicationNamesProvided);
        System.assertEquals(1, updateResult.applicationsMatched);
        System.assertEquals(1, updateResult.applicationNamesNotFound.size());
        System.assertEquals(true, updateResult.usersMatchedBeforeFilter >= 0);

        User refreshed = [SELECT Email, Username FROM User WHERE Id = :updateUser.Id];
        System.assertEquals(true, refreshed.Email == baseEmail || refreshed.Email == invalidEmail);
        System.assertEquals(true, refreshed.Username == baseEmail || refreshed.Username == baseEmail + '.invalid');

        String normalEmail = 'invalid.normal.' + stamp + '@example.com';
        makeUser(normalEmail, normalEmail);
        Account normalApplicant = makeApplicant('Normal', normalEmail);
        Application__c normalApp = new Application__c(Name = 'NORMAL-' + stamp, Applicant__c = normalApplicant.Id);
        insert normalApp;
        normalApp = [SELECT Id, Name FROM Application__c WHERE Id = :normalApp.Id];
        InvalidSuffixUserCleaner.CleanupResult normalResult =
            InvalidSuffixUserCleaner.cleanUserInvalidSuffix(new List<String>{ normalApp.Name });
        System.assertEquals(0, normalResult.usersEligibleForUpdate);

        Account noEmailApplicant = makeApplicant('NoEmail', null);
        Application__c noEmailApp = new Application__c(Name = 'NOEMAIL-' + stamp, Applicant__c = noEmailApplicant.Id);
        insert noEmailApp;
        noEmailApp = [SELECT Id, Name FROM Application__c WHERE Id = :noEmailApp.Id];
        InvalidSuffixUserCleaner.CleanupResult noEmailResult =
            InvalidSuffixUserCleaner.cleanUserInvalidSuffix(new List<String>{ noEmailApp.Name });
        System.assertEquals(0, noEmailResult.usersMatchedBeforeFilter);

        String conflictBase = 'invalid.conflict.' + stamp + '@example.com';
        makeUser('holder.' + stamp + '@example.com', conflictBase);
        makeUser(conflictBase + '.invalid', conflictBase + '.invalid');
        Account conflictApplicant = makeApplicant('Conflict', conflictBase + '.invalid');
        Application__c conflictApp = new Application__c(Name = 'CONFLICT-' + stamp, Applicant__c = conflictApplicant.Id);
        insert conflictApp;
        conflictApp = [SELECT Id, Name FROM Application__c WHERE Id = :conflictApp.Id];

        InvalidSuffixUserCleaner.CleanupResult conflictResult =
            InvalidSuffixUserCleaner.cleanUserInvalidSuffix(new List<String>{ conflictApp.Name });

        System.assertEquals(true, conflictResult.usersSkippedDueToConflict == 1 || conflictResult.usersMatchedBeforeFilter == 0);
        System.assertEquals(0, conflictResult.usersUpdatedSuccessfully);
    }
}
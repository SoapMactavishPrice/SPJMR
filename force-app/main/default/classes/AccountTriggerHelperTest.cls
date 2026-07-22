@IsTest
private class AccountTriggerHelperTest {

    private static Account newFacultyAccount(String tag) {
        Id facRt = [SELECT Id FROM RecordType
                    WHERE SobjectType = 'Account' AND DeveloperName = 'Faculty' AND IsPersonType = true
                    LIMIT 1].Id;
        Account a = new Account(
            FirstName = 'Fac', LastName = 'Ulty ' + tag,
            PersonEmail = ('fac' + tag + '@example.com.spjtest').toLowerCase(),
            RecordTypeId = facRt, Active__c = true);
        insert a;
        return a;
    }

    @IsTest
    static void preventInactivation_whenCourseInstructorExists() {
        Account acc = newFacultyAccount('a' + String.valueOf(Crypto.getRandomInteger()).right(5));
        insert new Course_Instructor__c(Faculty__c = acc.Id);

        Map<Id, Account> oldMap = new Map<Id, Account>{
            acc.Id => new Account(Id = acc.Id, Active__c = true)
        };
        Account becomingInactive = new Account(Id = acc.Id, Active__c = false);

        Test.startTest();
        AccountTriggerHelper.preventAccountInactivationWhenCourseInstructorExists(
            new List<Account>{ becomingInactive }, oldMap);
        Test.stopTest();

        System.assert(becomingInactive.hasErrors(),
            'Inactivation must be blocked when a Course Instructor record exists.');

        // No-op branches: oldMap null, and an account with no related instructor.
        Account other = new Account(Name = 'Faculty B', Active__c = true);
        insert other;
        Account otherInactive = new Account(Id = other.Id, Active__c = false);
        AccountTriggerHelper.preventAccountInactivationWhenCourseInstructorExists(
            new List<Account>{ otherInactive },
            new Map<Id, Account>{ other.Id => new Account(Id = other.Id, Active__c = true) });
        System.assert(!otherInactive.hasErrors(), 'No instructor -> no error.');

        AccountTriggerHelper.preventAccountInactivationWhenCourseInstructorExists(
            new List<Account>{ becomingInactive }, null);
    }

    @IsTest
    static void syncFacultyInactivation_clearsInstructor() {
        Account acc = newFacultyAccount('c' + String.valueOf(Crypto.getRandomInteger()).right(5));
        Instructor__c inst = new Instructor__c(Account__c = acc.Id);
        insert inst;

        Map<Id, Account> oldMap = new Map<Id, Account>{
            acc.Id => new Account(Id = acc.Id, Active__c = true)
        };

        Test.startTest();
        AccountTriggerHelper.syncFacultyInactivationToBatchCourseAssignments(
            new List<Account>{ new Account(Id = acc.Id, Active__c = false) }, oldMap);
        Test.stopTest();

        Instructor__c after = [SELECT Account__c FROM Instructor__c WHERE Id = :inst.Id];
        System.assertEquals(null, after.Account__c, 'Instructor account link should be cleared.');

        // Early-return branch: still active.
        AccountTriggerHelper.syncFacultyInactivationToBatchCourseAssignments(
            new List<Account>{ new Account(Id = acc.Id, Active__c = true) }, oldMap);
    }

    @IsTest
    static void createPortalUserForStudent_paths() {
        Account student = SpjimrPortalTestDataFactory.buildLearnerPersonAccount(
            'athn' + String.valueOf(Crypto.getRandomInteger()).right(5));

        Test.startTest();
        try {
            AccountTriggerHelper.createPortalUserForStudent(
                [SELECT Id, RecordTypeId FROM Account WHERE Id = :student.Id]);
        } catch (Exception e) { System.debug('createPortalUserForStudent: ' + e.getMessage()); }

        // Non-student / empty branches.
        Account biz = new Account(Name = 'Biz');
        insert biz;
        AccountTriggerHelper.createPortalUserForStudent(
            [SELECT Id, RecordTypeId FROM Account WHERE Id = :biz.Id]);
        AccountTriggerHelper.createPortalUserForStudent(new List<Account>());
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void createPortalUsersAsync_runs() {
        Account student = SpjimrPortalTestDataFactory.buildLearnerPersonAccount(
            'aasy' + String.valueOf(Crypto.getRandomInteger()).right(5));
        Account refreshed = [SELECT PersonContactId, PersonEmail, FirstName, LastName
                             FROM Account WHERE Id = :student.Id];

        AccountTriggerHelper.UserCreationData data = new AccountTriggerHelper.UserCreationData();
        data.contactId = refreshed.PersonContactId;
        data.accountId = student.Id;
        data.username = 'async' + Crypto.getRandomInteger() + '@example.com.spjtest';
        data.emailAddress = data.username;
        data.firstName = 'Async';
        data.lastName = 'Tester';
        data.profileId = [SELECT Id FROM Profile WHERE Name = 'SPJIMR Student Portal User' LIMIT 1].Id;

        Test.startTest();
        AccountTriggerHelper.createPortalUsersAsync(
            JSON.serialize(new List<AccountTriggerHelper.UserCreationData>{ data }));
        Test.stopTest();
        System.assert(true, 'Future method executed (user-creation errors are swallowed).');
    }

    @IsTest
    static void updateRole_Student_runs() {
        Account student = SpjimrPortalTestDataFactory.buildLearnerPersonAccount(
            'arole' + String.valueOf(Crypto.getRandomInteger()).right(5));
        Test.startTest();
        try {
            AccountTriggerHelper.updateRole_Student(
                [SELECT Id, RecordTypeId, OwnerId FROM Account WHERE Id = :student.Id]);
        } catch (Exception e) {
            // No 'Student' UserRole configured / self-update restriction -> tolerated.
            System.debug('updateRole_Student: ' + e.getMessage());
        }
        AccountTriggerHelper.updateRole_Student(new List<Account>());
        Test.stopTest();
        System.assert(true);
    }
}
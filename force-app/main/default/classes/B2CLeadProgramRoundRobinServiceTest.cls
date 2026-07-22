@IsTest
private class B2CLeadProgramRoundRobinServiceTest {

    private static User createUser(String aliasSuffix) {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        return new User(
            FirstName = 'Test',
            LastName = 'User' + aliasSuffix,
            Alias = ('t' + aliasSuffix).left(8),
            Email = 'testuser' + aliasSuffix + '@example.com',
            Username = 'testuser' + aliasSuffix + Datetime.now().getTime() + '@example.com',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
    }

    @IsTest
    static void testPickUser_NeverAssignedWins() {

        User u1 = createUser('1');
        User u2 = createUser('2');
        insert new List<User>{u1, u2};

        Program_Team_Members__c ptm1 = new Program_Team_Members__c(
            User__c = u1.Id,
            Last_Lead_Assigned_DateTime__c = System.now().addDays(-5)
        );
        ptm1.User__r = u1;

        Program_Team_Members__c ptm2 = new Program_Team_Members__c(
            User__c = u2.Id
        );
        ptm2.User__r = u2;

        Test.startTest();

        Id pickedUserId =
            B2CLeadProgramRoundRobinService.pickUserIdForTest(
                new List<Program_Team_Members__c>{ ptm1, ptm2 }
            );

        Test.stopTest();

        System.assertEquals(
            u2.Id,
            pickedUserId,
            'Never-assigned counselor should be selected first'
        );
    }

    @IsTest
    static void testPickUser_OldestAssignmentWins() {

        User u1 = createUser('3');
        User u2 = createUser('4');
        insert new List<User>{u1, u2};

        Program_Team_Members__c ptm1 = new Program_Team_Members__c(
            User__c = u1.Id,
            Last_Lead_Assigned_DateTime__c = System.now().addDays(-10)
        );
        ptm1.User__r = u1;

        Program_Team_Members__c ptm2 = new Program_Team_Members__c(
            User__c = u2.Id,
            Last_Lead_Assigned_DateTime__c = System.now().addDays(-2)
        );
        ptm2.User__r = u2;

        Id pickedUserId =
            B2CLeadProgramRoundRobinService.pickUserIdForTest(
                new List<Program_Team_Members__c>{ ptm1, ptm2 }
            );

        System.assertEquals(
            u1.Id,
            pickedUserId,
            'Oldest assignment timestamp should win'
        );
    }

    @IsTest
    static void testPickUser_NameTieBreaker() {

        User alpha = createUser('5');
        User beta  = createUser('6');

        alpha.LastName = 'Alpha';
        beta.LastName  = 'Beta';

        insert new List<User>{alpha, beta};

        Datetime ts = System.now().addDays(-5);

        Program_Team_Members__c ptm1 = new Program_Team_Members__c(
            User__c = alpha.Id,
            Last_Lead_Assigned_DateTime__c = ts
        );
        ptm1.User__r = alpha;

        Program_Team_Members__c ptm2 = new Program_Team_Members__c(
            User__c = beta.Id,
            Last_Lead_Assigned_DateTime__c = ts
        );
        ptm2.User__r = beta;

        Id pickedUserId =
            B2CLeadProgramRoundRobinService.pickUserIdForTest(
                new List<Program_Team_Members__c>{ ptm1, ptm2 }
            );

        System.assertEquals(
            alpha.Id,
            pickedUserId,
            'Alphabetical name should break ties'
        );
    }

    @IsTest
    static void testPickUser_EmptyListReturnsNull() {

        System.assertEquals(
            null,
            B2CLeadProgramRoundRobinService.pickUserIdForTest(
                new List<Program_Team_Members__c>()
            )
        );
    }
}
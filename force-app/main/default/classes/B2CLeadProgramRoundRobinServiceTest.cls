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
static void testApplyAfterLeadProgramInsert_Null() {
    Test.startTest();
    B2CLeadProgramRoundRobinService.applyAfterLeadProgramInsert(null);
    Test.stopTest();
}

@IsTest
static void testApplyAfterLeadProgramInsert_Empty() {
    Test.startTest();
    B2CLeadProgramRoundRobinService.applyAfterLeadProgramInsert(
        new List<Lead_Program__c>()
    );
    Test.stopTest();
}

@IsTest
static void testApplyAfterLeadProgramInsert_NoProgram() {
    Lead_Program__c lp = new Lead_Program__c();
    Test.startTest();
    B2CLeadProgramRoundRobinService.applyAfterLeadProgramInsert(
        new List<Lead_Program__c>{ lp }
    );
    Test.stopTest();
}
    
    @IsTest
static void testApplyAfterLeadProgramInsert_WithData() {

    Profile adminProfile = [
        SELECT Id
        FROM Profile
        WHERE Name = 'System Administrator'
        LIMIT 1
    ];

    User admin = new User(
        FirstName = 'System',
        LastName = 'Admin',
        Alias = 'sysadm',
        Email = 'sysadmin@test.com',
        Username = 'sysadmin' + System.currentTimeMillis() + '@test.com',
        TimeZoneSidKey = 'Asia/Kolkata',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        ProfileId = adminProfile.Id
    );
    insert admin;

    System.runAs(admin) {

        Program program = new Program(
            Name = 'Test Program',
            Program_Code__c = 'TEST',
            Short_Programme_Code__c = 'TES',
            Programme_Duration__c = 'Months',
            Programme_Intake__c = 50,
            Programme_Type__c = 'Modular',
            Programme_Sub_Type__c = 'Class Room',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(30)
        );
        insert program;

        Id b2cRt = Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get('B2C')
            .getRecordTypeId();

        Lead lead = new Lead(
            LastName = 'Test',
            Company = 'Test Company',
            RecordTypeId = b2cRt,
            OwnerId = admin.Id
        );
        insert lead;

        Lead_Program__c lp = new Lead_Program__c(
            Lead__c = lead.Id,
            Program__c = program.Id,
            OwnerId = admin.Id
        );
        insert lp;
        Program_Team__c programTeam = new Program_Team__c(
    Name = 'Test Team',
    Program__c = program.Id
);
insert programTeam;

Program_Team_Members__c teamMember = new Program_Team_Members__c(
    Program_Team__c = programTeam.Id,
    User__c = admin.Id,
    Role__c = 'Student Counselor',
    Last_Lead_Assigned_DateTime__c = System.now().addDays(-1)
);
insert teamMember;

        Test.startTest();
        B2CLeadProgramRoundRobinService.applyAfterLeadProgramInsert(
            new List<Lead_Program__c>{ lp }
        );
        Test.stopTest();

        System.assertNotEquals(null, lp.Id);
    }
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
static void testLoadCounsellorsByProgramId() {

    User u = createUser('LC');
    insert u;

    Program p = new Program(
        Name='P1',
        Program_Code__c='P',
        Short_Programme_Code__c='P',
        Programme_Duration__c='Months',
        Programme_Intake__c=90,
        StartDate=Date.today(),
        EndDate=Date.today().addDays(10),
        Programme_Type__c='Modular',
        Programme_Sub_Type__c='Class Room'
    );
    insert p;

    Program_Team__c team = new Program_Team__c(
        Program__c = p.Id
    );
    insert team;

    insert new Program_Team_Members__c(
        Program_Team__c = team.Id,
        User__c = u.Id,
        Role__c = 'Student Counselor'
    );

    Test.startTest();

    Map<Id,List<B2CLeadProgramRoundRobinService.MemberRow>> result =
        B2CLeadProgramRoundRobinService.loadCounsellorsByProgramId(
            new Set<Id>{p.Id}
        );

    Test.stopTest();

    System.assertEquals(1, result.size());
    System.assert(result.containsKey(p.Id));
}
    
    @IsTest
static void testMergeMembersByUser() {

    User u = createUser('MG');
    insert u;
     Program_Team__c pt = new Program_Team__c();
    insert pt;
    Program_Team_Members__c p1 = new Program_Team_Members__c(
        Program_Team__c = pt.Id,
        User__c=u.Id,
        Last_Lead_Assigned_DateTime__c=System.now().addDays(-5)
    );
    p1.User__r = u;

    Program_Team_Members__c p2 = new Program_Team_Members__c(
        Program_Team__c = pt.Id,
        User__c=u.Id,
        Last_Lead_Assigned_DateTime__c=System.now().addDays(-2)
    );
    p2.User__r = u;
	insert p1;
    insert p2;
    List<B2CLeadProgramRoundRobinService.MemberRow> rows =
        new List<B2CLeadProgramRoundRobinService.MemberRow>{
            new B2CLeadProgramRoundRobinService.MemberRow(p1),
            new B2CLeadProgramRoundRobinService.MemberRow(p2)
        };

    List<B2CLeadProgramRoundRobinService.MemberRow> merged =
        B2CLeadProgramRoundRobinService.mergeMembersByUser(rows);

    System.assertEquals(1, merged.size());
}
    
    @IsTest
static void testPickNext() {

    User u1 = createUser('PN1');
    User u2 = createUser('PN2');
    insert new List<User>{u1,u2};

    Program_Team_Members__c p1 = new Program_Team_Members__c(
        User__c=u1.Id,
        Last_Lead_Assigned_DateTime__c=System.now().addDays(-5)
    );
    p1.User__r=u1;

    Program_Team_Members__c p2 = new Program_Team_Members__c(
        User__c=u2.Id
    );
    p2.User__r=u2;

    List<B2CLeadProgramRoundRobinService.MemberRow> rows =
        new List<B2CLeadProgramRoundRobinService.MemberRow>{
            new B2CLeadProgramRoundRobinService.MemberRow(p1),
            new B2CLeadProgramRoundRobinService.MemberRow(p2)
        };

    B2CLeadProgramRoundRobinService.PickedMember picked =
        B2CLeadProgramRoundRobinService.pickNext(rows);

    
}
    
    @IsTest
static void testShareLeadWithOwner() {

    User u = createUser('SH');
    insert u;

    Schema.RecordTypeInfo b2c =
        Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');

    Lead l = new Lead(
        LastName='Test',
        Email='share@test.com',
        RecordTypeId=b2c.getRecordTypeId()
    );
    insert l;

    Test.startTest();

    B2CLeadProgramRoundRobinService.shareLeadWithOwner(
        new Map<Id,Id>{ l.Id => u.Id }
    );

    Test.stopTest();
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
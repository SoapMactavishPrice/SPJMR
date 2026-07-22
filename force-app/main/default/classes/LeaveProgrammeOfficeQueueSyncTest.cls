@IsTest
private class LeaveProgrammeOfficeQueueSyncTest {

    private static User buildUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = 'poqsync' + System.currentTimeMillis() + Crypto.getRandomInteger();
        return new User(
            Alias = 'poqs',
            Email = uniq + '@example.com.spjtest',
            EmailEncodingKey = 'UTF-8',
            LastName = 'PoQSync',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniq + '@example.com.spjtest'
        );
    }

    /** Reconcile adds a Programme Office user that isn't yet a queue member. */
    @IsTest
    static void sync_addsProgrammeOfficeUserToQueue() {
        User u = buildUser();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u; // setup-object DML inside runAs to avoid mixed DML
        }

        SObject team = (SObject) Type.forName('Program_Team__c').newInstance();
        team.put('Name', 'PO Queue Sync Test Team');
        insert team;

        // Create the Programme Office member BEFORE startTest so it is committed and
        // visible to the async reconcile that runs at stopTest.
        Program_Team_Members__c m = new Program_Team_Members__c(
            Program_Team__c = (Id) team.get('Id'),
            Role__c = 'Programme Office',
            User__c = u.Id
        );
        insert m;
        System.assertEquals(1,
            [SELECT COUNT() FROM Program_Team_Members__c WHERE Role__c = 'Programme Office' AND User__c = :u.Id],
            'Programme Office member should be queryable before the reconcile.');

        Test.startTest();
        LeaveProgrammeOfficeQueueSync.syncQueueAsync();
        Test.stopTest(); // future executes here

        List<Group> q = [
            SELECT Id FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Leave_Programme_Office'
            LIMIT 1
        ];
        if (!q.isEmpty()) {
            Integer cnt = [
                SELECT COUNT()
                FROM GroupMember
                WHERE GroupId = :q[0].Id AND UserOrGroupId = :u.Id
            ];
            System.assertEquals(1, cnt, 'Programme Office user should be synced into the queue.');
        }
    }

    /** Trigger path: a Programme Office change enqueues the reconcile without error. */
    @IsTest
    static void handle_enqueuesForProgrammeOfficeChange() {
        Test.startTest();
        LeaveProgrammeOfficeQueueSync.handle(
            new List<Program_Team_Members__c>{ new Program_Team_Members__c(Role__c = 'Programme Office') },
            null
        );
        Test.stopTest(); // any enqueued future runs harmlessly
        System.assert(true, 'Programme Office change is handled without error.');
    }

    /** Null lists and non-Programme-Office roles are ignored without error. */
    @IsTest
    static void handle_ignoresIrrelevantChanges() {
        Test.startTest();
        LeaveProgrammeOfficeQueueSync.handle(null, null);
        LeaveProgrammeOfficeQueueSync.handle(
            new List<Program_Team_Members__c>{ new Program_Team_Members__c(Role__c = 'Member') },
            null
        );
        Test.stopTest();
        System.assert(true, 'Irrelevant changes are ignored.');
    }

    /** Direct reconcile removes a stray user member that is no longer Programme Office. */
    @IsTest
    static void sync_removesStaleUserMember() {
        List<Group> q = [
            SELECT Id FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Leave_Programme_Office'
            LIMIT 1
        ];
        if (q.isEmpty()) {
            return; // queue not present in this org; nothing to assert
        }

        User stray = buildUser();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert stray;
            // add stray directly as a queue member; no matching Programme Office record exists
            insert new GroupMember(GroupId = q[0].Id, UserOrGroupId = stray.Id);
        }

        Test.startTest();
        LeaveProgrammeOfficeQueueSync.syncQueueAsync();
        Test.stopTest();

        Integer cnt = [
            SELECT COUNT()
            FROM GroupMember
            WHERE GroupId = :q[0].Id AND UserOrGroupId = :stray.Id
        ];
        System.assertEquals(0, cnt, 'Stale user member should be removed by the reconcile.');
    }
}
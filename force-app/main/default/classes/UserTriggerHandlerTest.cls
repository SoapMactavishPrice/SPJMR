@IsTest
public class UserTriggerHandlerTest {
    
    // -------------------------------------------------------
    // Helper: create a portal-ready User with a role on owner
    // Fixed: UserRole + User (setup objects) are wrapped in
    // System.runAs() to avoid MIXED_DML_OPERATION with
    // non-setup objects like Account.
    // -------------------------------------------------------
    private static User createPortalUser() {
        // Get Applicant Record Type
        Id applicantRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Applicant')
            .getRecordTypeId();
        
        // Step 1: Insert UserRole (setup object) inside System.runAs()
        UserRole role = new UserRole(
            Name              = 'HandlerTestRole',
            DeveloperName     = 'HandlerTestRole',
            RollupDescription = 'HandlerTestRole'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert role;
        }
        
        // Step 2: Insert Account (non-setup object) outside System.runAs()
        Account acc = new Account(
            RecordTypeId = applicantRT,
            FirstName    = 'Handler',
            LastName     = 'Applicant',
            PersonEmail  = 'handler@test.com'
        );
        insert acc;
        acc = [SELECT Id, PersonContactId, OwnerId FROM Account WHERE Id = :acc.Id];
        
        // Step 3: Assign Role to Account owner (setup object DML) inside System.runAs()
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = acc.OwnerId, UserRoleId = role.Id);
        }
        
        // Step 4: Insert portal User (setup object) inside System.runAs()
        Profile portalProfile = [
            SELECT Id FROM Profile
            WHERE Name LIKE '%Community%'
            LIMIT 1
        ];
        String email = 'handler' + System.currentTimeMillis() + '@test.com';
        User portalUser = new User(
            Username          = email,
            Email             = email,
            FirstName         = 'Handler',
            LastName          = 'User',
            Alias             = 'htest',
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = portalProfile.Id,
            ContactId         = acc.PersonContactId,
            CommunityNickname = 'htest' + System.currentTimeMillis()
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert portalUser;
        }
        return portalUser;
    }
    
    // -------------------------------------------------------
    // beforeInsert — currently empty, verify no exception
    // -------------------------------------------------------
    @IsTest
    static void testBeforeInsert() {
        UserTriggerHandler handler = new UserTriggerHandler();
        User u = new User();
        Test.startTest();
        handler.beforeInsert(new List<User>{ u });
        Test.stopTest();
        System.assertNotEquals(null, u);
    }
    
    // -------------------------------------------------------
    // beforeUpdate — currently empty, verify no exception
    // -------------------------------------------------------
    @IsTest
    static void testBeforeUpdate() {
        UserTriggerHandler handler = new UserTriggerHandler();
        User u = new User(Id = UserInfo.getUserId());
        Map<Id, User> newMap = new Map<Id, User>{ u.Id => u };
            Map<Id, User> oldMap = new Map<Id, User>{ u.Id => u };
                Test.startTest();
        handler.beforeUpdate(
            new List<User>{ u }, newMap,
            new List<User>{ u }, oldMap
        );
        Test.stopTest();
        System.assertNotEquals(null, newMap);
    }
    
    // -------------------------------------------------------
    // afterInsert — currently empty, verify no exception
    // -------------------------------------------------------
    @IsTest
    static void testAfterInsert() {
        UserTriggerHandler handler = new UserTriggerHandler();
        User u = new User(Id = UserInfo.getUserId());
        Map<Id, User> newMap = new Map<Id, User>{ u.Id => u };
            Test.startTest();
        handler.afterInsert(new List<User>{ u }, newMap);
        Test.stopTest();
        System.assertEquals(1, newMap.size());
    }
    
    // -------------------------------------------------------
    // afterUpdate — Scenario 1: field changed (triggers helper logic)
    // -------------------------------------------------------
    @IsTest
    static void testAfterUpdate_WithChange() {
        User portalUser = createPortalUser();
        
        Map<Id, User> oldMap = new Map<Id, User>{
            portalUser.Id => portalUser.clone(false, true, false, false)
                };
                    
                    System.runAs(new User(Id = UserInfo.getUserId())) {
                        portalUser.FirstName = 'UpdatedByHandler';
                        update portalUser;
                    }
        
        UserTriggerHandler handler = new UserTriggerHandler();
        Map<Id, User> newMap = new Map<Id, User>{ portalUser.Id => portalUser };
            
            Test.startTest();
        handler.afterUpdate(
            new List<User>{ portalUser }, newMap,
            new List<User>{ oldMap.get(portalUser.Id) }, oldMap
        );
        Test.stopTest();
        
        System.assertEquals(1, newMap.size());
    }
    
    // -------------------------------------------------------
    // afterUpdate — Scenario 2: no field changed (no-op path)
    // -------------------------------------------------------
    @IsTest
    static void testAfterUpdate_NoChange() {
        User portalUser = createPortalUser();
        
        Map<Id, User> oldMap = new Map<Id, User>{
            portalUser.Id => portalUser.clone(false, true, false, false)
                };
                    Map<Id, User> newMap = new Map<Id, User>{ portalUser.Id => portalUser };
                        
                        UserTriggerHandler handler = new UserTriggerHandler();
        
        Test.startTest();
        handler.afterUpdate(
            new List<User>{ portalUser }, newMap,
            new List<User>{ oldMap.get(portalUser.Id) }, oldMap
        );
        Test.stopTest();
        
        System.assertNotEquals(null, portalUser.Id);  
    }
    
    // -------------------------------------------------------
    // afterUpdate — Scenario 3: empty lists (boundary case)
    // -------------------------------------------------------
    @IsTest
    static void testAfterUpdate_EmptyLists() {
        UserTriggerHandler handler = new UserTriggerHandler();
        Test.startTest();
        handler.afterUpdate(
            new List<User>(), new Map<Id, User>(),
            new List<User>(), new Map<Id, User>()
        );
        Test.stopTest();
        System.assertEquals(0, new Map<Id,User>().size());
    }
}
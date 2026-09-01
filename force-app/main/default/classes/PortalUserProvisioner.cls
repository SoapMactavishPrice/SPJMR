/**
 * Test-only helper that provisions a portal community user linked to a learner
 * Person Account. Community-user creation requires the learner account's owner to
 * carry a UserRole, so this reparents the account to a freshly created role-bearing
 * owner first. All setup-object DML (UserRole/User) is isolated in runAs(self)
 * blocks to avoid MIXED_DML with the Person Account graph. Returns null when the
 * org has no community profile or the account has no PersonContact.
 */
@IsTest
public class PortalUserProvisioner { 

    public static User forAccount(Id learnerAccountId) {
        Profile pp = SpjimrPortalTestDataFactory.getPortalProfile();
        if (pp == null) return null;

        Account acct = [SELECT Id, PersonContactId FROM Account WHERE Id = :learnerAccountId LIMIT 1];
        if (acct.PersonContactId == null) return null;

        User self = new User(Id = UserInfo.getUserId());
        User owner;
        System.runAs(self) {
            try {
                UserRole role = new UserRole(
                    Name = 'PortalOwnerRole',
                    DeveloperName = 'PortalOwnerRole' + Math.abs(Crypto.getRandomInteger())
                );
                insert role;
                Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
                owner = new User(
                    Alias = 'pown',
                    Email = 'portalowner@example.com.spjtest',
                    EmailEncodingKey = 'UTF-8',
                    LastName = 'PortalOwner',
                    LanguageLocaleKey = 'en_US',
                    LocaleSidKey = 'en_US',
                    ProfileId = admin.Id,
                    TimeZoneSidKey = 'America/Los_Angeles',
                    Username = 'portalowner' + System.currentTimeMillis() + '@example.com.spjtest',
                    UserRoleId = role.Id
                );
                insert owner;
            } catch (Exception e) {
                owner = null;
            }
        }
        if (owner == null) return null;

        try {
            update new Account(Id = learnerAccountId, OwnerId = owner.Id);
        } catch (Exception e) {
            return null;
        }

        User pu = new User(
            Alias = 'pptu',
            Email = 'portaluser@example.com.spjtest',
            EmailEncodingKey = 'UTF-8',
            LastName = 'PortalLearner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = pp.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'portaluser' + System.currentTimeMillis() + '@example.com.spjtest',
            ContactId = acct.PersonContactId
        );
        System.runAs(self) {
            try {
                insert pu;
            } catch (Exception e) {
                pu = null;
            }
        }
        return pu;
    }
}
public class AccountTriggerHelper {
    
    /**
     * Prevents accounts from being marked inactive when related Course Instructor records exist.
     *
     * @param newAccounts Incoming Account records in before update context.
     * @param oldAccountMap Existing Account values keyed by Id.
     */
    public static void preventAccountInactivationWhenCourseInstructorExists(
        List<Account> newAccounts,
        Map<Id, Account> oldAccountMap
    ) {
        Set<Id> accountIdsToDeactivate = new Set<Id>();
        for (Account acc : newAccounts) {
            Account oldAcc = oldAccountMap != null ? oldAccountMap.get(acc.Id) : null;
            Boolean wasActive = oldAcc != null && oldAcc.Active__c == true;
            Boolean isBecomingInactive = acc.Active__c == false;
            if (wasActive && isBecomingInactive) {
                accountIdsToDeactivate.add(acc.Id);
            }
        }

        if (accountIdsToDeactivate.isEmpty()) {
            return;
        }
        Set<Id> blockedAccountIds = new Set<Id>();
        for (Course_Instructor__c ci : [
            SELECT Faculty__c
            FROM Course_Instructor__c
            WHERE Faculty__c IN :accountIdsToDeactivate
        ]) {
            if (ci.Faculty__c != null) {
                blockedAccountIds.add(ci.Faculty__c);
            }
        }

        if (blockedAccountIds.isEmpty()) {
            return;
        }

        for (Account acc : newAccounts) {
            if (blockedAccountIds.contains(acc.Id)) {
                acc.Active__c.addError(
                    'This faculty has related course instructor records. Remove them before marking this account inactive.'
                );
            }
        }
    }

    /**
     * One-way sync: when faculty Account is set inactive, clear related batch-course mappings.
     * This does not reactivate or update Account.Active__c from child-level changes.
     *
     * @param newAccounts Incoming Account records in after update context.
     * @param oldAccountMap Existing Account values keyed by Id.
     */
    public static void syncFacultyInactivationToBatchCourseAssignments(
        List<Account> newAccounts,
        Map<Id, Account> oldAccountMap
    ) {
        Set<Id> accountIdsToDeactivate = new Set<Id>();
        for (Account acc : newAccounts) {
            Account oldAcc = oldAccountMap != null ? oldAccountMap.get(acc.Id) : null;
            Boolean wasActive = oldAcc != null && oldAcc.Active__c == true;
            Boolean isBecomingInactive = acc.Active__c == false;
            if (wasActive && isBecomingInactive) {
                accountIdsToDeactivate.add(acc.Id);
            }
        }

        if (accountIdsToDeactivate.isEmpty()) {
            return;
        }

        List<Instructor__c> instructorUpdates = new List<Instructor__c>();
        for (Instructor__c instructorRow : [
            SELECT Id, Account__c
            FROM Instructor__c
            WHERE Account__c IN :accountIdsToDeactivate
        ]) {
            instructorRow.Account__c = null;
            instructorUpdates.add(instructorRow);
        }
        if (!instructorUpdates.isEmpty()) {
            update instructorUpdates;
        }
    }
    
     /**
     * Creates portal users for Student record type accounts
     * @param newAccounts List of newly created accounts
     */
    public static void createPortalUserForStudent(List<Account> newAccounts) {
        // Get Student record type with IsPersonType = true
        Id studentRecTypeId = null;
        try {
            RecordType studentRecordType = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Account' 
                AND DeveloperName = 'Student' 
                AND IsPersonType = true 
                LIMIT 1
            ];
            studentRecTypeId = studentRecordType.Id;
        } catch(Exception e) {
            System.debug('Error: Student record type with IsPersonType = true not found. ' + e.getMessage());
            return;
        }
        
        List<Account> studentAccounts = new List<Account>();
        
        // Filter accounts with Student record type
        for(Account acc : newAccounts) {
            if(acc.RecordTypeId == studentRecTypeId) {
                studentAccounts.add(acc);
            }
        }
        
        if(studentAccounts.isEmpty()) {
            return;
        }
        
        // Get the portal profile
        Profile portalProfile;
        try {
            portalProfile = [SELECT Id, Name FROM Profile WHERE Name = 'SPJIMR Student Portal User' LIMIT 1];
        } catch(Exception e) {
            System.debug('Error: Profile "SPJIMR Student Portal User" not found. ' + e.getMessage());
            return;
        }
        
        // Query accounts with PersonContactId and email information
        Set<Id> accountIds = new Set<Id>();
        for(Account acc : studentAccounts) {
            accountIds.add(acc.Id);
        }
        
        List<Account> accountsToProcess = [
            SELECT Id, PersonEmail, FirstName, LastName, PersonContactId
            FROM Account 
            WHERE Id IN :accountIds 
            AND PersonEmail != null
            AND PersonContactId != null
        ];
        
        if(accountsToProcess.isEmpty()) {
            return;
        }
        
        // Collect data for user creation (to be processed in @future method)
        List<UserCreationData> userCreationDataList = new List<UserCreationData>();
        
        for(Account acc : accountsToProcess) {
            // Generate username (using email)
            String username = acc.PersonEmail.toLowerCase().trim();
            
            // Check if user already exists
            List<User> existingUsers = [SELECT Id FROM User WHERE Username = :username OR Email = :acc.PersonEmail LIMIT 1];
            if(!existingUsers.isEmpty()) {
                System.debug('User already exists with email: ' + acc.PersonEmail);
                continue;
            }
            
            // Store data for @future method
            UserCreationData userData = new UserCreationData();
            userData.contactId = acc.PersonContactId;
            userData.accountId = acc.Id;
            userData.username = username;
            userData.emailAddress = acc.PersonEmail;
            userData.firstName = acc.FirstName;
            userData.lastName = acc.LastName;
            userData.profileId = portalProfile.Id;
            
            userCreationDataList.add(userData);
        }
        
        // Call @future method to create users in separate transaction
        if(!userCreationDataList.isEmpty()) {
            createPortalUsersAsync(JSON.serialize(userCreationDataList));
        }
    }
    
    /**
     * Wrapper class to hold user creation data
     */
    public class UserCreationData {
        public Id contactId;
        public Id accountId;
        public String username;
        public String emailAddress;
        public String firstName;
        public String lastName;
        public Id profileId;
    }
    
    /**
     * @future method to create portal users in a separate transaction
     * This avoids MIXED_DML_OPERATION errors
     */
    @future
    public static void createPortalUsersAsync(String userDataJson) {
        List<UserCreationData> userDataList = (List<UserCreationData>) JSON.deserialize(userDataJson, List<UserCreationData>.class);
        
        for(UserCreationData userData : userDataList) {
            // Double-check if user already exists
            List<User> existingUsers = [SELECT Id FROM User WHERE Username = :userData.username OR Email = :userData.emailAddress LIMIT 1];
            if(!existingUsers.isEmpty()) {
                System.debug('User already exists with email: ' + userData.emailAddress);
                continue;
            }
            
            try {
                // Create user object with all required fields
                User portalUser = new User();
                portalUser.Username = userData.username;
                portalUser.Email = userData.emailAddress;
                portalUser.FirstName = userData.firstName;
                portalUser.LastName = userData.lastName;
                portalUser.ProfileId = userData.profileId;
                portalUser.ContactId = userData.contactId;
                
                // Generate alias (first letter of first name + up to 7 chars of last name)
                String alias = '';
                if(String.isNotBlank(userData.firstName)) {
                    alias += userData.firstName.substring(0, 1).toLowerCase();
                }
                if(String.isNotBlank(userData.lastName)) {
                    alias += userData.lastName.length() > 7 ? userData.lastName.substring(0, 7).toLowerCase() : userData.lastName.toLowerCase();
                } else {
                    alias += 'user';
                }
                portalUser.Alias = alias;
                
                // Set required locale and timezone fields
                portalUser.LocaleSidKey = 'en_US';
                portalUser.TimeZoneSidKey = 'Asia/Kolkata';
                portalUser.LanguageLocaleKey = 'en_US';
                portalUser.EmailEncodingKey = 'UTF-8';
                
                // Insert the user
                insert portalUser;
                
                // Use System.resetPassword to generate password reset token and send email
                // This will send a password reset email to the user automatically
                System.resetPassword(portalUser.Id, true);
                
                System.debug('Portal user created successfully: ' + portalUser.Id);
            } catch(Exception e) {
                System.debug('Error creating portal user for ' + userData.emailAddress + ': ' + e.getMessage());
            }
        }
    }
    
    
    public static void updateRole_Student(List<Account> newAccounts){
        Id studentRecTypeId = Schema.SobjectType.Account.getRecordTypeInfosByName().get('Student').getRecordTypeId();
        Set<Id> OwnerIdSet = new Set<Id>();
         List<User> updateList = new List<User>();
        if(newAccounts.size()>0){
            for(Account acc:newAccounts){
                if(acc.RecordTypeId == studentRecTypeId){
                    OwnerIdSet.add(acc.OwnerId);
                }
            }
        }
        if(OwnerIdSet.size()>0){
            List<User> userList =[SELECT Id,UserRoleId FROM User WHERE Id IN:OwnerIdSet];
           
            if(userList.size()>0){
                Id StudentRoleId = [SELECT Id FROM UserRole WHERE Name='Student' LIMIT 1].Id;
                for(User u:userList){
                    u.UserRoleId=StudentRoleId;
                    updateList.add(u);
                }
            }
            
        }
        
        if(updateList.size()>0){
            try{
                update updateList;
            }catch(DMLException e){
                system.debug('Update Failed '+e.getMessage());
            }
            
        }
        else{
            system.debug('Empty Update List');
        }
    }

}
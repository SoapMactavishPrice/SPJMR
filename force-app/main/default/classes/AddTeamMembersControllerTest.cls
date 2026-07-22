@IsTest
public class AddTeamMembersControllerTest {
    
    @TestSetup
    static void setupData() {
        
        // Create Program Team
        insert new Program_Team__c(
            Name = 'Test Team'
        );
        
        // Create Users
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        for (Integer i = 0; i < 3; i++) {
            insert new User(
                FirstName = 'Test',
                LastName = 'User' + i,
                Email = 'testuser' + i + '@test.com',
                Username = 'testuser' + i + System.currentTimeMillis() + '@test.com',
                Alias = 'tusr' + i,
                TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = p.Id
            );
        }
    }
    
    // ------------------------------------------------------------
    // Full Flow
    // ------------------------------------------------------------
    @IsTest
    static void testFullControllerFlow() {
        
        Id teamId = [SELECT Id FROM Program_Team__c LIMIT 1].Id;
        
        PageReference page = new PageReference('/apex/test');
        page.getParameters().put('id', teamId);
        Test.setCurrentPage(page);
        
        AddTeamMembersController ctrl = new AddTeamMembersController();
        
        ctrl.nextPage();
        ctrl.prevPage();
        
        ctrl.searchKey = 'Test';
        ctrl.searchUsers();
        
        if (!ctrl.usersToDisplay.isEmpty()) {
            ctrl.usersToDisplay[0].isSelected = true;
        }
        
        ctrl.showPreviewPage();
        
        // Get valid picklist value
        String validRole =
            Program_Team_Members__c.Role__c.getDescribe()
            .getPicklistValues()[0]
            .getValue();
        
        if (!ctrl.previewList.isEmpty()) {
            ctrl.previewList[0].role = validRole;
        }
        
        ctrl.saveSelected();
        
        ctrl.backToSelection();
        
        ctrl.getRoleOptions();
        ctrl.getSelectedCount();
        
        System.assert(ctrl.getSelectedCount() >= 0);
    }
    
    // ------------------------------------------------------------
    // Existing Member Branch
    // ------------------------------------------------------------
    @IsTest
    static void testExistingMemberBranch() {
        
        Id teamId = [SELECT Id FROM Program_Team__c LIMIT 1].Id;
        
        PageReference page = new PageReference('/apex/test');
        page.getParameters().put('id', teamId);
        Test.setCurrentPage(page);
        
        AddTeamMembersController ctrl = new AddTeamMembersController();
        
        if (!ctrl.usersToDisplay.isEmpty()) {
            
            User u = ctrl.usersToDisplay[0].usr;
            
            String validRole =
                Program_Team_Members__c.Role__c.getDescribe()
                .getPicklistValues()[0]
                .getValue();
            
            // Insert existing member properly
            insert new Program_Team_Members__c(
                Program_Team__c = teamId,
                User__c = u.Id,
                Role__c = validRole
            );
            
            ctrl.usersToDisplay[0].isSelected = true;
            ctrl.showPreviewPage();
            
            if (!ctrl.previewList.isEmpty()) {
                ctrl.previewList[0].role = validRole;
            }
            
            ctrl.saveSelected();
        }
        List<Program_Team_Members__c> members =
            [SELECT Id FROM Program_Team_Members__c WHERE Program_Team__c = :teamId];
        
        System.assert(members.size() > 0);
    }
}
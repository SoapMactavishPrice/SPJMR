public with sharing class AddTeamMembersController {
  
    public Id programTeamId { get; set; }
    public Integer pageNumber { get; set; }
    public Integer pageSize { get; set; }
    public Integer totalPages { get; set; }
    public String searchKey { get; set; }
    public Boolean showPreview { get; set; }

    // persistent selection
    public Set<Id> selectedUserIds { get; set; }
    public List<UserWrapper> usersToDisplay { get; set; }

    // Updated preview list – now holds role also
    public List<PreviewWrapper> previewList { get; set; }

    public AddTeamMembersController() {
        programTeamId = ApexPages.currentPage().getParameters().get('id');
        pageNumber = 1; 
        pageSize = 10;
        searchKey = '';
        selectedUserIds = new Set<Id>();
        showPreview = false;
        loadUsers();
    }

    // Wrapper for user checkbox
    public class UserWrapper {
        public User usr { get; set; }
        public Boolean isSelected { get; set; }
        public UserWrapper(User u, Boolean sel) { 
            usr = u; 
            isSelected = sel; 
        }
    }

    // Wrapper for preview (User + Role selection)
    public class PreviewWrapper {
        public User usr { get; set; }
        public String role { get; set; }
        public PreviewWrapper(User u) {
            usr = u;
            role = null;
        }
    }

    // Load users
    public void loadUsers() {
        Set<Id> existing = new Set<Id>();
        for (Program_Team_Members__c ptm :
            [SELECT User__c FROM Program_Team_Members__c WHERE Program_Team__c = :programTeamId]) {
            existing.add(ptm.User__c);
        }

        String likeSearch = '%' + searchKey + '%';

        List<User> all = [
            SELECT Id, Name, Email, Profile.UserLicense.Name
            FROM User
            WHERE IsActive = true
              AND Profile.UserLicense.Name = 'Salesforce'
              AND Id NOT IN :existing
              AND (Name LIKE :likeSearch OR Email LIKE :likeSearch)
            ORDER BY Name
            LIMIT :pageSize OFFSET :((pageNumber - 1) * pageSize)
        ];

        Integer totalCount = [SELECT COUNT()
            FROM User
            WHERE IsActive = true
              AND Profile.UserLicense.Name = 'Salesforce'
              AND Id NOT IN :existing
              AND (Name LIKE :likeSearch OR Email LIKE :likeSearch)];

        totalPages = (Integer)Math.ceil((Decimal)totalCount / pageSize);
        usersToDisplay = new List<UserWrapper>();

        for (User u : all) {
            usersToDisplay.add(new UserWrapper(u, selectedUserIds.contains(u.Id)));
        }
    }

    // Persist checkbox changes
    public void updateSelection() {
        for (UserWrapper uw : usersToDisplay) {
            if (uw.isSelected) selectedUserIds.add(uw.usr.Id);
            else selectedUserIds.remove(uw.usr.Id);
        }
    }

    // Pagination + Search
    public void nextPage() { updateSelection(); if (pageNumber < totalPages) pageNumber++; loadUsers(); }
    public void prevPage() { updateSelection(); if (pageNumber > 1) pageNumber--; loadUsers(); }
    public void searchUsers() { updateSelection(); pageNumber = 1; loadUsers(); }

    // Preview selected users with roles
    public void showPreviewPage() {
        updateSelection();
        List<User> selUsers = [SELECT Id, Name, Email FROM User WHERE Id IN :selectedUserIds];

        previewList = new List<PreviewWrapper>();
        for (User u : selUsers) {
            previewList.add(new PreviewWrapper(u));
        }

        showPreview = true;
    }

    public void backToSelection() { 
        showPreview = false; 
        loadUsers(); 
    }

    // Fetch Role__c picklist options
    public List<SelectOption> getRoleOptions() {
        List<SelectOption> opts = new List<SelectOption>();
        for (Schema.PicklistEntry pe : Program_Team_Members__c.Role__c.getDescribe().getPicklistValues()) {
            opts.add(new SelectOption(pe.getValue(), pe.getLabel()));
        }
        return opts;
    }

    // Save selected users with roles
    public PageReference saveSelected() {
        if (previewList == null || previewList.isEmpty()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.WARNING, 
                'No users selected.'
            ));
            return null;
        }

        // Get existing members
        Set<Id> existingUserIds = new Set<Id>();
        for (Program_Team_Members__c ptm : [
            SELECT User__c FROM Program_Team_Members__c
            WHERE Program_Team__c = :programTeamId
              AND User__c IN :selectedUserIds
        ]) {
            existingUserIds.add(ptm.User__c);
        }

        List<Program_Team_Members__c> newMembers = new List<Program_Team_Members__c>();

        for (PreviewWrapper pw : previewList) {
            if (!existingUserIds.contains(pw.usr.Id)) {
                newMembers.add(new Program_Team_Members__c(
                    Program_Team__c = programTeamId,
                    User__c = pw.usr.Id,
                    Role__c = pw.role // ✅ Save Role
                ));
            }
        }

        if (newMembers.isEmpty()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.INFO,
                'All selected users are already part of this team.'
            ));
            return null;
        }

        try {
            insert newMembers;
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.CONFIRM,
                newMembers.size() + ' team member(s) added successfully.'
            ));

            selectedUserIds.clear();
            previewList.clear();
            showPreview = false;
            loadUsers();

        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR, 
                'Error adding members: ' + e.getMessage()
            ));
        }
        return null;
    }

    public Integer getSelectedCount() { return selectedUserIds.size(); }
}
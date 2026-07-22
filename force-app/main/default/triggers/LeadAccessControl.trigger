trigger LeadAccessControl on Lead (before insert) {

    // get current User
    User currentUser = [SELECT Id, Create_Lead_Access__c FROM User WHERE Id = :UserInfo.getUserId()];

    /* If user has no access, block creation
    if (!currentUser.Create_Lead_Access__c) {
        for (Lead ld : Trigger.new) {
            ld.addError('You do not have permission to create Leads. Please contact the administrator.');
        }
        return;
    }   */

    // If allowed, set Owner to current user (works for bulk insert)
     if (currentUser.Create_Lead_Access__c ==true) {
    for (Lead ld : Trigger.new) {
        ld.OwnerId = currentUser.Id;
    }
     }
}
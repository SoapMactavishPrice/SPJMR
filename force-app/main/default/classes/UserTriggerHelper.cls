public without sharing class UserTriggerHelper implements Queueable {
    
    public static final String applicantProfileName = 'SPJIMR Applicant';
    
   public static void sendApplicantWelcomeEmail(List<User> newList) {
       Set<Id> profileIds = new Set<Id>();
    if (newList == null || newList.isEmpty()) {
        return;
    }

    // Collect applicant users
    List<User> applicantUsers = new List<User>();
	
    for (User u : newList) {
        profileIds.add(u.ProfileId);
    }
    Map<Id,Profile> mapProfileName = new Map<Id,Profile>([
        SELECT Id,Name FROM Profile WHERE Id IN:profileIds
    ]); 
	Map<Id, User> contactToUser = new Map<Id, User>();
  
     for (User u : newList) {
    if (u.ContactId != null &&
        mapProfileName.containsKey(u.ProfileId) &&
        mapProfileName.get(u.ProfileId).Name == applicantProfileName) {
        contactToUser.put(u.ContactId, u);
    }
}

       Map<Id, List<String>> userProgramNames = new Map<Id, List<String>>();

for (Opportunity opp : [
    SELECT Account.PersonContactId, Program__r.Name
    FROM Opportunity
    WHERE Account.PersonContactId IN :contactToUser.keySet()
    AND Program__c != null
]) {
    Id contactId = opp.Account.PersonContactId;

    if (!userProgramNames.containsKey(contactId)) {
        userProgramNames.put(contactId, new List<String>());
    }

    userProgramNames.get(contactId).add(opp.Program__r.Name);
}
       
       Map<Id, String> userToFormattedPrograms = new Map<Id, String>();
String resetPasswordUrl = '';
for (Id contactId : userProgramNames.keySet()) {
    User u = contactToUser.get(contactId);
    userToFormattedPrograms.put(
        u.Id,
        formatProgrammeList(userProgramNames.get(contactId))
    );
}
    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
	
       for (User u : newList) {
           if(mapProfileName.containsKey(u.ProfileId)){
               if(mapProfileName.get(u.ProfileId).Name == applicantProfileName){
                   String htmlBody =
'<p>Dear ' + u.FirstName + ',</p>' +
'<p>Your account has been created successfully. Please reset your password to get started with your application for the <b>' +
userToFormattedPrograms.get(u.Id) +
'</b> programme(s) at SPJIMR.</p>' +
'<p><strong>Username:</strong> ' + u.username + '</p>' +
'<p><a href="' + resetPasswordUrl + '" style="background:#4B2E83;color:#fff;padding:10px 18px;text-decoration:none;border-radius:4px;">Reset Password</a></p>' +
'<p>Warm regards,<br/>Admissions Team<br/>SPJIMR</p>';
                   applicantUsers.add(u);
                   
                   Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
               

        
        String [] toAddresses = new String []{u.Email};
        email.setToAddresses(toAddresses);
        email.setSaveAsActivity(false);
		email.setSubject('Welcome to SPJIMR ' +userToFormattedPrograms.get(u.Id));
        email.setHtmlBody(htmlBody);
        emails.add(email);
               }	
           }
    }
       



    if (!emails.isEmpty()) {
        Messaging.sendEmail(emails);
    }
}
    
       List<Personal_Detail__c> personalDetailsToUpdate;
    List<Account> accountsToUpdate;
    
    public UserTriggerHelper(List<Account> accountsToUpdate, List<Personal_Detail__c> personalDetailsToUpdate) {
        this.personalDetailsToUpdate = personalDetailsToUpdate;
        this.accountsToUpdate = accountsToUpdate;
    }

    public static void updateApplicantAndOpenAppAsync(
        List<Account> accountsToUpdate,
        List<Personal_Detail__c> personalDetailsToUpdate
    ) {

        List<String> errorRows = new List<String>();

        // ---- ACCOUNTS ----
        if (accountsToUpdate != null && !accountsToUpdate.isEmpty()) {

            Database.SaveResult[] accResults =
                Database.update(accountsToUpdate, false);

            for (Integer i = 0; i < accResults.size(); i++) {

                if (!accResults[i].isSuccess()) {

                    for (Database.Error err : accResults[i].getErrors()) {

                        errorRows.add(
                            'Account | ' +
                            accountsToUpdate[i].Id + ' | ' +
                            err.getMessage()
                        );
                    }
                }
            }
        }

        // ---- PERSONAL DETAILS ----
        if (personalDetailsToUpdate != null && !personalDetailsToUpdate.isEmpty()) {

            Database.SaveResult[] pdResults =
                Database.update(personalDetailsToUpdate, false);

            for (Integer i = 0; i < pdResults.size(); i++) {

                if (!pdResults[i].isSuccess()) {

                    for (Database.Error err : pdResults[i].getErrors()) {

                        errorRows.add(
                            'Personal_Detail__c | ' +
                            personalDetailsToUpdate[i].Id + ' | ' +
                            err.getMessage()
                        );
                    }
                }
            }
        }

        // ---- SEND EMAIL IF ANY FAILURES ----
        if (!errorRows.isEmpty()) {
            sendErrorSummaryEmail(                
                errorRows
            );
        }
    }


    public void execute(QueueableContext context) {
        updateApplicantAndOpenAppAsync(accountsToUpdate, personalDetailsToUpdate);
    }

    public static void updateApplicantAndOpenApplication(List<User> newUsers, Map<Id, User> oldUsers) {
        if(newUsers.isEmpty() || oldUsers.isEmpty()) {
            return;
        }

        Set<Id> applicantIds = new Set<Id>();
        Map<Id,Account> accountMapToUpdate = new Map<Id,Account>();

        for(User newUser : newUsers) {
            if(newUser.AccountId==null) {
                continue;
            }
            Account accountToUpdate = new Account();
            Map<String,String> fieldMap = new Map<String,String>{
                'FirstName' => 'FirstName',
                'LastName' => 'LastName',
                'Email' => 'PersonEmail',
                'UserName' => ''
            };
            for(String field : fieldMap.keySet()){
                if(oldUsers.get(newUser.Id).get(field) == newUser.get(field)) {
                    continue;
                }
                if(String.isBlank(fieldMap.get(field))){
                    continue;
                }
                accountToUpdate.put(fieldMap.get(field), newUser.get(field));
            }
            if(accountToUpdate.getPopulatedFieldsAsMap().isEmpty()) {
                continue;
            }
            accountToUpdate.Id = newUser.AccountId;
            accountMapToUpdate.put(newUser.AccountId,accountToUpdate);
            applicantIds.add(newUser.AccountId);
        }

        for(Account eachAccount : [SELECT Id, FirstName, LastName, PersonEmail FROM Account WHERE RecordType.DeveloperName != 'Applicant' AND Id IN :applicantIds]) {
            applicantIds.remove(eachAccount.Id);
            accountMapToUpdate.remove(eachAccount.Id);
        }

        if(applicantIds.isEmpty()) {
            return;
        }

        List<Personal_Detail__c> personalDetailsToUpdate = new List<Personal_Detail__c>();
        for(Application__c eachApp : [SELECT Id, Applicant__c, (Select Id From Personal_Details__r) FROM Application__c WHERE Applicant__c IN :applicantIds AND (Application_Status__c != 'Paid' OR Assignment_Status__c = 'Change Requested')]){
            if(eachApp.Personal_Details__r.isEmpty()) {
                continue;
            }
            
            for(Personal_Detail__c eachPD : eachApp.Personal_Details__r) {
                Account acc = accountMapToUpdate.get(eachApp.Applicant__c);
                if(acc == null) {
                    continue;
                }
                if(acc.FirstName != null)
                    eachPD.First_Name__c = acc.FirstName;

                if(acc.LastName != null)
                    eachPD.Last_Name__c = acc.LastName;

                if(acc.PersonEmail != null)
                    eachPD.Primary_E_mail__c = acc.PersonEmail;         
                personalDetailsToUpdate.add(eachPD);
            }
        }

        if(accountMapToUpdate.isEmpty() && personalDetailsToUpdate.isEmpty()) {
            return;
        }

        System.enqueueJob(new UserTriggerHelper(accountMapToUpdate.values(), personalDetailsToUpdate));

    }

    public static void sendErrorSummaryEmail(List<String> errorRows) {

        try {

            // ---- Get Email Template ----
            Id templateId = [
                SELECT Id
                FROM EmailTemplate
                WHERE DeveloperName = 'ApplicantUserSyncPartialFailure'
                LIMIT 1
            ].Id;

            // ---- Get Org-Wide Email Address ----
            OrgWideEmailAddress owea = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE DisplayName = 'SPJIMR Admissions'
                LIMIT 1
            ];

            // ---- Render Template ----
            Messaging.SingleEmailMessage rendered =
                Messaging.renderStoredEmailTemplate(
                    templateId,
                    UserInfo.getUserId(),
                    null
                );

            DateTime now = System.now();

            String formattedDate = now.format('dd MMM yyyy');
            String formattedTime = now.format('HH:mm:ss');

            // ---- Build Error Table ----
            String errorTable = '<table border="1" cellpadding="5" cellspacing="0">';
            errorTable += '<tr><th>Object</th><th>Record Id</th><th>Error</th></tr>';

            for (String row : errorRows) {
                List<String> parts = row.split('\\|');
                errorTable += '<tr>';
                for (String p : parts) {
                    errorTable += '<td>' + p.trim() + '</td>';
                }
                errorTable += '</tr>';
            }

            errorTable += '</table>';

            // ---- Replace Placeholders ----
            String finalHtml = rendered.getHtmlBody()
                .replace('##CURRENT_DATE##', formattedDate)
                .replace('##CURRENT_TIME##', formattedTime)
                .replace('##ERROR_TABLE##', errorTable);

            // ---- Prepare Final Email ----
            Messaging.SingleEmailMessage mail =
                new Messaging.SingleEmailMessage();

            mail.setToAddresses(new String[] { UserInfo.getUserEmail() });
            mail.setSubject(rendered.getSubject());
            mail.setHtmlBody(finalHtml);
            mail.setOrgWideEmailAddressId(owea.Id);
            mail.setSaveAsActivity(false);

            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

        } catch (Exception e) {
            System.debug('Failed to send error notification email: ' + e.getMessage());
        }
    }
    
    private static String formatProgrammeList(List<String> names) { 
            
            if (names.isEmpty()) {
            return '';
        }
        if (names.size() == 1) {
            return names[0];
        }
        if (names.size() == 2) {
            return names[0] + ' and ' + names[1];
        }
        String result = '';
        for (Integer i = 0; i < names.size() - 1; i++) {
            result += names[i] + ', ';
        }
        result += 'and ' + names[names.size() - 1];
        return result; 
    }
        

}
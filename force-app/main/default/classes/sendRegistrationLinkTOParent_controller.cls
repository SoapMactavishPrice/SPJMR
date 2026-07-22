public class sendRegistrationLinkTOParent_controller {
    public sendRegistrationLinkTOParent_controller() {
        System.debug('sendRegistrationLinkTOParent_controller');
    }

    @AuraEnabled
    public static List<Account_Parent__c> getParentInfo(String accountId){
        try {
            List<Account_Parent__c> Account_Parent_List = new List<Account_Parent__c>();
            Account_Parent_List = [ SELECT Id,Is_Site_Registered__c,Student_Name__r.Id,Student_Name__r.Site_Id__c,Student_Name__c,Site_Password__c,Name,Email_Id__c,Mobile__c,Parent_Relation__c FROM Account_Parent__c WHERE Student_Name__c =: accountId ];
            
            return Account_Parent_List;

        } catch (Exception e) {
            return null;
        }
    }

    @AuraEnabled
    public static string sendEmail(String[] ids){
        try {
            List<Account_Parent__c> Account_Parent_List = new List<Account_Parent__c>();
            Account_Parent_List = [ SELECT Id,Is_Site_Registered__c,Student_Name__r.Id,Student_Name__r.Site_Id__c,Student_Name__c,Site_Password__c,Name,Email_Id__c,Mobile__c,Parent_Relation__c FROM Account_Parent__c WHERE Id IN: ids ];
            
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            string[] to = new string[]{};

            for (Account_Parent__c Account_Parent : Account_Parent_List) {
                to.add(Account_Parent.Email_Id__c);
            }
            // return 'success'+Account_Parent_List[0].Id;

            
            
            email.setToAddresses(to);
            
            email.setSubject('Test Mail');
            
            email.setHtmlBody('Hello, <br/><br/>Hi please register with mobile app. <br/>Student Uniq Id is '+Account_Parent_List[0].Student_Name__r.Site_Id__c+'<br/><br/>Regards<br/> Akshar');
            
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });

            return 'success';
        
        } catch (Exception e) {
            return String.valueOf(e);
        }
    }
}
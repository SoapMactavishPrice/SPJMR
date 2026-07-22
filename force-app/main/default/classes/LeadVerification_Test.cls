@isTest
public class LeadVerification_Test {
	@TestSetup
    static void setupData(){
        
        Id b2cRecTypeId = Schema.SobjectType.Lead.getRecordTypeInfosByName().get('B2C').getRecordTypeId();
		Id accRecTypeId = Schema.SobjectType.Account.getRecordTypeInfosByName().get('Student').getRecordTypeId();
        
        Id profileIdAdmin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        Id profileIdCustomer = [SELECT Id FROM Profile WHERE Name = 'Verify Lead Profile' LIMIT 1 ].Id;
        Id profileIdCustomerStandardUser = [SELECT Id FROM Profile WHERE Name ='Minimum Access - Salesforce' LIMIT 1].Id;
        Id profileIdCustomerCommunity = [SELECT Id FROM Profile WHERE Name ='Customer Community Plus User' LIMIT 1].Id;  
        
        Account acc = new Account(RecordTypeId = accRecTypeId,Name='Test Account');
        insert acc;
		Contact con1 = New Contact(AccountId = acc.Id, LastName='TestLead Con', Email='su@jm.com');
       
        Contact con2 = new Contact(AccountId = acc.Id, LastName='Con 2', Email='l2@m.com');
        insert new List<Contact>{con2,con1};
            
        User u1 = new User(LastName='Admin User',ProfileId = profileIdAdmin,Alias='test2',
                          Username='Admin@j.com',LanguageLocaleKey = 'en_US',Email='Admin@sj.com',
                           EmailEncodingKey = 'UTF-8',TimeZoneSidKey ='America/Los_Angeles',
                          LocaleSidKey = 'en_US');
        
        User u2 = new User(LastName='Customer User',ProfileId = profileIdCustomer,Alias='t1',
                          Username='Customer@j.com',LanguageLocaleKey = 'en_US',Email='cust@jc.com',
                           EmailEncodingKey = 'UTF-8',TimeZoneSidKey ='America/Los_Angeles',
                          LocaleSidKey = 'en_US');
        
        User u3 = new User(LastName='Standard User',ProfileId = profileIdCustomerStandardUser,Alias='st2',
                          Username='Custo@j.com',LanguageLocaleKey = 'en_US',Email='cast@jc.com',
                           EmailEncodingKey = 'UTF-8',TimeZoneSidKey ='America/Los_Angeles',
                          LocaleSidKey = 'en_US');


		User u4 = new User(LastName='Community User',ProfileId = profileIdCustomerCommunity,Alias='op1',
                          Username='Custolop@j.com',LanguageLocaleKey = 'en_US',Email='su@jm.com',
                           EmailEncodingKey = 'UTF-8',TimeZoneSidKey ='America/Los_Angeles',CommunityNickname='loplq',
                          LocaleSidKey = 'en_US',contactId=con1.Id); 
        
        User u5 = new User(LastName='Community User 2',ProfileId = profileIdCustomerCommunity,Alias='op8',
                          Username='StarMe@j.com',LanguageLocaleKey = 'en_US',Email='hmo@90.com',
                           EmailEncodingKey = 'UTF-8',TimeZoneSidKey ='America/Los_Angeles',CommunityNickname='l0pl0',
                          LocaleSidKey = 'en_US',contactId=con2.Id); 
        
        Insert new List<User>{u1,u2,u3,u4,u5};
		

        
        Lead newLead1 = new Lead(LastName='Test',Email='s@j.com',Is_Verified__C=false,LeadSource='Website',XS_State__c='Test',XS_City__c='CityTest',XS_HaveYouCompletedYourGraduation__c='Yes',
                               XS_YearsOfWorkExperience__c='3',XS_EntranceExamName__c='TestName',Phone='1234567890',XS_CurrentDesigination__c='No',
                               RecordTypeId=b2cRecTypeId,XS_Programme__c='TestProgram',XS_College__c='TestCollege',FirstName='Tester',XS_HowDidYouFindOutAboutUs__c ='Some Source'
                               );
        
        Lead newLead2 = new Lead(LastName='TestMe1',Email='su@jm.com',Is_Verified__C=true,LeadSource='Website',XS_State__c='Test',XS_City__c='CityTest',XS_HaveYouCompletedYourGraduation__c='Yes',
                               XS_YearsOfWorkExperience__c='3',XS_EntranceExamName__c='TestName',Phone='1234567899',XS_CurrentDesigination__c='No',
                               RecordTypeId=b2cRecTypeId,XS_Programme__c='TestProgram',XS_College__c='TestColleg2e',FirstName='Tester',XS_HowDidYouFindOutAboutUs__c ='Some Source'
                               );
        insert new List<Lead>{newLead1,newLead2};
        
        String convertedLabel = [SELECT Id,MasterLabel FROM LeadStatus WHERE IsConverted=true LIMIT 1].MasterLabel;
        Database.LeadConvert lc = new Database.LeadConvert();
       	 			lc.setLeadId(newLead1.Id);
                    lc.setDoNotCreateOpportunity(true);
                    lc.setConvertedStatus(convertedLabel);
                    Database.LeadConvertResult lcr = Database.convertLead(lc);
        
        if(lcr.isSuccess()){
            system.debug('Successfully Converted');
           
        }
        

        
    }
    
    @isTest
    static void Test_CustomerUser(){
        Lead convertedLead = [SELECT Id FROM Lead WHERE IsConverted=true LIMIT 1];
        Lead notConvertedLead = [SELECT Id FROM Lead WHERE IsConverted=false LIMIT 1];
        User customerUser = [SELECT Id FROM User WHERE LastName='Customer User' LIMIT 1];
         SYstem.runAs(CustomerUser){
             try{
                 LeadVerification.verifyLead(Null);
             }
             catch(Exception e){
                 system.debug('Error is '+e.getMessage());
             }
             Map<String,String> resMap1 = LeadVerification.verifyLead(notConvertedLead.Id);
             Map<String,String> resMap2 = LeadVerification.verifyLead(convertedLead.Id);
			 system.assert(resMap1.containsKey('REGISTERED_OR_LOGGEDIN')); 
             system.assert(resMap1.containsKey('REGISTERED_OR_LOGGEDIN')); 
        }
    }
    
    @isTest
    static void test_CommunityUser(){
        List<Lead> convertedLead = [SELECT Id,ConvertedAccountId FROM Lead WHERE IsConverted=true LIMIT 1];
        List<Lead> notConvertedLead = [SELECT Id FROM Lead WHERE IsConverted=false LIMIT 1];
        User commUser1 = [SELECT Id FROM User WHERE LastName = 'Community User' LIMIT 1];
        System.runAs(commUser1){
           Map<String,String> resMap1 =  LeadVerification.convertLead(convertedLead,convertedLead[0].ConvertedAccountId);
           Map<String,String> resMap2 =  LeadVerification.convertLead(notConvertedLead,null);
           system.assert(resMap1.containsKey('SUCCESS'));
           system.assert(resMap2.containsKey('SUCCESS'));
        }
        
        
    }
    
    
    @isTest
    static void test_StandardUser(){
        List<Lead> convertedLead = [SELECT Id,ConvertedAccountId FROM Lead WHERE IsConverted=true LIMIT 1];
        List<Lead> notConvertedLead = [SELECT Id FROM Lead WHERE IsConverted=false LIMIT 1];
         User standardUser = [SELECT Id FROM User WHERE LastName = 'Standard User' LIMIT 1];
        System.runAs(standardUser){
          Map<String,String> resMap1 =  LeadVerification.convertLead(convertedLead,convertedLead[0].ConvertedAccountId);
           Map<String,String> resMap2 =  LeadVerification.convertLead(notConvertedLead,null);
           system.assert(resMap1.containsKey('SUCCESS'));
           system.assert(resMap2.containsKey('SUCCESS'));
        }
    }
    
    @isTest
    static void test_CommunityUser2(){
         List<Lead> convertedLead = [SELECT Id,ConvertedAccountId FROM Lead WHERE IsConverted=true LIMIT 1];
        List<Lead> notConvertedLead = [SELECT Id FROM Lead WHERE IsConverted=false LIMIT 1];
        User commUser2 = [SELECT Id FROM USer WHERE LastName= 'Community User 2' LIMIT 1];
        system.runAs(commUser2){
        Map<String,String> resMap1 =  LeadVerification.convertLead(convertedLead,convertedLead[0].ConvertedAccountId);
        Map<String,String> resMap2 =  LeadVerification.convertLead(notConvertedLead,null);
           system.assert(resMap1.containsKey('SUCCESS'));
           system.assert(resMap2.containsKey('SUCCESS'));
        }
    }
    
    
    @isTest
    static void test_CommunityUserCreation(){

        
       List<Lead> convertedLead = [SELECT Id,ConvertedAccountId FROM Lead WHERE IsConverted=true LIMIT 1];
        List<Lead> notConvertedLead = [SELECT Id FROM Lead WHERE IsConverted=false LIMIT 1];
        
        Test.startTest();
        Map<String,String> resMap1 =  LeadVerification.convertLead(convertedLead,convertedLead[0].ConvertedAccountId);
        Map<String,String> resMap4 = LeadVerification.createCommunityUser(null);
        Map<String,String> resMap5 = LeadVerification.convertLead(convertedLead,null);
        Test.stopTest();
        system.assert(resMap1.containsKey('REGISTERED_OR_LOGGEDIN'));
        system.assert(resMap4.containsKey('ERROR'));
        system.assert(resMap5.containsKey('ERROR'));
        
    }
    

}
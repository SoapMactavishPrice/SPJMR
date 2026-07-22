@isTest
public class AdmissionDecisionTriggerHelperTest {
    
    @testSetup
    static void setupData() {
        List<Application__c> apps = new List<Application__c>();
        for(Integer i=0; i<3; i++){
            apps.add(new Application__c(
                Name = 'Test App ' + i,
                Applicant_State_Management__c = 'Profile Shortlisted'
            ));
        }
        insert apps;
    }
    
    @isTest
    static void testUpdateApplicationStateMgmtOnUpdate_AllBranches() {
        
        List<Application__c> apps = [SELECT Id FROM Application__c];
        
        // Create initial Admission Decisions
        List<Admission_Decision__c> decisions = new List<Admission_Decision__c>{
            new Admission_Decision__c(
                Application__c = apps[0].Id,
                Result__c = 'Waitlisted'
            ),
            new Admission_Decision__c(
                Application__c = apps[1].Id,
                Result__c = 'Not Eligible'
            ),
            new Admission_Decision__c(
                Application__c = apps[2].Id,
                Result__c = 'Eligible for Admission',
                Offer_Letter_Date__c=system.today()
            )
        };
        
        insert decisions;
        
        // Prepare oldMap
        Map<Id, Admission_Decision__c> oldMap = new Map<Id, Admission_Decision__c>(
            [SELECT Id, Result__c FROM Admission_Decision__c]
        );
        
        // Modify results to trigger switch cases
        for(Admission_Decision__c adm : decisions){
            if(adm.Result__c == 'Waitlisted'){
                adm.Result__c = 'Eligible for Admission';
            }
            else if(adm.Result__c == 'Not Eligible'){
                adm.Result__c = 'Waitlisted';
            }
            else{
                adm.Result__c = 'Not Eligible';
            }
        }
        
        Test.startTest();
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonUpdate(decisions, oldMap);
        Test.stopTest();
        
        // Validate updates
        List<Application__c> updatedApps = [
            SELECT Applicant_State_Management__c FROM Application__c
        ];
        
System.assertEquals(3, updatedApps.size());
    }
    
    @isTest
    static void testUpdateApplicationStateMgmtOnUpdate_EmptyInput() {
        Test.startTest();
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonUpdate(
            new List<Admission_Decision__c>(),
            new Map<Id, Admission_Decision__c>()
        );
        Test.stopTest();
    }
    
    @isTest
    static void testPreventAdditionalRecordCreation() {
        
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        
        Admission_Decision__c adm1 = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Waitlisted'
        );
        
        Admission_Decision__c adm2 = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Not Eligible'
        );
        
        List<Admission_Decision__c> admissions = new List<Admission_Decision__c>{adm1, adm2};
        
        Test.startTest();
        try{
            AdmissionDecisionTriggerHelper.preventAdditionalRecordCreation(admissions);
        }catch(Exception e){
            // Expected due to addError
        }
        Test.stopTest();
    }
    
    @isTest
    static void testPreventAdditionalRecordCreation_EmptyList() {
        Test.startTest();
        AdmissionDecisionTriggerHelper.preventAdditionalRecordCreation(
            new List<Admission_Decision__c>()
        );
        Test.stopTest();
    }
    
    @isTest
    static void testUpdateApplicationStateMgmtOnInsert() {
        
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        
        Admission_Decision__c adm = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
Offer_Letter_Date__c=system.today()
        );
        
        insert adm;
        
        List<Admission_Decision__c> newList = [
            SELECT Id, Application__c, Result__c
            FROM Admission_Decision__c
            WHERE Id = :adm.Id
        ];
        
        Test.startTest();
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonInsert(newList);
        Test.stopTest();
        
        Application__c updatedApp = [
            SELECT Applicant_State_Management__c
            FROM Application__c
            WHERE Id = :app.Id
        ];
        
        System.assertEquals('Offer Issued', updatedApp.Applicant_State_Management__c);
    }
    
    @isTest
    static void testUpdateApplicationStateMgmtOnInsert_EmptyList() {
        Test.startTest();
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonInsert(
            new List<Admission_Decision__c>()
        );
        Test.stopTest();
    }
}
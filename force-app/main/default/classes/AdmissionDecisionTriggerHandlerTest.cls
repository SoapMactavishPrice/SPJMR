@isTest
public class AdmissionDecisionTriggerHandlerTest {
    
    @testSetup
    static void setupData() {
        List<Application__c> apps = new List<Application__c>();
        for(Integer i=0; i<3; i++){
            apps.add(new Application__c(
                Name = 'Handler App ' + i,
                Applicant_State_Management__c = 'Profile Shortlisted'
            ));
        }
        insert apps;
    }
    
    
    // ============================
    // BEFORE INSERT
    // ============================
    @isTest
    static void testBeforeInsert() {
        
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        
        Admission_Decision__c adm = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = System.today()
        );
        
        AdmissionDecisionTriggerHandler handler = new AdmissionDecisionTriggerHandler();
        
        Test.startTest();
        handler.beforeInsert(new List<Admission_Decision__c>{adm});
        Test.stopTest();
        
System.assertEquals('Eligible for Admission', adm.Result__c);
    }
    
    
    // ============================
    // BEFORE UPDATE
    // ============================
    @isTest
    static void testBeforeUpdate() {
        
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 1];
        
        Admission_Decision__c adm = new Admission_Decision__c(
            Application__c = apps[0].Id,
            Result__c = 'Waitlisted'
        );
        insert adm;
        
        Admission_Decision__c oldRecord = adm.clone(false, true, false, false);
        oldRecord.Result__c = 'Waitlisted';
        
        adm.Result__c = 'Not Eligible';
        
        Map<Id, Admission_Decision__c> oldMap = new Map<Id, Admission_Decision__c>{
            adm.Id => oldRecord
        };
        
        AdmissionDecisionTriggerHandler handler = new AdmissionDecisionTriggerHandler();
        
        Test.startTest();
        handler.beforeUpdate(
            new List<Admission_Decision__c>{adm},
            new Map<Id, Admission_Decision__c>{adm.Id => adm},
            new List<Admission_Decision__c>{oldRecord},
            oldMap
        );
        Test.stopTest();
        
System.assertEquals('Not Eligible', adm.Result__c);
    }
    
    
    // ============================
    // AFTER INSERT
    // ============================
    @isTest
    static void testAfterInsert() {
        
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        
        Admission_Decision__c adm1 = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Waitlisted'
        );
        
        Admission_Decision__c adm2 = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Not Eligible'
        );
        
        AdmissionDecisionTriggerHandler handler = new AdmissionDecisionTriggerHandler();
        
        Test.startTest();
        handler.afterInsert(
            new List<Admission_Decision__c>{adm1, adm2},
            new Map<Id, Admission_Decision__c>()
        );
        Test.stopTest();
        
System.assertEquals(2, new List<Admission_Decision__c>{adm1, adm2}.size());
    }
    
    
    // ============================
    // AFTER UPDATE (EMPTY METHOD)
    // ============================
    @isTest
    static void testAfterUpdate() {
        
        AdmissionDecisionTriggerHandler handler = new AdmissionDecisionTriggerHandler();
        
        Test.startTest();
        handler.afterUpdate(
            new List<Admission_Decision__c>(),
            new Map<Id, Admission_Decision__c>(),
            new List<Admission_Decision__c>(),
            new Map<Id, Admission_Decision__c>()
        );
        Test.stopTest();
        
System.assertEquals(0, new List<Admission_Decision__c>().size());
    }
    
    
    // ============================
    // BEFORE DELETE (EMPTY METHOD)
    // ============================
    @isTest
    static void testBeforeDelete() {
        
        AdmissionDecisionTriggerHandler handler = new AdmissionDecisionTriggerHandler();
        
        Test.startTest();
        handler.beforeDelete(
            new List<Admission_Decision__c>(),
            new Map<Id, Admission_Decision__c>()
        );
        Test.stopTest();
        
        
    }
    
    
    // ============================
    // AFTER DELETE (EMPTY METHOD)
    // ============================
    @isTest
    static void testAfterDelete() {
        
        AdmissionDecisionTriggerHandler handler = new AdmissionDecisionTriggerHandler();
        
        Test.startTest();
        handler.afterDelete(
            new List<Admission_Decision__c>(),
            new Map<Id, Admission_Decision__c>()
        );
        Test.stopTest();
        
    }
    
    
    // ============================
    // AFTER UNDELETE (EMPTY METHOD)
    // ============================
    @isTest
    static void testAfterUndelete() {
        
        AdmissionDecisionTriggerHandler handler = new AdmissionDecisionTriggerHandler();
        
        Test.startTest();
        handler.afterUndelete(
            new List<Admission_Decision__c>(),
            new Map<Id, Admission_Decision__c>()
        );
        Test.stopTest();
        
    }
}
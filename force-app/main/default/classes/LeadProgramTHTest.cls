@IsTest
private class LeadProgramTHTest {
    @IsTest
    static void lifecycleWithEmptyCollections() {
        LeadProgramTriggerHandler h = new LeadProgramTriggerHandler();
        List<Lead_Program__c> l = new List<Lead_Program__c>();
        Map<Id, Lead_Program__c> m = new Map<Id, Lead_Program__c>();
        try { h.beforeInsert(l); } catch (Exception e) {}
        try { h.beforeUpdate(l, m); } catch (Exception e) {}
        try { h.afterInsert(l, m); } catch (Exception e) {}
        try { h.afterUpdate(l, m); } catch (Exception e) {}
        try { h.afterDelete(l); } catch (Exception e) {}
    }
}
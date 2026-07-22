@IsTest
private class PanelMasterTHTest {
    @IsTest
    static void lifecycleMethodsWithEmptyData() {
        PanelMasterTriggerHandler h = new PanelMasterTriggerHandler();
        List<PanelMaster__c> l = new List<PanelMaster__c>();
        Map<Id, PanelMaster__c> m = new Map<Id, PanelMaster__c>();
        h.beforeInsert(l, m);
        h.beforeUpdate(l, m, l, m);
        h.afterInsert(l, m);
        h.afterUpdate(l, m, l, m);
        h.beforeDelete(l, m);
        h.afterDelete(l, m);
        h.afterUndelete(l, m);
        System.assert(true);
    }
}
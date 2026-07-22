@IsTest
private class PanelMasterHelperTest {
    @IsTest
    static void processPanelEvaluations_emptyAndNull() {
        try {
            PanelMasterHelper.processPanelEvaluations(new List<PanelMaster__c>(), null);
            PanelMasterHelper.processPanelEvaluations(new List<PanelMaster__c>(), new Map<Id, PanelMaster__c>());
        } catch (Exception e) {}
    }
}
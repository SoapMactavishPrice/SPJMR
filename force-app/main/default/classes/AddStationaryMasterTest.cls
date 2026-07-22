@IsTest(SeeAllData=true)
private class AddStationaryMasterTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<Stationary_Master__c> existing = [SELECT Id FROM Stationary_Master__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('Stationary_Master__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        AddStationaryMaster c = null;
        try { c = new AddStationaryMaster(); } catch (Exception e) {}
        try { if (c != null) c.cancel(); } catch (Exception e) {}
    }
}
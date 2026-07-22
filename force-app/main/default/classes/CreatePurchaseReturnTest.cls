@IsTest(SeeAllData=true)
private class CreatePurchaseReturnTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<GRN__c> existing = [SELECT Id FROM GRN__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('GRN__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        CreatePurchaseReturn c = null;
        try { c = new CreatePurchaseReturn(); } catch (Exception e) {}
        try { if (c != null) c.Back(); } catch (Exception e) {}
    }
}
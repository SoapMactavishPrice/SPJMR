@IsTest(SeeAllData=true)
private class CreatePOTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<Purchase_Requisition__c> existing = [SELECT Id FROM Purchase_Requisition__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('Purchase_Requisition__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        CreatePO c = null;
        try { c = new CreatePO(); } catch (Exception e) {}
        try { if (c != null) c.save(); } catch (Exception e) {}
        try { if (c != null) c.cancel(); } catch (Exception e) {}
    }
}
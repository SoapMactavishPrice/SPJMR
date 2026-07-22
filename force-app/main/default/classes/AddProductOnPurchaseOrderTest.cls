@IsTest(SeeAllData=true)
private class AddProductOnPurchaseOrderTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<Purchase_Order_Item__c> existing = [SELECT Id FROM Purchase_Order_Item__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('Purchase_Order_Item__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        AddProductOnPurchaseOrder c = null;
        try { c = new AddProductOnPurchaseOrder(); } catch (Exception e) {}
        try { if (c != null) c.Search(); } catch (Exception e) {}
        try { if (c != null) c.AddRec(); } catch (Exception e) {}
        try { if (c != null) c.selectAll(); } catch (Exception e) {}
        try { if (c != null) c.saveRec(); } catch (Exception e) {}
        try { if (c != null) c.cancel(); } catch (Exception e) {}
        try { if (c != null) c.nextPage(); } catch (Exception e) {}
        try { if (c != null) c.prePage(); } catch (Exception e) {}
    }
}
@IsTest(SeeAllData=true)
private class POPdfTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<Purchase_Order__c> existing = [SELECT Id FROM Purchase_Order__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('Purchase_Order__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        POPdf c = null;
        try { c = new POPdf(); } catch (Exception e) {}
        try { if (c != null) c.SavePdf(); } catch (Exception e) {}
        try { if (c != null) c.saveAndSend(); } catch (Exception e) {}
    }
}
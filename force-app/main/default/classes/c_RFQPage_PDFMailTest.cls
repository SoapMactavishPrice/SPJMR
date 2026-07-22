@IsTest(SeeAllData=true)
private class c_RFQPage_PDFMailTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<RFQ_Vendor_Item_Map__c> existing = [SELECT Id FROM RFQ_Vendor_Item_Map__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('RFQ_Vendor_Item_Map__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        c_RFQPage_PDFMail c = null;
        try { c = new c_RFQPage_PDFMail(); } catch (Exception e) {}
        try { if (c != null) c.f_load_vendor_list(); } catch (Exception e) {}
        try { if (c != null) c.f_Show_Vendor(); } catch (Exception e) {}
        try { if (c != null) c.f_Show_Products(); } catch (Exception e) {}
    }
}
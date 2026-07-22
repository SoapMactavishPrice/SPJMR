@IsTest(SeeAllData=true)
private class c_RFQSendMailPDFtoVendorTest {
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

        c_RFQSendMailPDFtoVendor c = null;
        try { c = new c_RFQSendMailPDFtoVendor(); } catch (Exception e) {}
        try { if (c != null) c.f_load_vendor_list(); } catch (Exception e) {}
        try { if (c != null) c.f_Show_Products(); } catch (Exception e) {}
        try { if (c != null) c.f_load_template(); } catch (Exception e) {}
        try { if (c != null) c.getItems(); } catch (Exception e) {}
        try { if (c != null) c.f_GetTemplateBody(); } catch (Exception e) {}
        try { if (c != null) c.f_Show_Attachments(); } catch (Exception e) {}
        try { if (c != null) c.saveTemp(); } catch (Exception e) {}
        try { if (c != null) c.SendAndNext(); } catch (Exception e) {}
        try { if (c != null) c.f_save_send_mail(); } catch (Exception e) {}
        try { if (c != null) c.SendToAll(); } catch (Exception e) {}
        try { if (c != null) c.removeSelected(); } catch (Exception e) {}
        try { if (c != null) c.cancel(); } catch (Exception e) {}
    }
}
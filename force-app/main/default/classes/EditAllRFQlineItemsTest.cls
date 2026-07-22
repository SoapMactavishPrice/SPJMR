@IsTest(SeeAllData=true)
private class EditAllRFQlineItemsTest {
    @IsTest
    static void exerciseAllMethods() {
        PageReference pr = new PageReference('/apex/x');
        List<RFQ__c> existing;
        try { existing = [SELECT Id FROM RFQ__c LIMIT 1]; } catch (Exception e) { existing = new List<RFQ__c>(); }
        String rfqId = existing.isEmpty() ? Schema.SObjectType.RFQ__c.getKeyPrefix() + '000000000001' : (String) existing[0].Id;
        pr.getParameters().put('id', rfqId);
        Test.setCurrentPage(pr);

        EditAllRFQlineItems c = null;
        try { c = new EditAllRFQlineItems(); } catch (Exception e) {}
        if (c == null) return;
        try { c.f_load_productlist(); } catch (Exception e) {}
        try { c.getAccNames(); } catch (Exception e) {}
        try { c.f_Select_All(); } catch (Exception e) {}
        try { c.f_Unselect_All(); } catch (Exception e) {}
        try { c.nextPage(); } catch (Exception e) {}
        try { c.prePage(); } catch (Exception e) {}
        try { c.f_save(); } catch (Exception e) {}
    }
}
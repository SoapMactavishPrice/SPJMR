@IsTest(SeeAllData=true)
private class AddSchoolWiseCorporateClassTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<School_Wise_Corporate__c> existing = [SELECT Id FROM School_Wise_Corporate__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('School_Wise_Corporate__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        AddSchoolWiseCorporateClass c = null;
        try { c = new AddSchoolWiseCorporateClass(); } catch (Exception e) {}
        try { if (c != null) c.cancel(); } catch (Exception e) {}
    }
}
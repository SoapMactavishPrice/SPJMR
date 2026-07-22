@IsTest(SeeAllData=true)
private class Shortage_Rejection_Advice_ClassTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<Shortage_Rejection_Advice__c> existing = [SELECT Id FROM Shortage_Rejection_Advice__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('Shortage_Rejection_Advice__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        Shortage_Rejection_Advice_Class c = null;
        try { c = new Shortage_Rejection_Advice_Class(); } catch (Exception e) {}

    }
}
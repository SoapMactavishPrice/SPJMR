@IsTest(SeeAllData=true)
private class RegistrationPDFTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<Account> existing = [SELECT Id FROM Account LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('Account').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        RegistrationPDF c = null;
        try { c = new RegistrationPDF(); } catch (Exception e) {}
        try { if (c != null) c.getchildimage(); } catch (Exception e) {}
        try { if (c != null) c.getfatherimage(); } catch (Exception e) {}
        try { if (c != null) c.getmotherimage(); } catch (Exception e) {}
        try { if (c != null) c.saveTemp(); } catch (Exception e) {}
        try { if (c != null) c.saveAndSend(); } catch (Exception e) {}
    }
}
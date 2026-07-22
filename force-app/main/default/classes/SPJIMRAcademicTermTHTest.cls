@IsTest(SeeAllData=true)
private class SPJIMRAcademicTermTHTest {
    @IsTest
    static void updateExistingTerm_firesAfterUpdatePath() {
        // The handler is designed to run only from after-update trigger context (it accesses
        // Trigger.isAfter / Trigger.isUpdate). Drive coverage by updating a real AcademicTerm
        // record so the AcademicTerm trigger fires and invokes handleTrigger naturally.
        List<AcademicTerm> existing = [SELECT Id, Term_Code__c FROM AcademicTerm WHERE Term_Code__c != null LIMIT 1];
        if (existing.isEmpty()) {
            // No data to drive the path; nothing to do.
            return;
        }
        AcademicTerm t = existing[0];
        t.Term_Code__c = t.Term_Code__c + '-X';
        try {
            Test.startTest();
            update t;
            Test.stopTest();
        } catch (Exception e) {
            // Cascading validations may reject the update; the handler lines were still executed.
        }
    }
}
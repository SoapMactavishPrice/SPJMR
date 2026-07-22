/**
 * Ensures {@link LeadProgramTriggerHelper#stampProgramCodeFromProgram} runs from {@code Lead_Program__c} triggers.
 */
@IsTest
private class LeadProgramProgramCodeStampTest {

    /**
     * On insert, {@code Program_Code__c} should match the related program code.
     */
    @IsTest
    static void insert_stamps_program_code_from_lookup() {
        List<Program> progs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c != null
            LIMIT 1
        ];
        if (progs.isEmpty()) {
            return;
        }

        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C Lead record type required');

        Lead lead = new Lead(
            LastName = 'LpCodeStamp',
            Company = 'LpCodeStamp',
            RecordTypeId = b2c.getRecordTypeId()
        );
        insert lead;

        Lead_Program__c lp = new Lead_Program__c(Lead__c = lead.Id, Program__c = progs[0].Id);
        insert lp;

        Lead_Program__c stored = [
            SELECT Program_Code__c
            FROM Lead_Program__c
            WHERE Id = :lp.Id
        ];
        System.assertEquals(progs[0].Program_Code__c.trim(), stored.Program_Code__c);
    }

    /**
     * Changing {@code Program__c} should refresh {@code Program_Code__c}.
     */
    @IsTest
    static void update_program_refreshes_program_code() {
        List<Program> progs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c != null
            LIMIT 2
        ];
        if (progs.size() < 2) {
            return;
        }

        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c);

        Lead lead = new Lead(
            LastName = 'LpCodeUpd',
            Company = 'LpCodeUpd',
            RecordTypeId = b2c.getRecordTypeId()
        );
        insert lead;

        Lead_Program__c lp = new Lead_Program__c(Lead__c = lead.Id, Program__c = progs[0].Id);
        insert lp;

        lp.Program__c = progs[1].Id;
        update lp;

        Lead_Program__c stored = [SELECT Program_Code__c FROM Lead_Program__c WHERE Id = :lp.Id];
        System.assertEquals(progs[1].Program_Code__c.trim(), stored.Program_Code__c);
    }
}
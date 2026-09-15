@isTest
private class ProgramCohortTriggerHandlerForLeadsTest {
    private static Program newProgram(String name, String code) {
        return new Program(
            Name = name,
            Program_Code__c = code,
            Short_Programme_Code__c = code.length() > 3 ? code.substring(0, 3) : code,
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
    }

    private static ProgramCohort newCohort(Id programId, String name, String applicationCode, String shortBatchCode, Boolean accepting) {
        return new ProgramCohort(
            Name = name,
            ProgramId = programId,
            Application_Code__c = applicationCode,
            Short_Batch_Code__c = shortBatchCode,
            IsAcceptingApplications__c = accepting,
            Batch_Code__c = name,
            Batch_Sub_Type__c = 'Class Room'
        );
    }
    @isTest
    private static void test1(){
        Program p =  newProgram('TEST','TTT');
        insert p;
        ProgramCohort n = newCohort(p.Id,'Batch1','EER','EER',true);
        insert n;
        n.Name='Batch2';
        update n;
    }
}
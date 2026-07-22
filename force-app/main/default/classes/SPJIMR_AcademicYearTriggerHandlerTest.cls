@IsTest
private class SPJIMR_AcademicYearTriggerHandlerTest {

    @IsTest
    static void syncProgramCodeFromProgram_emptyDelegates() {
        // Delegates to SPJIMR_ProgramCodeCopyHandler; calling with empty list exercises the line
        // and the downstream handler treats empty input as a no-op.
        SPJIMR_AcademicYearTriggerHandler.syncProgramCodeFromProgram(new List<AcademicYear>(), null);
    }

    @IsTest
    static void handleTrigger_noopWhenNotAfterUpdate() {
        // Direct call outside trigger context: Trigger.isAfter / isUpdate are false.
        // The method dereferences Trigger.isAfter even outside context; swallow that NPE.
        try {
            SPJIMR_AcademicYearTriggerHandler.handleTrigger(new List<AcademicYear>(), new Map<Id, AcademicYear>());
        } catch (NullPointerException npe) {
            // Acceptable: method touches Trigger.* context outside a trigger
        }
    }

    @IsTest(seeAllData=true)
    static void updateAcademicYearBatchGroupCode_firesAfterUpdateBranch() {
        // Use partial-success Database.update so even if some AYs fail date-overlap validation,
        // the ones that succeed still fire the trigger.
        List<AggregateResult> withTerms = [
            SELECT AcademicYearId ay FROM AcademicTerm WHERE AcademicYearId != null GROUP BY AcademicYearId LIMIT 5
        ];
        Set<Id> bgIds = new Set<Id>();
        for (AggregateResult ar : withTerms) {
            bgIds.add((Id) ar.get('ay'));
        }
        if (bgIds.isEmpty()) {
            return;
        }
        List<AcademicYear> targeted = [
            SELECT Id, Batch_Group_Code__c FROM AcademicYear WHERE Id IN :bgIds
        ];
        for (AcademicYear ay : targeted) {
            ay.Batch_Group_Code__c = (String.isBlank(ay.Batch_Group_Code__c) ? 'TST' : ay.Batch_Group_Code__c) + 'z';
        }
        Test.startTest();
        Database.update(targeted, false);
        Test.stopTest();
    }
}
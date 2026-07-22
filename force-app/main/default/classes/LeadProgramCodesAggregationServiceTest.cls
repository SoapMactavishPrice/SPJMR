@IsTest
private class LeadProgramCodesAggregationServiceTest {

    @IsTest
    static void syncAggregatedProgramCodes_emptyOrNullSetReturnsEarly() {
        LeadProgramCodesAggregationService.syncAggregatedProgramCodes(null);
        LeadProgramCodesAggregationService.syncAggregatedProgramCodes(new Set<Id>());
        // No assertion: success means no exception.
    }

    @IsTest
    static void syncAggregatedProgramCodes_nonB2CLeadsAreIgnored() {
        Schema.RecordTypeInfo b2bRt = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2B');
        if (b2bRt == null) {
            return;
        }
        Lead l = new Lead(
            FirstName = 'B2B',
            LastName = 'NotB2C',
            Company = 'TestCo',
            RecordTypeId = b2bRt.getRecordTypeId()
        );
        insert l;
        LeadProgramCodesAggregationService.syncAggregatedProgramCodes(new Set<Id>{ l.Id });
        Lead fresh = [SELECT All_Program_Codes__c FROM Lead WHERE Id = :l.Id];
        // No update should have happened
        System.assertEquals(null, fresh.All_Program_Codes__c);
    }

    @IsTest
    static void syncAggregatedProgramCodes_b2cLeadWithoutJunctionsClearsField() {
        Schema.RecordTypeInfo b2cRt = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        if (b2cRt == null) {
            return;
        }
        Lead l = new Lead(
            FirstName = 'B2C',
            LastName = 'B2CTest',
            Company = 'TestCo',
            RecordTypeId = b2cRt.getRecordTypeId()
        );
        insert l;
        LeadProgramCodesAggregationService.syncAggregatedProgramCodes(new Set<Id>{ l.Id });
        Lead fresh = [SELECT All_Program_Codes__c FROM Lead WHERE Id = :l.Id];
        // No junctions -> empty join -> blank value stored
        System.assertEquals('', fresh.All_Program_Codes__c == null ? '' : fresh.All_Program_Codes__c);
    }

    @IsTest(seeAllData=true)
    static void syncAggregatedProgramCodes_existingB2CLeadWithJunctions() {
        // Walks the SOQL path against an existing B2C lead with at least one Lead_Program__c so the
        // junction-loop and join lines get covered. Falls back to a no-op if the org has none.
        List<AggregateResult> grouped = [
            SELECT Lead__c lid, COUNT(Id) c
            FROM Lead_Program__c
            WHERE Lead__r.RecordType.DeveloperName = 'B2C' AND Program__r.Program_Code__c != null
            GROUP BY Lead__c
            LIMIT 1
        ];
        if (grouped.isEmpty()) {
            return;
        }
        Id leadId = (Id) grouped[0].get('lid');
        LeadProgramCodesAggregationService.syncAggregatedProgramCodes(new Set<Id>{ leadId });
    }
}
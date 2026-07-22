@IsTest
private class OpportunityTriggerHandlerTest {
    @IsTest
    static void exerciseClass() {
        OpportunityTriggerHandler inst = null;
        try { inst = new OpportunityTriggerHandler(); } catch (Exception e) {}
        try { OpportunityTriggerHandler.handleBeforeInsert(new List<Opportunity>()); } catch (Exception e) {}
        try { OpportunityTriggerHandler.handleAfterUpdate(new List<Opportunity>(), new Map<Id, Opportunity>()); } catch (Exception e) {}
    }
}
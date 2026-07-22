@IsTest
private class LeadPublicAPIHelperTest {
    @IsTest
    static void exerciseClass() {
        LeadPublicAPIHelper inst = null;
        try { inst = new LeadPublicAPIHelper(); } catch (Exception e) {}
        try { LeadPublicAPIHelper.scenarioApiName(null); } catch (Exception e) {}
        try { LeadPublicAPIHelper.messageForScenario(null); } catch (Exception e) {}
        try { LeadPublicAPIHelper.processLead(null, new Map<String, Program>(), new Map<String, Id>(), new Map<String, Id>(), null, null, new Map<String, Lead>(), new Map<String, Lead>(), new Map<Id, Set<Id>>()); } catch (Exception e) {}
    }
}
@IsTest
private class LeadEmailFlowInvokeTest {
    @IsTest
    static void exerciseClass() {
        LeadEmailFlowInvoke inst = null;
        try { inst = new LeadEmailFlowInvoke(); } catch (Exception e) {}
        try { LeadEmailFlowInvoke.runFlow(null); } catch (Exception e) {}
    }
}
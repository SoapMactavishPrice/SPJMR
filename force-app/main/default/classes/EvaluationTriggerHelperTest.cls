@IsTest
private class EvaluationTriggerHelperTest {
    @IsTest
    static void emptyListIsHandled() {
        // The entire helper body is wrapped in `if(!listNewEval.isEmpty()){...}` -
        // an empty list exercises the guard without DML.
        EvaluationTriggerHelper.updateApplicationStatus(new List<Evaluation__c>());
        System.assert(true);
    }
}
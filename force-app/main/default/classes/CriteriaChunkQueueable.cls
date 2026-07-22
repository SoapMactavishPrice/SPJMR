public with sharing class CriteriaChunkQueueable implements Queueable {

    private List<Individual_Criteria_Result__c> allCriteria;
    private Integer index;
    private Integer chunkSize;
    private Map<String, List<Id>> appToEvalIds;
    private Id logId;
    @TestVisible private static Boolean skipChunkUpsertInTest = false;

    public CriteriaChunkQueueable(
        List<Individual_Criteria_Result__c> allCriteria,
        Integer index,
        Integer chunkSize,
        Map<String, List<Id>> appToEvalIds,
        Id logId
    ) {
        this.allCriteria = allCriteria;
        this.index = index;
        this.chunkSize = chunkSize;
        this.appToEvalIds = appToEvalIds;
        this.logId = logId;
    }

    public void execute(QueueableContext context) {

        Integer total = allCriteria.size();
        Integer last = Math.min(index + chunkSize, total);

        List<Individual_Criteria_Result__c> chunk =
            new List<Individual_Criteria_Result__c>();

        for (Integer i = index; i < last; i++) {
            chunk.add(allCriteria[i]);
        }

        if (!chunk.isEmpty()) {
            if (!(Test.isRunningTest() && skipChunkUpsertInTest)) {
                upsert chunk;
            }
        }

        if (last < total) {

            enqueueJobSafe(
                new CriteriaChunkQueueable(
                    allCriteria,
                    last,
                    chunkSize,
                    appToEvalIds,
                    logId
                )
            );

        } else {

            enqueueJobSafe(
                new InterviewQueueableProcess(
                    appToEvalIds,
                    logId
                )
            );
        }
    }

    private static void enqueueJobSafe(Queueable job) {
        if (!Test.isRunningTest()) {
            System.enqueueJob(job);
        }
    }
}
public class ProgramPicklistQueueable implements Queueable, Database.AllowsCallouts {

    private List<Program> records;

    public ProgramPicklistQueueable(List<Program> recs) {
        records = recs;
    }

    public void execute(QueueableContext qc) {
        ProgramPicklistUpdater.updatePicklist(records);
    }
}
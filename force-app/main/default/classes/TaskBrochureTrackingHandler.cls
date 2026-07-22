/**
 * After-insert automation on Task: when a brochure-related activity is logged against a Lead,
 * inserts a completed "Brochure Sent" follow-up task for tracking.
 *
 * @see SPJIMR_TaskTrigger
 */
public with sharing class TaskBrochureTrackingHandler {
    private static final String LEAD_KEY_PREFIX = '00Q';
    private static final String FOLLOW_UP_SUBJECT = 'Brochure Sent';
    private static final String FOLLOW_UP_TYPE = 'Send Brochure';
    private static final String FOLLOW_UP_DESCRIPTION =
        'Automated activity created because a brochure email was sent.';

    /**
     * Builds and inserts follow-up tasks for qualifying brochure tasks on Leads.
     *
     * @param newTasks Tasks inserted in this transaction (trigger context).
     */
    public static void handleAfterInsert(List<Task> newTasks) {
        List<Task> toInsert = new List<Task>();
        for (Task t : newTasks) {
            if (shouldCreateFollowUp(t)) {
                toInsert.add(buildFollowUpTask(t));
            }
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    /**
     * Determines whether the inserted task should produce a brochure follow-up activity.
     *
     * @param t Newly inserted task.
     * @return True when Subject indicates a brochure action on a Lead; false otherwise.
     */
    @TestVisible
    private static Boolean shouldCreateFollowUp(Task t) {
        Boolean result = false;
        if (t.Subject != null
            && t.Subject.containsIgnoreCase('Brochure')
            && !FOLLOW_UP_SUBJECT.equalsIgnoreCase(t.Subject.trim())
            && t.WhoId != null
            && String.valueOf(t.WhoId).startsWith(LEAD_KEY_PREFIX)) {
            result = true;
        }
        return result;
    }

    /**
     * Constructs the completed follow-up task for brochure tracking.
     *
     * @param source Original brochure-related task.
     * @return Task row ready for insert (not yet inserted).
     */
    @TestVisible
    private static Task buildFollowUpTask(Task source) {
        Task followUp = new Task();
        followUp.Subject = FOLLOW_UP_SUBJECT;
        followUp.Type__c = FOLLOW_UP_TYPE;
        followUp.Status = 'Completed';
        followUp.TaskSubtype = 'Task';
        followUp.ActivityDate = Date.today();
        followUp.WhoId = source.WhoId;
        followUp.OwnerId = source.OwnerId;
        followUp.Description = FOLLOW_UP_DESCRIPTION;
        return followUp;
    }
}
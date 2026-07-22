/**
 * Syncs Opportunity.StageName from Application__c when Application_Status__c or Application_Stage__c changes.
 * Expects Opportunity.Application__c to reference the Application.
 *
 * Rules: Application Status → Initiated / Paid map to the same opportunity stage names; Application Stage
 * maps a fixed set of steps to matching opportunity stages (Program Details on Application → Programme Details on Opportunity).
 */
public with sharing class ApplicationTriggerHandler {

    private static final String STAGE_INITIATED = 'Initiated';
    private static final String STAGE_PAID = 'Paid';

    /**
     * Application_Stage__c value (label or common API value) → Opportunity StageName to set.
     */
    private static final Map<String, String> APP_STAGE_TO_OPP_STAGE = buildApplicationStageToOpportunityStageMap();

    private static Map<String, String> buildApplicationStageToOpportunityStageMap() {
        Map<String, String> m = new Map<String, String>();
        m.put('Academic Details', 'Academic Details');
        m.put('Academic_Detail__c', 'Academic Details');

        m.put('Programme Details', 'Programme Details');
        m.put('Program Details', 'Programme Details');
        m.put('Program_Detail__c', 'Programme Details');

        m.put('Basic Details', 'Basic Details');

        m.put('Entrance Exam', 'Entrance Exam');
        m.put('Competitive_Exam_Details__c', 'Entrance Exam');
        m.put('Competitive_Exam_GMAT_Focus_Edition__c', 'Entrance Exam');

        m.put('Work Experience', 'Work Experience');
        m.put('Work_Experience__c', 'Work Experience');

        m.put('Profile Information', 'Profile Information');
        m.put('Personal_Summary__c', 'Profile Information');

        m.put('Payment', 'Payment');
        return m;
    }

    /**
     * After update: push stage to related opportunities when status or application stage changes.
     *
     * @param newList Trigger.new Application rows.
     * @param oldMap Trigger.oldMap by Application Id.
     */
    public static void handleAfterUpdate(List<Application__c> newList, Map<Id, Application__c> oldMap) {
        Set<Id> applicationIds = new Set<Id>();
        for (Application__c app : newList) {
            Application__c oldApp = oldMap.get(app.Id);
            if (oldApp == null) {
                continue;
            }
            if (hasRelevantChange(app, oldApp)) {
                applicationIds.add(app.Id);
            }
        }

        if (applicationIds.isEmpty()) {
            return;
        }

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        for (Opportunity opp : [
            SELECT Id, StageName, Application__c, Stage_Initiated_Date__c
            FROM Opportunity
            WHERE Application__c IN :applicationIds
        ]) {
            Application__c app = findApplicationForOpp(newList, opp.Application__c);
            Application__c oldApp = oldMap.get(opp.Application__c);
            if (app == null || oldApp == null) {
                continue;
            }

            String newStage = resolveOpportunityStage(app, oldApp);
            if (String.isNotBlank(newStage) && opp.StageName != newStage) {
                opp.StageName = newStage;
                if (newStage == STAGE_INITIATED && opp.Stage_Initiated_Date__c == null) {
                    opp.Stage_Initiated_Date__c = System.now();
                }
                oppsToUpdate.add(opp);
            }
        }

        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;
        }
    }

    /**
     * True when Application_Status__c or Application_Stage__c changed.
     *
     * @param app New Application version.
     * @param oldApp Old Application version.
     * @return Whether opportunity sync should run for this row.
     */
    private static Boolean hasRelevantChange(Application__c app, Application__c oldApp) {
        return app.Application_Status__c != oldApp.Application_Status__c
            || app.Application_Stage__c != oldApp.Application_Stage__c;
    }

    private static Application__c findApplicationForOpp(List<Application__c> newList, Id applicationId) {
        for (Application__c a : newList) {
            if (a.Id == applicationId) {
                return a;
            }
        }
        return null;
    }

    /**
     * Status milestones first (Initiated, Paid), then Application_Stage__c mapped to opportunity stages only.
     *
     * @param app New Application version.
     * @param oldApp Old Application version.
     * @return Opportunity StageName to apply, or null to leave unchanged.
     */
    private static String resolveOpportunityStage(Application__c app, Application__c oldApp) {
        if (changedTo(app.Application_Status__c, oldApp.Application_Status__c, STAGE_INITIATED)) {
            return STAGE_INITIATED;
        }
        if (changedTo(app.Application_Status__c, oldApp.Application_Status__c, STAGE_PAID)) {
            return STAGE_PAID;
        }
        if (app.Application_Stage__c != oldApp.Application_Stage__c) {
            String mapped = mapApplicationStageToOpportunityStage(app.Application_Stage__c);
            if (String.isNotBlank(mapped)) {
                return mapped;
            }
        }
        return null;
    }

    /**
     * Resolves Application_Stage__c stored value (label or API name) to the Opportunity stage label.
     *
     * @param applicationStageRaw Current Application_Stage__c value.
     * @return Opportunity stage string, or null if not in the configured set.
     */
    private static String mapApplicationStageToOpportunityStage(String applicationStageRaw) {
        if (String.isBlank(applicationStageRaw)) {
            return null;
        }
        String key = applicationStageRaw.trim();
        if (APP_STAGE_TO_OPP_STAGE.containsKey(key)) {
            return APP_STAGE_TO_OPP_STAGE.get(key);
        }
        String lower = key.toLowerCase();
        for (String k : APP_STAGE_TO_OPP_STAGE.keySet()) {
            if (k != null && k.toLowerCase().equals(lower)) {
                return APP_STAGE_TO_OPP_STAGE.get(k);
            }
        }
        return null;
    }

    private static Boolean changedTo(String newVal, String oldVal, String target) {
        return newVal == target && oldVal != target;
    }

    /**
     * Invokes the GMP application submitted email flow when status becomes Submitted.
     *
     * @param newList Trigger.new Application rows.
     * @param oldMap Trigger.oldMap, or null on insert (not used on after update only trigger).
     */
    public static void handleGMPEmail(List<Application__c> newList, Map<Id, Application__c> oldMap) {
        for (Application__c app : newList) {
            Application__c oldApp = oldMap != null ? oldMap.get(app.Id) : null;

            Boolean statusChanged =
                oldApp == null || oldApp.Application_Status__c != app.Application_Status__c;

            if (statusChanged && app.Application_Status__c == 'Submitted') {
                Map<String, Object> flowInputs = new Map<String, Object>();
                flowInputs.put('recordId', app.Id);

                Flow.Interview.GMP_Application_Submitted_Email_Notification myFlow = new Flow.Interview.GMP_Application_Submitted_Email_Notification(
                    flowInputs
                );

                myFlow.start();
            }
        }
    }
}
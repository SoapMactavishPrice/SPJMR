public without sharing class ApplicationTriggerHandlerForLeads {
     private static final String STAGE_INITIATED = 'Initiated';
    private static final String STAGE_PAID = 'Paid';

    private static final Set<String> DECLINE_WITHDRAWAL_STATUSES = new Set<String>{ 'Withdrawn', 'Offer Not Accepted' };

    private static final Set<String> PAID_STATUSES = new Set<String>();
    private static final Set<String> INITIATED_STATUSES = new Set<String>();
    private static final Boolean STATUSES_LOADED = loadStatuses();
        
         private static Boolean loadStatuses() {
        for (Hierarchy_Programme__c hp : [SELECT All_Paid_Statuses__c, All_Initiated_Statuses__c FROM Hierarchy_Programme__c]) {
            if (String.isNotBlank(hp.All_Paid_Statuses__c)) {
                for (String status : hp.All_Paid_Statuses__c.split(',')) {
                    if (String.isNotBlank(status)) {
                        PAID_STATUSES.add(status.trim());
                    }
                }
            }
            if (String.isNotBlank(hp.All_Initiated_Statuses__c)) {
                for (String status : hp.All_Initiated_Statuses__c.split(',')) {
                    if (String.isNotBlank(status)) {
                        INITIATED_STATUSES.add(status.trim());
                    }
                }
            }
        }
        if (PAID_STATUSES.isEmpty()) {
            PAID_STATUSES.add(STAGE_PAID);
        }
        if (INITIATED_STATUSES.isEmpty()) {
            INITIATED_STATUSES.add(STAGE_INITIATED);
        }
        return true;
    }
    public static void handleAfterUpdate(){
        
        
       

    }
    
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
        ApplicationNumberController.updateApplicationNames(newList,oldMap);
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
        Boolean isInitiated = 
        app.Application_Status__c != null && INITIATED_STATUSES.contains(app.Application_Status__c)
        && oldApp.Application_Status__c != app.Application_Status__c;

        if(isInitiated ){
            return STAGE_INITIATED;
        }
        Boolean isPaid = 
        app.Application_Status__c != null && PAID_STATUSES.contains(app.Application_Status__c)
        && oldApp.Application_Status__c != app.Application_Status__c;
        if(isPaid){
            return STAGE_PAID;
        }

        // if (changedTo(app.Application_Status__c, oldApp.Application_Status__c, STAGE_INITIATED)) {
        //     return STAGE_INITIATED;
        // }
        // if (changedTo(app.Application_Status__c, oldApp.Application_Status__c, STAGE_PAID)) {
        //     return STAGE_PAID;
        // }
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

}
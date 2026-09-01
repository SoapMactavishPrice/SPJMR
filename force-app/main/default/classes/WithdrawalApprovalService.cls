/**
 * Shared server-side logic for the Withdrawal Request approval flow that now
 * runs on the standard Salesforce Approval Process
 * ('Withdrawal_Request_Approval_Process').
 *
 *  - submitForApproval(...) is called from WithdrawalRequestTrigger (after
 *    insert). It resolves the Programme Office approver(s) for each request,
 *    stamps Current_Role__c / Current_Approver_User__c / Current_Approver_Ids__c
 *    (the approval step assigns via the Current_Approver_User__c related-user
 *    field), then submits each record with Approval.process. It never throws -
 *    a routing/config gap must not roll back the student's submission; it logs
 *    to Notification_Debug__c instead, exactly like
 *    WithdrawalRequestNotificationService.
 *
 *  - getProgrammeApprovers(...) is the single place that maps a Programme +
 *    business role to Program_Team_Members__c user Ids. Role mapping:
 *      Programme Office approver -> Role__c = 'Programme Office'
 *      Chairperson approver      -> Role__c = 'Deputy Chairperson'
 *    (the same mapping the Deferment flow uses for its Chairperson level).
 *
 * WITH SYSTEM_MODE is forced on every query because portal (Experience Cloud)
 * submissions run this trigger under enforced USER_MODE somewhere in the call
 * chain.
 */
public without sharing class WithdrawalApprovalService {

    @TestVisible
    private static final String PROCESS_DEF_NAME = 'Withdrawal_Request_Approval_Process';
    private static final String PROGRAMME_OFFICE_ROLE = 'Programme Office';
    private static final String STATUS_APPLIED = 'Applied';
    private static final String LOG_PREFIX = 'WithdrawalApprovalService: ';

    /**
     * @param programmeId  Withdrawal_Request__c.Programme_Master__c (a Program Id).
     * @param role         Program_Team_Members__c.Role__c value to match.
     * @return Distinct approver User Ids, oldest membership first; empty when none.
     */
    public static List<Id> getProgrammeApprovers(Id programmeId, String role) {
        List<Id> approverIds = new List<Id>();
        if (programmeId == null || String.isBlank(role)) {
            return approverIds;
        }
        Set<Id> seen = new Set<Id>();
        for (Program_Team_Members__c member : [
            SELECT User__c
            FROM Program_Team_Members__c
            WHERE Role__c = :role
            AND User__c != null
            AND Program_Team__r.Program__c = :programmeId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
        ]) {
            if (seen.add(member.User__c)) {
                approverIds.add(member.User__c);
            }
        }
        return approverIds;
    }

    /**
     * Submits each freshly inserted 'Applied' Withdrawal Request into the
     * standard approval process, routed to the Programme Office team.
     */
    public static void submitForApproval(List<Withdrawal_Request__c> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Map<Id, List<String>> logByRequest = new Map<Id, List<String>>();
        try {
            Set<Id> requestIds = new Set<Id>();
            for (Withdrawal_Request__c r : requests) {
                if (r.Id != null) {
                    requestIds.add(r.Id);
                }
            }
            if (requestIds.isEmpty()) {
                return;
            }

            // Records already tied to an open approval instance are skipped so a
            // re-run (or a manual call) can never double-submit.
            Set<Id> alreadyInProcess = new Set<Id>();
            for (ProcessInstance pi : [
                SELECT TargetObjectId
                FROM ProcessInstance
                WHERE TargetObjectId IN :requestIds
                AND Status IN ('Pending', 'Submitted')
                WITH SYSTEM_MODE
            ]) {
                alreadyInProcess.add(pi.TargetObjectId);
            }

            Map<Id, Withdrawal_Request__c> detailed = new Map<Id, Withdrawal_Request__c>([
                SELECT Id, Status__c, Programme_Master__c, OwnerId
                FROM Withdrawal_Request__c
                WHERE Id IN :requestIds
                WITH SYSTEM_MODE
            ]);

            List<Withdrawal_Request__c> toStage = new List<Withdrawal_Request__c>();
            Map<Id, List<Id>> approversByRequest = new Map<Id, List<Id>>();

            for (Id reqId : detailed.keySet()) {
                Withdrawal_Request__c req = detailed.get(reqId);
                List<String> lines = new List<String>();
                logByRequest.put(reqId, lines);

                if (req.Status__c != STATUS_APPLIED) {
                    lines.add(LOG_PREFIX + 'SKIP submit: Status is "' + req.Status__c + '", not "' + STATUS_APPLIED + '".');
                    continue;
                }
                if (alreadyInProcess.contains(reqId)) {
                    lines.add(LOG_PREFIX + 'SKIP submit: already has an open approval instance.');
                    continue;
                }
                if (req.Programme_Master__c == null) {
                    lines.add(LOG_PREFIX + 'STOP: Programme_Master__c is blank - cannot route to a Programme Office approver.');
                    continue;
                }

                List<Id> approvers = getProgrammeApprovers(req.Programme_Master__c, PROGRAMME_OFFICE_ROLE);
                if (approvers.isEmpty()) {
                    lines.add(LOG_PREFIX + 'STOP: no Programme Office team member for Programme ' + req.Programme_Master__c
                        + ' - request not submitted for approval.');
                    continue;
                }

                approversByRequest.put(reqId, approvers);
                toStage.add(new Withdrawal_Request__c(
                    Id = reqId,
                    Current_Role__c = 'Programme Office',
                    Current_Approver_User__c = approvers[0],
                    Current_Approver_Ids__c = joinIds(approvers)
                ));
            }

            if (toStage.isEmpty()) {
                saveLogs(logByRequest);
                return;
            }

            Database.update(toStage, AccessLevel.SYSTEM_MODE);

            List<Approval.ProcessSubmitRequest> submissions = new List<Approval.ProcessSubmitRequest>();
            List<Id> submissionOrder = new List<Id>();
            for (Id reqId : approversByRequest.keySet()) {
                Approval.ProcessSubmitRequest psr = new Approval.ProcessSubmitRequest();
                psr.setObjectId(reqId);
                psr.setProcessDefinitionNameOrId(PROCESS_DEF_NAME);
                psr.setSkipEntryCriteria(false);
                psr.setSubmitterId(detailed.get(reqId).OwnerId);
                psr.setNextApproverIds(approversByRequest.get(reqId));
                psr.setComments('Auto-submitted on creation.');
                submissions.add(psr);
                submissionOrder.add(reqId);
            }

            List<Approval.ProcessResult> results = Approval.process(submissions, false);
            for (Integer i = 0; i < results.size(); i++) {
                Id reqId = submissionOrder[i];
                Approval.ProcessResult res = results[i];
                if (res.isSuccess()) {
                    logByRequest.get(reqId).add(LOG_PREFIX + 'Submitted for approval. Instance status='
                        + res.getInstanceStatus() + '.');
                } else {
                    String msg = (res.getErrors() != null && !res.getErrors().isEmpty())
                        ? res.getErrors()[0].getMessage() : 'unknown error';
                    logByRequest.get(reqId).add(LOG_PREFIX + 'Approval.process submit FAILED: ' + msg);
                }
            }
        } catch (Exception e) {
            for (List<String> lines : logByRequest.values()) {
                lines.add(LOG_PREFIX + 'UNCAUGHT EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            }
            System.debug(LoggingLevel.ERROR, LOG_PREFIX + 'submitForApproval failed: ' + e.getMessage());
        } finally {
            saveLogs(logByRequest);
        }
    }

    private static String joinIds(List<Id> ids) {
        List<String> strs = new List<String>();
        for (Id i : ids) {
            strs.add(String.valueOf(i));
        }
        return String.join(strs, ',');
    }

    /**
     * Appends the collected diagnostic lines to Notification_Debug__c so the
     * submission trace is inspectable on the record (portal debug logs are hard
     * to reach). Best-effort; never throws.
     */
    private static void saveLogs(Map<Id, List<String>> logByRequest) {
        if (logByRequest == null || logByRequest.isEmpty()) {
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (Id reqId : logByRequest.keySet()) {
            if (reqId != null && !logByRequest.get(reqId).isEmpty()) {
                ids.add(reqId);
            }
        }
        if (ids.isEmpty()) {
            return;
        }
        try {
            Map<Id, Withdrawal_Request__c> current = new Map<Id, Withdrawal_Request__c>([
                SELECT Id, Notification_Debug__c
                FROM Withdrawal_Request__c
                WHERE Id IN :ids
                WITH SYSTEM_MODE
            ]);
            List<Withdrawal_Request__c> toUpdate = new List<Withdrawal_Request__c>();
            for (Id reqId : ids) {
                Withdrawal_Request__c cur = current.get(reqId);
                String existing = (cur != null && cur.Notification_Debug__c != null) ? cur.Notification_Debug__c : '';
                String appended = existing + (String.isBlank(existing) ? '' : '\n')
                    + String.join(logByRequest.get(reqId), '\n');
                if (appended.length() > 131000) {
                    appended = appended.substring(appended.length() - 131000);
                }
                toUpdate.add(new Withdrawal_Request__c(Id = reqId, Notification_Debug__c = appended));
            }
            Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_PREFIX + 'saveLogs failed: ' + e.getMessage());
        }
    }
}
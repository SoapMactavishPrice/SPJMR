public with sharing class DefermentRequestTriggerHandler {

    // Must match the Display Name of the Org-Wide Email Address in
    // Setup > Organization-Wide Addresses. Confirm it shows as Verified.
    // Matches DefermentApprovalNotificationService — keeps all Deferment
    // Request emails coming from the same sender/domain.
    private static final String ORG_WIDE_EMAIL_DISPLAY_NAME = 'SPJIMR Deferment';

    private static final String LOG_PREFIX = 'DefermentRequestTriggerHandler: ';

    public static void sendDefermentFormEnabledEmail(
        List<Deferment_Request__c> requests
    ) {
        List<Messaging.SingleEmailMessage> emails =
            new List<Messaging.SingleEmailMessage>();

        Id templateId = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = 'Break_in_Study_Option_Enabled'
            LIMIT 1
        ].Id;

        Set<Id> accountIds = new Set<Id>();

        for (Deferment_Request__c request : requests) {
            if (
                request.Status__c == 'Deferment Form Enabled' &&
                request.Account__c != null
            ) {
                accountIds.add(request.Account__c);
            }
        }

        if (accountIds.isEmpty()) {
            return;
        }

        Map<Id, Account> studentAccounts = new Map<Id, Account>([
            SELECT Id, PersonContactId
            FROM Account
            WHERE Id IN :accountIds
        ]);

        // NEW: resolve the Org-Wide Email Address, same as
        // DefermentApprovalNotificationService, so this email doesn't
        // silently fail delivery on an unverified default sender.
        Id orgWideEmailAddressId = null;
        List<OrgWideEmailAddress> owaList = [
            SELECT Id, DisplayName, Address
            FROM OrgWideEmailAddress
            WHERE DisplayName = :ORG_WIDE_EMAIL_DISPLAY_NAME
            LIMIT 1
        ];
        if (!owaList.isEmpty()) {
            orgWideEmailAddressId = owaList[0].Id;
            System.debug(LOG_PREFIX + 'Using Org-Wide Email Address: ' + owaList[0].Address);
        } else {
            System.debug(LOG_PREFIX + 'WARN: OrgWideEmailAddress \'' + ORG_WIDE_EMAIL_DISPLAY_NAME
                + '\' not found - email will use the default sender (may silently fail).');
        }

        for (Deferment_Request__c request : requests) {

            if (request.Status__c != 'Deferment Form Enabled') {
                continue;
            }

            if (request.Account__c == null) {
                continue;
            }

            Account studentAccount = studentAccounts.get(request.Account__c);

            if (
                studentAccount == null ||
                studentAccount.PersonContactId == null
            ) {
                continue;
            }

            Messaging.SingleEmailMessage email =
                new Messaging.SingleEmailMessage();

            email.setTemplateId(templateId);

            // Student receives the email
            email.setTargetObjectId(studentAccount.PersonContactId);

            // Deferment Request is available for merge fields
            email.setWhatId(request.Id);

            email.setSaveAsActivity(false);

            // NEW: send from the verified Org-Wide Email Address
            if (orgWideEmailAddressId != null) {
                email.setOrgWideEmailAddressId(orgWideEmailAddressId);
            }

            emails.add(email);
        }

        if (!emails.isEmpty()) {
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);

            Integer sentCount = 0;
            for (Messaging.SendEmailResult r : results) {
                if (r.isSuccess()) {
                    sentCount++;
                } else {
                    for (Messaging.SendEmailError err : r.getErrors()) {
                        System.debug(LOggingLevel.ERROR, LOG_PREFIX + 'Email send FAILED: '
                            + err.getStatusCode() + ' - ' + err.getMessage());
                    }
                }
            }
            System.debug(LOG_PREFIX + 'Deferment Form Enabled emails sent: ' + sentCount + ' of ' + emails.size());
        }
    }
    public static void sendDefermentProcessCompleteEmail(
    List<Deferment_Request__c> newRequests,
    Map<Id, Deferment_Request__c> oldRequestsById
) {
    for (Deferment_Request__c request : newRequests) {

        Deferment_Request__c oldRequest = oldRequestsById != null
            ? oldRequestsById.get(request.Id)
            : null;

        // NOTE: DefermentRequestStatusTrigger (before update) silently
        // rewrites 'Deferment Process Complete' -> 'Pending Re-enrollment'
        // before this after-trigger ever sees the record, so Status__c
        // here will NEVER equal 'Deferment Process Complete' — it will
        // already be 'Pending Re-enrollment'. We detect the completion
        // event by watching for the transition INTO 'Pending Re-enrollment'
        // instead.
        Boolean justCompleted =
            request.Status__c == 'Pending Re-enrollment' &&
            (oldRequest == null || oldRequest.Status__c != 'Pending Re-enrollment');

        if (!justCompleted || request.Account__c == null) {
            continue;
        }

        DefermentApprovalNotificationService.notifyStudentOfDefermentProcessComplete(
            request.Id,
            request.Account__c
        );
    }
}
}
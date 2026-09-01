/**
 * Sends an Email + Salesforce Custom Notification to the Programme Office
 * approver(s) whenever a Withdrawal_Request__c record is submitted, whether
 * created by an internal Admin or by a student via the Student Portal.
 *
 * Called from WithdrawalRequestTrigger (After Insert). All entry points are
 * wrapped so a notification failure can never roll back the record insert.
 *
 * KEY DESIGN NOTES
 *
 * 1. System mode is forced explicitly (WITH SYSTEM_MODE / AccessLevel.SYSTEM_MODE)
 *    on every query and the diagnostic-field update. Portal (Experience
 *    Cloud) submissions run this trigger under enforced USER_MODE somewhere
 *    in the call chain, which overrides a plain "without sharing" class
 *    declaration. Without the explicit SYSTEM_MODE overrides, the query
 *    against Program_Team_Members__c and the diagnostic update throw or fail
 *    silently for portal-submitted records, even though the identical logic
 *    works fine for Admin-created records.
 *
 * 2. Recipients are resolved exactly the way the Deferment and Leave flows
 *    resolve theirs: Withdrawal_Request__c.Programme_Master__c ->
 *    Program_Team_Members__c (via Program_Team__r.Program__c) filtered to
 *    Role__c = 'Programme Office'. There is no queue and no fallback list -
 *    when a request's Programme has no Programme Office team member (or the
 *    Programme lookup is blank), that request is logged as a STOP and no
 *    notification is sent for it, matching LeaveApproverResolver /
 *    DefermentApprovalNotificationService behaviour.
 *
 * 3. Email is built manually (not via a stored EmailTemplate). Salesforce
 *    does not allow setWhatId() together with setTargetObjectId() when the
 *    target is a User - "WhatId is not available for sending emails to
 *    UserIds." Since every recipient here is a User (not a Contact/Lead),
 *    a stored template's merge fields cannot be resolved. The HTML body
 *    below is styled to match the org's "Withdrawal Request Submitted"
 *    Classic Email Template layout.
 *
 * 4. Diagnostics persist to Notification_Debug__c (Long Text Area) on the
 *    record itself, in a `finally` block so it saves regardless of where
 *    execution stops. This is intentionally kept in production: portal
 *    users' debug logs are difficult to access via Setup trace flags, so
 *    this field is the primary way to inspect what happened on a given
 *    submission without needing org admin log access.
 */
public without sharing class WithdrawalRequestNotificationService {

    private static final String CUSTOM_NOTIFICATION_NAME = 'Withdrawal_Request_Notification';
    private static final String PROGRAMME_OFFICE_ROLE = 'Programme Office';
    private static final String LOG_PREFIX = 'WithdrawalRequestNotificationService: ';

    // Must match the Display Name of the Org-Wide Email Address in
    // Setup > Organization-Wide Addresses. Confirm it shows as Verified.
    private static final String ORG_WIDE_EMAIL_DISPLAY_NAME = 'SPJIMR Withdrawal';

    public static void sendNotifications(List<Withdrawal_Request__c> withdrawalRequests) {
        List<String> diagnosticLines = new List<String>();
        try {
            sendNotificationsInternal(withdrawalRequests, diagnosticLines);
        } catch (Exception e) {
            log(diagnosticLines, 'UNCAUGHT EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
        } finally {
            saveDiagnostics(withdrawalRequests, diagnosticLines);
        }
    }

    private static void sendNotificationsInternal(List<Withdrawal_Request__c> withdrawalRequests, List<String> diagnosticLines) {

        if (withdrawalRequests == null || withdrawalRequests.isEmpty()) {
            return;
        }
        log(diagnosticLines, 'Start. withdrawalRequests.size()=' + withdrawalRequests.size());
        log(diagnosticLines, 'Running as UserId=' + UserInfo.getUserId()
            + ' ProfileId=' + UserInfo.getProfileId() + ' UserType=' + UserInfo.getUserType());

        // 1. Collect Programme Master IDs. A request with no Programme cannot
        // be routed (there is no queue fallback) and is logged in step 3.
        Set<Id> programmeMasterIds = new Set<Id>();
        for (Withdrawal_Request__c request : withdrawalRequests) {
            if (request.Programme_Master__c != null) {
                programmeMasterIds.add(request.Programme_Master__c);
            }
        }

        // 2. Programme Office approvers per Programme, resolved the same way as
        // the Deferment / Leave flows: Program_Team_Members__c joined to its
        // Programme via Program_Team__r.Program__c, filtered to the Programme
        // Office role. One bulk query, no queue, no fallback list.
        Map<Id, Set<Id>> programmeToUserIds = new Map<Id, Set<Id>>();
        if (!programmeMasterIds.isEmpty()) {
            for (Program_Team_Members__c member : [
                SELECT User__c, Program_Team__r.Program__c
                FROM Program_Team_Members__c
                WHERE Role__c = :PROGRAMME_OFFICE_ROLE
                AND User__c != null
                AND Program_Team__r.Program__c IN :programmeMasterIds
                WITH SYSTEM_MODE
                ORDER BY CreatedDate ASC
            ]) {
                Id programmeId = member.Program_Team__r.Program__c;
                if (!programmeToUserIds.containsKey(programmeId)) {
                    programmeToUserIds.put(programmeId, new Set<Id>());
                }
                programmeToUserIds.get(programmeId).add(member.User__c);
            }
        }

        // 3. Resolve recipients per request from the Programme Office team only.
        Map<Id, Set<Id>> requestToUserIds = new Map<Id, Set<Id>>();
        Set<Id> allCandidateUserIds = new Set<Id>();
        for (Withdrawal_Request__c request : withdrawalRequests) {
            Set<Id> recipients = (request.Programme_Master__c != null)
                ? programmeToUserIds.get(request.Programme_Master__c)
                : null;
            if (recipients == null || recipients.isEmpty()) {
                log(diagnosticLines, 'STOP: Request ' + request.Id
                    + ' has no Programme Office team member for Programme '
                    + request.Programme_Master__c + ' - nothing sent for this request.');
                continue;
            }
            requestToUserIds.put(request.Id, recipients);
            allCandidateUserIds.addAll(recipients);
        }

        if (allCandidateUserIds.isEmpty()) {
            log(diagnosticLines, 'STOP: no Programme Office recipients resolved for any request.');
            return;
        }

        // 4. Active users for all resolved candidates.
        Map<Id, User> usersMap = new Map<Id, User>([
            SELECT Id, Name, Email, IsActive
            FROM User
            WHERE Id IN :allCandidateUserIds
            AND IsActive = true
            WITH SYSTEM_MODE
        ]);
        if (usersMap.isEmpty()) {
            log(diagnosticLines, 'STOP: none of the candidate users are Active.');
            return;
        }

        // 5. Re-query requests for the fields the email body needs.
        Map<Id, Withdrawal_Request__c> detailedRequests = new Map<Id, Withdrawal_Request__c>([
            SELECT Id, Name, Status__c, Roll_Number__c, Application_ID__c,
                   Student__r.Name, Programme_Master__r.Name
            FROM Withdrawal_Request__c
            WHERE Id IN :withdrawalRequests
            WITH SYSTEM_MODE
        ]);

        // 6. Custom Notification Type.
        List<CustomNotificationType> notificationTypes = [
            SELECT Id, DeveloperName
            FROM CustomNotificationType
            WHERE DeveloperName = :CUSTOM_NOTIFICATION_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        CustomNotificationType notificationType = notificationTypes.isEmpty() ? null : notificationTypes[0];
        if (notificationType == null) {
            log(diagnosticLines, 'WARN: CustomNotificationType \'' + CUSTOM_NOTIFICATION_NAME + '\' not found - custom notifications skipped.');
        }

        // 7. Org-Wide Email Address to send from. Without this, Salesforce
        // falls back to a default sender tied to the running user, which can
        // silently fail delivery for portal users (unverified sending
        // domain) even though the send call still reports success.
        Id orgWideEmailAddressId = null;
        List<OrgWideEmailAddress> owaList = [
            SELECT Id, DisplayName, Address
            FROM OrgWideEmailAddress
            WHERE DisplayName = :ORG_WIDE_EMAIL_DISPLAY_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!owaList.isEmpty()) {
            orgWideEmailAddressId = owaList[0].Id;
        } else {
            log(diagnosticLines, 'WARN: OrgWideEmailAddress \'' + ORG_WIDE_EMAIL_DISPLAY_NAME + '\' not found - emails will use the default sender.');
        }

        String orgBaseUrl = URL.getOrgDomainUrl().toExternalForm();

        // 8. Build and send emails.
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Withdrawal_Request__c request : withdrawalRequests) {
            Set<Id> recipientUserIds = requestToUserIds.get(request.Id);
            if (recipientUserIds == null || recipientUserIds.isEmpty()) {
                continue;
            }

            Withdrawal_Request__c detail = detailedRequests.get(request.Id);
            String studentName = (detail != null && detail.Student__r != null) ? detail.Student__r.Name : '';
            String rollNumber = (detail != null) ? detail.Roll_Number__c : '';
            String applicationId = (detail != null) ? detail.Application_ID__c : '';
            String programmeName = (detail != null && detail.Programme_Master__r != null) ? detail.Programme_Master__r.Name : '';
            String status = (detail != null) ? detail.Status__c : '';
            String recordLink = orgBaseUrl + '/' + request.Id;

            for (Id userId : recipientUserIds) {
                User recipient = usersMap.get(userId);
                if (recipient == null || String.isBlank(recipient.Email)) {
                    continue;
                }

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(recipient.Id);
                email.setSaveAsActivity(false);
                if (orgWideEmailAddressId != null) {
                    email.setOrgWideEmailAddressId(orgWideEmailAddressId);
                }
                email.setSubject('New Withdrawal Request Submitted: ' + request.Name);
                email.setPlainTextBody(
                    'Hi ' + recipient.Name + ',\n\n' +
                    'A new withdrawal request has been submitted and is now available for review.\n\n' +
                    'Student Name: ' + studentName + '\n' +
                    'Student Roll Number: ' + rollNumber + '\n' +
                    'Student Registration: ' + applicationId + '\n' +
                    'Programme: ' + programmeName + '\n' +
                    'Status: ' + status + '\n\n' +
                    'Record link: ' + recordLink + '\n\n' +
                    'Kindly log in to the system to review the request and take the necessary action.\n' +
                    'This is an automated notification. Please do not reply to this email.'
                );
                email.setHtmlBody(
                    '<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;border:1px solid #ddd;">' +
                    '<div style="background:#4b2e83;color:#fff;padding:16px 20px;font-size:18px;font-weight:bold;">Withdrawal Request</div>' +
                    '<div style="padding:20px;">' +
                    '<p style="font-weight:bold;">Dear Program Office, a new withdrawal request has been submitted and is now available for review in the system.</p>' +
                    '<table style="width:100%;border-collapse:collapse;margin-top:12px;">' +
                    buildEmailRow('Student Name', studentName) +
                    buildEmailRow('Student Roll Number', rollNumber) +
                    buildEmailRow('Student Registration', applicationId) +
                    buildEmailRow('Programme', programmeName) +
                    buildEmailRow('Status', status) +
                    '</table>' +
                    '<p style="margin-top:16px;"><a href="' + recordLink + '">Kindly log in to the system to review the request and take the necessary action.</a></p>' +
                    '<p style="color:#c0392b;font-size:12px;">This is an automated notification. Please do not reply to this email.</p>' +
                    '</div></div>'
                );
                emails.add(email);
            }
        }

        if (!emails.isEmpty()) {
            List<Messaging.SendEmailResult> emailResults = Messaging.sendEmail(emails, false);
            Integer emailsSent = 0;
            for (Messaging.SendEmailResult r : emailResults) {
                if (r.isSuccess()) {
                    emailsSent++;
                } else {
                    for (Messaging.SendEmailError err : r.getErrors()) {
                        log(diagnosticLines, 'Email send FAILED: ' + err.getStatusCode() + ' - ' + err.getMessage());
                    }
                }
            }
            log(diagnosticLines, 'Emails sent: ' + emailsSent + ' of ' + emails.size() + ' prepared.');
        }

        // 9. Custom Notifications.
        if (notificationType != null) {
            Integer notificationsSent = 0;
            for (Withdrawal_Request__c request : withdrawalRequests) {
                Set<Id> recipientUserIds = requestToUserIds.get(request.Id);
                if (recipientUserIds == null || recipientUserIds.isEmpty()) {
                    continue;
                }
                Set<String> recipientIds = new Set<String>();
                for (Id userId : recipientUserIds) {
                    recipientIds.add(String.valueOf(userId));
                }

                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setNotificationTypeId(notificationType.Id);
                notification.setTitle('New Withdrawal Request');
                notification.setBody('Withdrawal request ' + request.Name + ' has been submitted and is awaiting review.');
                notification.setTargetId(request.Id);
                try {
                    notification.send(recipientIds);
                    notificationsSent++;
                } catch (Exception notifEx) {
                    log(diagnosticLines, 'Custom notification FAILED for ' + request.Id + ': ' + notifEx.getMessage());
                }
            }
            log(diagnosticLines, 'Custom notifications sent: ' + notificationsSent + '.');
        }

        log(diagnosticLines, 'Done.');
    }

    private static String buildEmailRow(String label, String value) {
        String safeValue = String.isBlank(value) ? '-' : value.escapeHtml4();
        return '<tr>' +
            '<td style="border:1px solid #ddd;padding:8px;font-weight:bold;background:#f5f5f5;width:40%;">' + label + '</td>' +
            '<td style="border:1px solid #ddd;padding:8px;">' + safeValue + '</td>' +
            '</tr>';
    }

    // --- Diagnostics -------------------------------------------------
    // Persisted to Notification_Debug__c so execution is inspectable
    // directly on the record, without needing debug-log access for the
    // submitting user (frequently unavailable for portal users).

    private static void log(List<String> diagnosticLines, String message) {
        diagnosticLines.add(message);
        System.debug(LOG_PREFIX + message);
    }

    private static void saveDiagnostics(List<Withdrawal_Request__c> withdrawalRequests, List<String> diagnosticLines) {
        if (withdrawalRequests == null || withdrawalRequests.isEmpty() || diagnosticLines.isEmpty()) {
            return;
        }
        String combined = String.join(diagnosticLines, '\n');
        if (combined.length() > 131000) {
            combined = combined.substring(0, 131000);
        }
        List<Withdrawal_Request__c> toUpdate = new List<Withdrawal_Request__c>();
        for (Withdrawal_Request__c req : withdrawalRequests) {
            if (req.Id != null) {
                toUpdate.add(new Withdrawal_Request__c(Id = req.Id, Notification_Debug__c = combined));
            }
        }
        if (toUpdate.isEmpty()) {
            return;
        }
        try {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult sr : saveResults) {
                if (!sr.isSuccess()) {
                    for (Database.Error err : sr.getErrors()) {
                        System.debug(LoggingLevel.ERROR, LOG_PREFIX + 'Failed to save Notification_Debug__c for '
                            + sr.getId() + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
                    }
                }
            }
        } catch (Exception saveEx) {
            System.debug(LoggingLevel.ERROR, LOG_PREFIX + 'Failed to save diagnostics: ' + saveEx.getMessage());
        }
    }
}
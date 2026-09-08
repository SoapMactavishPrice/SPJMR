@SuppressWarnings('PMD.ApexCRUDViolation,PMD.CyclomaticComplexity')
public without sharing class RejoiningReminderBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    @TestVisible
    private static final Integer REMINDER_DAYS = 30;

    @TestVisible
    private static final Integer NOTICE_MONTHS = 3;

    private static final String APPROVED_STATUS = 'Approved';

    private static final String STATUS_NOTIFIED =
        'Return to Campus Notification Sent';

    private static final String WITHDRAWN_STATUS = 'Withdrawal';

    private static final String OFFICE_ROLE = 'Programme Office';

    private static final String MANAGER_ROLE = 'Manager';

    private static final String SENDER_NAME = 'SPJIMR Programme Office';

    @TestVisible
    private static String tplStudent = 'Rejoining_Reminder_Student';

    @TestVisible
    private static String tplOffice = 'Rejoining_Reminder_Programme_Office';

    @TestVisible
    private static String tplNotice = 'Return_to_Campus_Student';

    @TestVisible
    private static String notificationTypeName = 'Rejoining_Date_Missing';

    private List<MissingDateAlert> missingDateAlerts =
        new List<MissingDateAlert>();

    private class MissingDateAlert {
        Id requestId;
        String requestName;
        Id programmeId;

        MissingDateAlert(Id requestId, String requestName, Id programmeId) {
            this.requestId = requestId;
            this.requestName = requestName;
            this.programmeId = programmeId;
        }
    }

    /**
     * The messages built by the most recent execute(), exposed so tests can
     * assert on recipients and volume without inspecting the mail server.
     */
    @TestVisible
    private static List<Messaging.SingleEmailMessage> lastOutbox;

    /**
     * Nothing is really sent in a test context, so Messaging.sendEmail reports
     * every message as unsuccessful there and the stamping path below could
     * never be exercised. Tests set this to true to stand in for a successful
     * send; production never reassigns it.
     */
    @TestVisible
    private static Boolean assumeSendSucceeded = false;

    /**
     * @description Selects requests due a 30-day reminder plus approved
     *              requests with no Rejoining Date.
     * @param ctx the batchable context
     * @return query locator over the Deferment Requests needing mail tonight
     */
    public Database.QueryLocator start(Database.BatchableContext ctx) {

        Date reminderDate = Date.today().addDays(REMINDER_DAYS);
        Date noticeDate = Date.today().addMonths(NOTICE_MONTHS);
        String approved = APPROVED_STATUS;
        String withdrawn = WITHDRAWN_STATUS;

        return Database.getQueryLocator([
            SELECT Id,
                   Name,
                   Status__c,
                   Rejoining_Date__c,
                   Programme__c,
                   Account__c,
                   Account__r.Alternate_E_mail__c,
                   Account__r.PersonContactId
            FROM Deferment_Request__c
            WHERE Programme__c != null
            AND Status__c != :withdrawn
            AND (
                    Rejoining_Date__c = :reminderDate
                    OR Rejoining_Date__c = :noticeDate
                    OR (
                        Rejoining_Date__c = null
                        AND Approval_Status__c = :approved
                    )
                )
        ]);
    }

    /**
     * @description Builds and sends the reminder mail for one batch chunk.
     * @param ctx the batchable context
     * @param scope the Deferment Requests in this chunk
     */
    public void execute(
        Database.BatchableContext ctx,
        List<Deferment_Request__c> scope
    ) {
        Map<String, Id> templateIds = templateIdsByName();
        Date noticeDate = Date.today().addMonths(NOTICE_MONTHS);
        Set<Id> programmeIds = new Set<Id>();

        for (Deferment_Request__c request : scope) {
            programmeIds.add(request.Programme__c);
        }

        Map<Id, List<String>> officeEmails = officeEmailsByProgramme(programmeIds);
        Id senderId = orgWideSenderId();

        List<Messaging.SingleEmailMessage> outbox =
            new List<Messaging.SingleEmailMessage>();

        // Outbox position of each 30-day student reminder, so only the requests
        // whose mail actually leaves are stamped.
        Map<Integer, Id> reminderByPosition = new Map<Integer, Id>();

        for (Deferment_Request__c request : scope) {

            List<String> office = officeEmails.get(request.Programme__c);

            if (request.Rejoining_Date__c == null) {
                missingDateAlerts.add(new MissingDateAlert(
                    request.Id,
                    request.Name,
                    request.Programme__c
                ));
                continue;
            }

            if (request.Rejoining_Date__c == noticeDate) {
                addMail(
                    outbox,
                    templateIds.get(tplNotice),
                    request,
                    studentAddress(request),
                    senderId
                );
                continue;
            }

            Boolean queued = addMail(
                outbox,
                templateIds.get(tplStudent),
                request,
                studentAddress(request),
                senderId
            );

            if (queued) {
                reminderByPosition.put(outbox.size() - 1, request.Id);
            }

            addMail(
                outbox,
                templateIds.get(tplOffice),
                request,
                office,
                senderId
            );
        }

        lastOutbox = outbox;

        if (outbox.isEmpty()) {
            return;
        }

        List<Messaging.SendEmailResult> results =
            Messaging.sendEmail(outbox, false);

        stampNotified(results, reminderByPosition);
    }

    /**
     * @description Marks every request whose student reminder was accepted by
     *              the mail service as 'Return to Campus Notification Sent'.
     *              Results come back one per message, in the order they were
     *              sent, so the outbox position identifies the request.
     * @param results the send results for this chunk
     * @param reminderByPosition outbox position to Deferment Request Id
     */
    private void stampNotified(
        List<Messaging.SendEmailResult> results,
        Map<Integer, Id> reminderByPosition
    ) {
        List<Deferment_Request__c> notified = new List<Deferment_Request__c>();

        for (Integer position : reminderByPosition.keySet()) {

            if (!assumeSendSucceeded && !results[position].isSuccess()) {
                continue;
            }

            notified.add(new Deferment_Request__c(
                Id = reminderByPosition.get(position),
                Status__c = STATUS_NOTIFIED
            ));
        }

        Database.update(notified, false);
    }

    public void finish(Database.BatchableContext ctx) {

        if (missingDateAlerts.isEmpty()) {
            return;
        }

        Id typeId = notificationTypeId();

        if (typeId == null) {
            return;
        }

        Set<Id> programmeIds = new Set<Id>();
        for (MissingDateAlert alert : missingDateAlerts) {
            if (alert.programmeId != null) {
                programmeIds.add(alert.programmeId);
            }
        }

        Map<Id, Set<String>> recipients =
            managerUserIdsByProgramme(programmeIds);

        for (MissingDateAlert alert : missingDateAlerts) {

            Set<String> audience = recipients.get(alert.programmeId);

            if (audience == null || audience.isEmpty()) {
                continue;
            }

            Messaging.CustomNotification bell =
                new Messaging.CustomNotification();

            bell.setNotificationTypeId(typeId);
            bell.setTitle('Rejoining Date pending');
            bell.setBody(
                'For ' + alert.requestName +
                ' the rejoining Date is pending.'
            );
            bell.setTargetId(alert.requestId);

            bell.send(audience);
        }
    }

    private Id notificationTypeId() {

        List<CustomNotificationType> types = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :notificationTypeName
            LIMIT 1
        ];

        return types.isEmpty() ? null : types[0].Id;
    }

    private Map<Id, Set<String>> managerUserIdsByProgramme(
        Set<Id> programmeIds
    ) {

        Map<Id, Set<String>> usersByProgramme = new Map<Id, Set<String>>();

        if (programmeIds == null || programmeIds.isEmpty()) {
            return usersByProgramme;
        }

        for (Program_Team_Members__c member : [
            SELECT User__c,
                   Program_Team__r.Program__c
            FROM Program_Team_Members__c
            WHERE Role__c = :MANAGER_ROLE
            AND User__c != null
            AND User__r.IsActive = true
            AND Program_Team__r.Program__c IN :programmeIds
        ]) {
            Id programmeId = member.Program_Team__r.Program__c;

            if (!usersByProgramme.containsKey(programmeId)) {
                usersByProgramme.put(programmeId, new Set<String>());
            }

            usersByProgramme.get(programmeId)
                .add(String.valueOf(member.User__c));
        }

        return usersByProgramme;
    }

    /**
     * @description Renders a stored template against one request and queues it
     *              for the given addresses. Silently skips when there is no
     *              template or nobody to send to.
     * @param outbox the list being built for this chunk
     * @param templateId the stored EmailTemplate to render
     * @param request the Deferment Request supplying merge values
     * @param addresses the recipients
     * @param senderId the org-wide sender, or null to send as the running user
     * @return true when a message was queued, false when there was nothing to send
     */
    private Boolean addMail(
        List<Messaging.SingleEmailMessage> outbox,
        Id templateId,
        Deferment_Request__c request,
        List<String> addresses,
        Id senderId
    ) {
        if (templateId == null || addresses == null || addresses.isEmpty()) {
            return false;
        }

        Messaging.SingleEmailMessage mail =
            Messaging.renderStoredEmailTemplate(
                templateId,
                request.Account__r == null
                    ? null
                    : request.Account__r.PersonContactId,
                request.Id
            );

        mail.setToAddresses(addresses);
        mail.setUseSignature(false);

        if (senderId != null) {
            mail.setOrgWideEmailAddressId(senderId);
        }

        outbox.add(mail);

        return true;
    }

    /**
     * @description The student's alternate e-mail, as a single-entry list.
     * @param request the Deferment Request
     * @return the address list, empty when no alternate e-mail is recorded
     */
    private List<String> studentAddress(Deferment_Request__c request) {

        if (
            request.Account__r == null ||
            String.isBlank(request.Account__r.Alternate_E_mail__c)
        ) {
            return new List<String>();
        }

        return new List<String>{ request.Account__r.Alternate_E_mail__c };
    }

    /**
     * @description Resolves Programme Office recipients per programme.
     * @param programmeIds the programmes in the current chunk
     * @return map of programme Id to the e-mail addresses of its Programme Office
     */
    private Map<Id, List<String>> officeEmailsByProgramme(Set<Id> programmeIds) {

        Map<Id, List<String>> emailsByProgramme = new Map<Id, List<String>>();

        for (Program_Team_Members__c member : [
            SELECT User__r.Email,
                   Program_Team__r.Program__c
            FROM Program_Team_Members__c
            WHERE Role__c = :OFFICE_ROLE
            AND User__c != null
            AND User__r.IsActive = true
            AND User__r.Email != null
            AND Program_Team__r.Program__c IN :programmeIds
        ]) {
            Id programmeId = member.Program_Team__r.Program__c;

            if (!emailsByProgramme.containsKey(programmeId)) {
                emailsByProgramme.put(programmeId, new List<String>());
            }

            emailsByProgramme.get(programmeId).add(member.User__r.Email);
        }

        return emailsByProgramme;
    }

    /**
     * @description Looks up the three stored templates in one query.
     * @return map of template DeveloperName to Id
     */
    private Map<String, Id> templateIdsByName() {

        Map<String, Id> idsByName = new Map<String, Id>();

        for (EmailTemplate template : [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN (
                :tplStudent,
                :tplOffice,
                :tplNotice
            )
        ]) {
            idsByName.put(template.DeveloperName, template.Id);
        }

        return idsByName;
    }

    /**
     * @description Finds the verified org-wide sender, if one exists.
     * @return the OrgWideEmailAddress Id, or null to send as the running user
     */
    private Id orgWideSenderId() {

        List<OrgWideEmailAddress> senders = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = :SENDER_NAME
            LIMIT 1
        ];

        return senders.isEmpty() ? null : senders[0].Id;
    }
}
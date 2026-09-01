/**
 * @description Nightly batch behind SE-1150 / SE-1177. Emails a rejoining
 *              reminder to the student and their Programme Office when a
 *              Deferment Request's Rejoining Date is exactly 30 days away, and
 *              raises one nightly bell notification per programme for approved
 *              requests that still have no Rejoining Date recorded. Requests
 *              whose Status is Withdrawal are skipped altogether.
 *
 *              A request whose student reminder actually goes out is stamped
 *              'Return to Campus Notification Sent', so the tracker shows the
 *              student has been told to plan their return.
 *
 *              Programme Office recipients are resolved from
 *              Program_Team_Members__c, the same data used for leave and
 *              deferment approver routing. Runs as the scheduled job's user
 *              against system metadata, so CRUD/FLS checks are bypassed by
 *              design.
 */
// PMD.CyclomaticComplexity is suppressed for the CLASS TOTAL only: this is the
// sum across many small helpers, and no single method exceeds a complexity of 8
// against a limit of 10. Splitting the class would scatter one night's work
// across two files without making any method simpler.
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.CyclomaticComplexity')
public without sharing class RejoiningReminderBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    /** Days ahead of the Rejoining Date that the 30-day reminder is sent. */
    @TestVisible
    private static final Integer REMINDER_DAYS = 30;

    /** Months ahead of the Rejoining Date that the Return to Campus notice is sent. */
    @TestVisible
    private static final Integer NOTICE_MONTHS = 3;

    /** Approval_Status__c value marking a fully approved deferment. */
    private static final String APPROVED_STATUS = 'Approved';

    /** Status__c stamped once the student's 30-day reminder has gone out. */
    private static final String STATUS_NOTIFIED =
        'Return to Campus Notification Sent';

    /**
     * Status__c value marking a student who has told the Programme Office they
     * are not coming back. Such requests are skipped entirely: no reminder, no
     * Return to Campus notice and no missing-date bell.
     */
    private static final String WITHDRAWN_STATUS = 'Withdrawal';

    /** Program_Team_Members__c role that receives Programme Office mail. */
    private static final String OFFICE_ROLE = 'Programme Office';

    /** Org-wide sender shown to recipients. */
    private static final String SENDER_NAME = 'SPJIMR Programme Office';

    /**
     * Stored template DeveloperNames. Not final so tests can point them at
     * templates created inside the test transaction; production never reassigns
     * them.
     */
    @TestVisible
    private static String tplStudent = 'Rejoining_Reminder_Student';

    @TestVisible
    private static String tplOffice = 'Rejoining_Reminder_Programme_Office';

    @TestVisible
    private static String tplNotice = 'Return_to_Campus_Student';

    /** Custom Notification Type behind the missing-date bell alert. */
    @TestVisible
    private static String notificationTypeName = 'Rejoining_Date_Missing';

    /**
     * Where the bell notification lands: the Deferment Request list view of
     * approved requests with no Rejoining Date.
     */
    private static final String TARGET_PAGE_REF =
        '{"type":"standard__objectPage","attributes":' +
        '{"objectApiName":"Deferment_Request__c","actionName":"list"},' +
        '"state":{"filterName":"Rejoining_Date_Missing"}}';

    /**
     * Running count of approved requests with no Rejoining Date, by programme.
     * Accumulated across chunks and raised as one bell each in finish().
     */
    private Map<Id, Integer> missingByProgramme = new Map<Id, Integer>();

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
                Integer seen = missingByProgramme.get(request.Programme__c);
                missingByProgramme.put(
                    request.Programme__c,
                    seen == null ? 1 : seen + 1
                );
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

    /**
     * @description Raises one bell notification per programme that has approved
     *              requests with no Rejoining Date, addressed to that
     *              programme's Programme Office.
     * @param ctx the batchable context
     */
    public void finish(Database.BatchableContext ctx) {

        if (missingByProgramme.isEmpty()) {
            return;
        }

        Id typeId = notificationTypeId();

        if (typeId == null) {
            return;
        }

        Map<Id, Set<String>> recipients =
            officeUserIdsByProgramme(missingByProgramme.keySet());

        Map<Id, Program> programmes = new Map<Id, Program>([
            SELECT Id, Name
            FROM Program
            WHERE Id IN :missingByProgramme.keySet()
        ]);

        for (Id programmeId : missingByProgramme.keySet()) {

            Set<String> audience = recipients.get(programmeId);

            if (audience == null || audience.isEmpty()) {
                continue;
            }

            Program programme = programmes.get(programmeId);

            Messaging.CustomNotification bell =
                new Messaging.CustomNotification();

            bell.setNotificationTypeId(typeId);
            bell.setTitle('Rejoining Date not recorded');
            bell.setBody(
                missingByProgramme.get(programmeId) +
                ' student(s) on ' +
                (programme == null ? 'this programme' : programme.Name) +
                ' have an approved Break in Study with no Rejoining Date.' +
                ' No rejoining reminders can be sent until it is entered.'
            );
            bell.setTargetPageRef(TARGET_PAGE_REF);

            bell.send(audience);
        }
    }

    /**
     * @description Looks up the Custom Notification Type behind the bell alert.
     * @return the type Id, or null when it has not been deployed
     */
    private Id notificationTypeId() {

        List<CustomNotificationType> types = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :notificationTypeName
            LIMIT 1
        ];

        return types.isEmpty() ? null : types[0].Id;
    }

    /**
     * @description Resolves Programme Office user Ids per programme.
     * @param programmeIds the programmes needing a bell
     * @return map of programme Id to the User Ids of its Programme Office
     */
    private Map<Id, Set<String>> officeUserIdsByProgramme(Set<Id> programmeIds) {

        Map<Id, Set<String>> usersByProgramme = new Map<Id, Set<String>>();

        for (Program_Team_Members__c member : [
            SELECT User__c,
                   Program_Team__r.Program__c
            FROM Program_Team_Members__c
            WHERE Role__c = :OFFICE_ROLE
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
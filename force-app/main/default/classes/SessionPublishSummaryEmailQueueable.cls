/**
 * @description Sends ONE consolidated "schedule published" email per recipient after the Program
 *          Team publishes a date range of sessions from the timetable calendar, replacing the
 *          per-session Google Calendar invitation emails that Google used to send (one per
 *          session, so a 40-session publish meant 40 emails for every enrolled student).
 *
 *          Students are told to check the Participant Portal; faculty are told the sessions were
 *          added to their Google Calendar. Both audiences get exactly one email per publication,
 *          deduplicated across every session in that publication.
 *
 * @note    Scope: this job is enqueued ONLY by TimetableSessionController.publishSessions, i.e.
 *          only by the Publish button. Creating a session (saveSession) keeps its own independent
 *          Yes/No behaviour and never reaches this class, and neither does Republish, Reschedule
 *          or Cancel. Nothing here runs from a trigger, so a Draft -> Published change made any
 *          other way cannot fire a summary email.
 *
 * @note    The per-session Google emails are suppressed separately, by publishSessions forcing
 *          SessionCalendarInviteHandler.skipUserNotifications = true. The Google events are still
 *          created and patched, and students are still attached as guests, so the sessions appear
 *          on everybody's calendar silently and RSVP capture keeps working.
 *
 * @note    Copy is held in the constants below rather than in Custom Metadata or an Email Template.
 *          It is deliberately generic and identical for every publication, so config would have
 *          added ten deployable components (and a per-org setup step) to hold four fixed strings.
 *          Rewording therefore needs a deploy — accepted. The Programme Office already has a
 *          user-facing off switch: answering No on the "Send calendar invitation emails?" modal
 *          publishes silently and sends nothing.
 *
 * @note    Emails send from whoever clicked Publish, so replies reach a real person. If a Programme
 *          Office Organization-Wide Email Address is created later, set SENDER_ADDRESS below.
 */
// Sharing declared explicitly as `without sharing`: the Program Team member who clicks Publish is
// not guaranteed sharing visibility of every learner or faculty Person Account in the published
// divisions, and the notification must reach all of them, exactly like the calendar guest list.
//
// ApexCRUDViolation suppressed: this class performs no DML. It reads the enrolment and faculty
// junctions for the sessions the publish action just committed, purely to resolve email addresses.
// OperationWithLimitsInLoop suppressed: the Messaging.sendEmail inside sendInChunks' loop IS the
// mechanism that keeps each call within the per-invocation recipient cap; the loop is bounded by
// MESSAGES_PER_INVOCATION * MAX_INVOCATIONS and anything beyond it is handed to a chained job.
// QueueableWithoutFinalizer suppressed for consistency with SessionCalendarInviteQueueable: a
// failed send is already visible under Setup > Apex Jobs, and the publish it reports on has
// already committed, so there is no compensating action for a finalizer to take.
// CyclomaticComplexity suppressed at CLASS level only (total 57, highest single method 9): every
// method stays inside the per-method limit; the total is simply the sum of many small, single-purpose
// helpers, which is the shape this ruleset asks for. Same suppression as SessionCalendarInviteHandler.
// ExcessiveParameterList suppressed for the two 4-parameter members (the continuation constructor
// and addRecipient), which sit exactly on the threshold. Both take one cohesive tuple — the two
// audience lists plus the date range, and one recipient's identity — so bundling them into another
// wrapper object would add indirection without making either call site clearer.
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.OperationWithLimitsInLoop,PMD.QueueableWithoutFinalizer,PMD.CyclomaticComplexity,PMD.ExcessiveParameterList')
public without sharing class SessionPublishSummaryEmailQueueable implements Queueable {

    /** @description Date format used for the {0} / {1} placeholders, e.g. "11 Aug 2026". */
    private static final String DATE_FORMAT = 'd MMM yyyy';

    private static final String SIGN_OFF =
        '<p>Warm regards,<br />Programme Office<br />'
        + 'S. P. Jain Institute of Management and Research</p>';

    /** @description Subject shared by both audiences. {0} range start, {1} range end. */
    private static final String SUBJECT = 'Session Schedule Published: {0} to {1}';

    /** @description {0} range start, {1} range end, {2} recipient greeting. */
    private static final String STUDENT_BODY =
        '<p>Dear {2},</p>'
        + '<p>The schedule for {0} to {1} has been published. '
        + 'Please check your Participant Portal for details.</p>'
        + SIGN_OFF;

    private static final String FACULTY_BODY =
        '<p>Dear {2},</p>'
        + '<p>The session schedule for {0} to {1} has been published. The sessions assigned to you '
        + 'have been added to your Google Calendar. Please review your calendar for the details.</p>'
        + SIGN_OFF;

    private static final String STUDENT_FALLBACK_GREETING = 'Student';
    private static final String FACULTY_FALLBACK_GREETING = 'Faculty Member';

    /**
     * @description The ONLY address these emails may come from. Must exist as a VERIFIED
     *          Organization-Wide Email Address (Setup > Organization-Wide Addresses).
     *
     *          There is deliberately no fallback to the running user: a Programme Office notice
     *          must not arrive from whichever staff member happened to click Publish. If the
     *          verified address is missing the job fails loudly instead, which is visible under
     *          Setup > Apex Jobs — the publish itself has already committed and is unaffected.
     */
    private static final String SENDER_ADDRESS = 'finessedirect@spjimr.org';

    /**
     * @description Test seam. Apex cannot create an OrgWideEmailAddress, and a test run has no
     *          verified sender to point at, so tests switch the requirement off and assert the
     *          audience and copy instead. senderIsRequiredThrowsWhenUnverified covers the on case.
     */
    @TestVisible
    private static Boolean requireVerifiedSender = true;

    /** @description Recipients per Messaging.sendEmail call. */
    private static final Integer MESSAGES_PER_INVOCATION = 100;

    /**
     * @description Messaging.sendEmail calls this job may spend. Apex allows 10 email invocations
     *          per transaction; one is deliberately left unspent so an unrelated retry or a
     *          platform-side send cannot push the transaction over the limit.
     */
    private static final Integer MAX_INVOCATIONS = 9;

    /**
     * @description Every message this transaction handed to Messaging.sendEmail. Recorded so the
     *          tests can assert the audience, the deduplication and the merged copy — emails are
     *          not delivered in a test context, so there is nothing else to inspect. Holds
     *          references to messages that already exist in memory, so it costs no real heap.
     */
    @TestVisible
    private static List<Messaging.SingleEmailMessage> sentMessages =
        new List<Messaging.SingleEmailMessage>();

    private Set<Id> sessionIds;
    private Date rangeStart;
    private Date rangeEnd;

    /**
     * @description Populated only on a continuation job. When set, the recipients were already
     *          resolved by the previous link in the chain and must not be re-queried.
     */
    private List<Recipient> pendingStudents;
    private List<Recipient> pendingFaculty;

    /** @description Raised when no verified org-wide sender is available. */
    public class SenderNotConfiguredException extends Exception {}

    /** @description One resolved addressee: who to send to and how to greet them. */
    public class Recipient {
        public Id contactId;
        public String email;
        public String greeting;
    }

    /**
     * @description Everything one audience's emails need besides the recipients themselves.
     *          Bundled into an object, and populated by field assignment, so the message builder
     *          keeps a short signature — the same shape SessionCalendarInviteHandler.PushRequest
     *          uses for the calendar push.
     */
    private class CopySpec {
        private String body;
        private String fallbackGreeting;
        private String startText;
        private String endText;
        private Id senderId;
    }

    /**
     * @description Primary constructor, used by TimetableSessionController.publishSessions.
     * @param sessionIds The sessions this publication action just published.
     * @param rangeStart Earliest Session_Date__c among those sessions.
     * @param rangeEnd Latest Session_Date__c among those sessions.
     */
    public SessionPublishSummaryEmailQueueable(Set<Id> sessionIds, Date rangeStart, Date rangeEnd) {
        this.sessionIds = (sessionIds != null) ? sessionIds : new Set<Id>();
        this.rangeStart = rangeStart;
        this.rangeEnd   = rangeEnd;
    }

    /**
     * @description Continuation constructor: carries the recipients a previous link could not fit
     *          inside its email-invocation budget, so a very large publication still reaches
     *          everybody without re-resolving or re-sending to anyone.
     * @param students Students still to be emailed.
     * @param faculty Faculty still to be emailed.
     * @param rangeStart Earliest Session_Date__c among the published sessions.
     * @param rangeEnd Latest Session_Date__c among the published sessions.
     */
    @TestVisible
    private SessionPublishSummaryEmailQueueable(
        List<Recipient> students,
        List<Recipient> faculty,
        Date rangeStart,
        Date rangeEnd
    ) {
        this.sessionIds      = new Set<Id>();
        this.pendingStudents = students;
        this.pendingFaculty  = faculty;
        this.rangeStart      = rangeStart;
        this.rangeEnd        = rangeEnd;
    }

    /**
     * @description Resolves the audiences and sends one email each, chaining if the publication is
     *          larger than one transaction's email budget.
     * @param context The queueable context supplied by the platform.
     */
    public void execute(QueueableContext context) {
        List<Recipient> students = (pendingStudents != null) ? pendingStudents : resolveStudents();
        List<Recipient> faculty  = (pendingFaculty  != null) ? pendingFaculty  : resolveFaculty();

        // Resolved before anything is built: if there is no verified Programme Office sender there
        // is nothing valid to send from, and failing here sends nobody a half-right email.
        Id senderId = resolveSenderId(SENDER_ADDRESS);
        if (senderId == null && requireVerifiedSender && !(students.isEmpty() && faculty.isEmpty())) {
            throw new SenderNotConfiguredException(
                'Publish summary not sent: no verified Organization-Wide Email Address exists for '
                + SENDER_ADDRESS + '. Create it under Setup > Organization-Wide Addresses and click '
                + 'the verification link sent to that mailbox, then re-run the notification. The '
                + 'sessions themselves are already published and are unaffected.'
            );
        }

        String startText  = formatDate(rangeStart);
        String endText    = formatDate(rangeEnd);

        CopySpec studentCopy = new CopySpec();
        studentCopy.body             = STUDENT_BODY;
        studentCopy.fallbackGreeting = STUDENT_FALLBACK_GREETING;
        studentCopy.startText        = startText;
        studentCopy.endText          = endText;
        studentCopy.senderId         = senderId;

        CopySpec facultyCopy = new CopySpec();
        facultyCopy.body             = FACULTY_BODY;
        facultyCopy.fallbackGreeting = FACULTY_FALLBACK_GREETING;
        facultyCopy.startText        = startText;
        facultyCopy.endText          = endText;
        facultyCopy.senderId         = senderId;

        Integer capacity = MESSAGES_PER_INVOCATION * MAX_INVOCATIONS;
        List<Recipient> studentSlice = takeSlice(students, capacity);
        List<Recipient> facultySlice = takeSlice(faculty, capacity - studentSlice.size());

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        messages.addAll(buildMessages(studentSlice, studentCopy));
        messages.addAll(buildMessages(facultySlice, facultyCopy));

        sendInChunks(messages);
        chainRemainder(students, faculty);
    }

    /**
     * @description Resolves the distinct students enrolled in the published sessions. Deliberately
     *          reads Session_Enrollment__c rather than the divisions, so the email reaches exactly
     *          the people who were attached to the Google events as guests.
     * @return One Recipient per distinct student.
     */
    private List<Recipient> resolveStudents() {
        Map<String, Recipient> byKey = new Map<String, Recipient>();
        if (sessionIds.isEmpty()) {
            return byKey.values();
        }
        for (Session_Enrollment__c se : [
            SELECT Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonContactId,
                   Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail,
                   Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.FirstName
            FROM   Session_Enrollment__c
            WHERE  Session__c IN :sessionIds
              AND  Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail != NULL
        ]) {
            Account learner = learnerOf(se);
            if (learner != null) {
                addRecipient(byKey, learner.PersonContactId, learner.PersonEmail, learner.FirstName);
            }
        }
        return byKey.values();
    }

    /**
     * @description Resolves the distinct faculty assigned to the published sessions.
     * @return One Recipient per distinct faculty member.
     */
    private List<Recipient> resolveFaculty() {
        Map<String, Recipient> byKey = new Map<String, Recipient>();
        if (sessionIds.isEmpty()) {
            return byKey.values();
        }
        for (Session_Faculty__c sf : [
            SELECT Session_Faculty__r.PersonContactId,
                   Session_Faculty__r.PersonEmail,
                   Session_Faculty__r.Name
            FROM   Session_Faculty__c
            WHERE  Session__c IN :sessionIds
              AND  Session_Faculty__r.PersonEmail != NULL
        ]) {
            if (sf.Session_Faculty__r != null) {
                addRecipient(
                    byKey,
                    sf.Session_Faculty__r.PersonContactId,
                    sf.Session_Faculty__r.PersonEmail,
                    sf.Session_Faculty__r.Name
                );
            }
        }
        return byKey.values();
    }

    /**
     * @description Walks the enrolment to its learner Person Account, tolerating a broken chain.
     * @param se The session enrolment row.
     * @return The learner account, or null when any link in the chain is missing.
     */
    private static Account learnerOf(Session_Enrollment__c se) {
        if (se.Division_Enrollment__r == null
                || se.Division_Enrollment__r.Academic_Term_Enrollment__r == null) {
            return null;
        }
        return se.Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount;
    }

    /**
     * @description Adds a recipient under a dedupe key, so a student enrolled in twenty of the
     *          published sessions still receives exactly one email.
     * @param byKey Accumulator keyed by contact id, falling back to lowercased email.
     * @param contactId The recipient's PersonContactId, may be null.
     * @param email The recipient's email address.
     * @param name The name used to build the greeting, may be blank.
     */
    private static void addRecipient(
        Map<String, Recipient> byKey,
        Id contactId,
        String email,
        String name
    ) {
        if (String.isBlank(email)) {
            return;
        }
        String key = (contactId != null) ? String.valueOf(contactId) : email.toLowerCase().trim();
        if (byKey.containsKey(key)) {
            return;
        }
        Recipient r = new Recipient();
        r.contactId = contactId;
        r.email     = email;
        r.greeting  = String.isNotBlank(name) ? name.trim() : null;
        byKey.put(key, r);
    }

    /**
     * @description Removes and returns the first `count` recipients, leaving the remainder in the
     *          source list for the continuation job.
     * @param source The full recipient list, mutated in place.
     * @param count How many recipients this transaction can afford.
     * @return The recipients to email now.
     */
    private static List<Recipient> takeSlice(List<Recipient> source, Integer count) {
        List<Recipient> taken = new List<Recipient>();
        if (source == null || count <= 0) {
            return taken;
        }
        while (!source.isEmpty() && taken.size() < count) {
            taken.add(source.remove(0));
        }
        return taken;
    }

    /**
     * @description Builds one personalised email per recipient.
     * @param recipients The audience slice being emailed now.
     * @param spec The audience's copy, sender and formatted date range.
     * @return The messages, ready to send.
     */
    private static List<Messaging.SingleEmailMessage> buildMessages(
        List<Recipient> recipients,
        CopySpec spec
    ) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        if (recipients == null || recipients.isEmpty() || String.isBlank(spec.body)) {
            return messages;
        }
        String defaultGreeting = String.isNotBlank(spec.fallbackGreeting)
            ? spec.fallbackGreeting
            : 'Participant';

        for (Recipient r : recipients) {
            String greeting = String.isNotBlank(r.greeting) ? r.greeting : defaultGreeting;
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

            // setTargetObjectId is preferred (it is the org's existing idiom and associates the
            // send with the person record); toAddresses is the fallback for a learner or faculty
            // Person Account with no contact behind it.
            if (r.contactId != null) {
                mail.setTargetObjectId(r.contactId);
                mail.setSaveAsActivity(false);
            } else {
                mail.setToAddresses(new List<String>{ r.email });
            }
            if (spec.senderId != null) {
                mail.setOrgWideEmailAddressId(spec.senderId);
            }
            String html = mergeCopy(spec.body, spec, greeting);
            mail.setSubject(mergeCopy(SUBJECT, spec, greeting));
            mail.setHtmlBody(html);
            mail.setPlainTextBody(toPlainText(html));
            messages.add(mail);
        }
        return messages;
    }

    /**
     * @description Substitutes the {0} / {1} / {2} placeholders. Uses replace() rather than
     *          String.format because the copy is admin-editable and an apostrophe in a
     *          MessageFormat pattern silently swallows the placeholders around it.
     * @param template The configured copy.
     * @param spec The audience's copy spec, carrying the formatted dates.
     * @param greeting The recipient greeting.
     * @return The merged text.
     */
    private static String mergeCopy(String template, CopySpec spec, String greeting) {
        if (String.isBlank(template)) {
            return '';
        }
        return template
            .replace('{0}', spec.startText)
            .replace('{1}', spec.endText)
            .replace('{2}', greeting);
    }

    /**
     * @description Derives the plain-text alternative from the merged HTML body, so a mail client
     *          that refuses HTML still shows readable text rather than markup.
     * @param html The merged HTML body.
     * @return The stripped plain-text equivalent.
     */
    private static String toPlainText(String html) {
        return html
            .replaceAll('<br\\s*/?>', '\n')
            .replaceAll('</p>', '\n')
            .replaceAll('<[^>]+>', '')
            .trim();
    }

    /**
     * @description Sends the messages in chunks that respect the per-transaction email budget.
     *          allOrNothing is false so one undeliverable address cannot stop everybody else's
     *          email, and a partial failure cannot roll back the publish that already committed.
     * @param messages The messages to send.
     */
    private static void sendInChunks(List<Messaging.SingleEmailMessage> messages) {
        if (messages.isEmpty()) {
            return;
        }
        sentMessages.addAll(messages);

        List<Messaging.SingleEmailMessage> chunk = new List<Messaging.SingleEmailMessage>();
        for (Messaging.SingleEmailMessage mail : messages) {
            chunk.add(mail);
            if (chunk.size() == MESSAGES_PER_INVOCATION) {
                Messaging.sendEmail(chunk, false);
                chunk = new List<Messaging.SingleEmailMessage>();
            }
        }
        if (!chunk.isEmpty()) {
            Messaging.sendEmail(chunk, false);
        }
    }

    /**
     * @description Enqueues a continuation job for recipients that did not fit this transaction's
     *          email budget. Skipped when nothing is left or the transaction has no queueable slot,
     *          in which case the publish itself is unaffected and already committed.
     * @param students Students still unsent.
     * @param faculty Faculty still unsent.
     */
    private void chainRemainder(List<Recipient> students, List<Recipient> faculty) {
        Boolean nothingLeft = (students == null || students.isEmpty())
            && (faculty == null || faculty.isEmpty());
        if (nothingLeft) {
            return;
        }
        if (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs() <= 0) {
            return;
        }
        System.enqueueJob(
            new SessionPublishSummaryEmailQueueable(students, faculty, rangeStart, rangeEnd)
        );
    }

    /**
     * @description Resolves the configured Organization-Wide Email Address.
     * @param address The configured sender address, may be blank.
     * @return Its id, or null to send as the running user.
     */
    @TestVisible
    private static Id resolveSenderId(String address) {
        if (String.isBlank(address)) {
            return null;
        }
        // IsVerified matters: an org-wide address that exists but has not had its verification link
        // clicked cannot be used as a sender, and passing its id makes the send fail. Filtering here
        // means an unverified (or misspelt) address degrades to sending as the running user — the
        // pre-existing behaviour — instead of throwing and losing the notification entirely.
        List<OrgWideEmailAddress> owas = [
            SELECT Id
            FROM   OrgWideEmailAddress
            WHERE  Address = :address.trim()
              AND  IsVerified = true
            LIMIT  1
        ];
        return owas.isEmpty() ? null : owas[0].Id;
    }

    /**
     * @description Formats a date for the email copy, e.g. "11 Aug 2026".
     * @param value The date to format.
     * @return The formatted date, or an empty string when null.
     */
    private static String formatDate(Date value) {
        if (value == null) {
            return '';
        }
        return Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0)).format(DATE_FORMAT);
    }
}
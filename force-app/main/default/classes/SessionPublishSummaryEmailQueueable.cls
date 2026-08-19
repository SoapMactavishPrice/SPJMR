@SuppressWarnings('PMD.ApexCRUDViolation,PMD.OperationWithLimitsInLoop,PMD.QueueableWithoutFinalizer,PMD.CyclomaticComplexity,PMD.ExcessiveParameterList')
public without sharing class SessionPublishSummaryEmailQueueable implements Queueable {

    private static final String DATE_FORMAT = 'd MMM yyyy';

    private static final String SIGN_OFF =
        '<p>Warm regards,<br />Programme Office<br />'
        + 'S. P. Jain Institute of Management and Research</p>';

    private static final String SUBJECT = 'Session Schedule Published: {0} to {1}';

    private static final String STUDENT_BODY =
        '<p>Dear {2},</p>'
        + '<p>The schedule for {0} to {1} has been published. '
        + 'Please check your Participant Portal for details.</p>'
        + SIGN_OFF;

    // Republish copy. A republish is a single session, so both dates collapse onto {0} and {1} is
    // left out of the wording rather than reading "20 Aug 2026 to 20 Aug 2026".
    private static final String SUBJECT_REPUBLISH = 'Session Schedule Republished: {0}';

    private static final String STUDENT_BODY_REPUBLISH =
        '<p>Dear {2},</p>'
        + '<p>The schedule for {0} has been Republished. '
        + 'Please check your Participant Portal for the latest details.</p>'
        + SIGN_OFF;

    private static final String FACULTY_BODY =
        '<p>Dear {2},</p>'
        + '<p>The session schedule for {0} to {1} has been published. The sessions assigned to you '
        + 'have been added to your Google Calendar. Please review your calendar for the details.</p>'
        + SIGN_OFF;

    private static final String STUDENT_FALLBACK_GREETING = 'Student';
    private static final String FACULTY_FALLBACK_GREETING = 'Faculty Member';

    @TestVisible
    private static Boolean requireVerifiedSender = true;

    @TestVisible
    private static List<OrgWideEmailAddress> senderOverride;

    private static final Integer MESSAGES_PER_INVOCATION = 100;

    private static final Integer MAX_INVOCATIONS = 9;

    @TestVisible
    private static List<Messaging.SingleEmailMessage> sentMessages =
        new List<Messaging.SingleEmailMessage>();

    private Set<Id> sessionIds;
    private Date rangeStart;
    private Date rangeEnd;
    private Boolean studentsOnly;
    private Boolean isRepublish;

    private List<Recipient> pendingStudents;
    private List<Recipient> pendingFaculty;

    public class SenderNotConfiguredException extends Exception {}

    public class Recipient {
        public Id contactId;
        public String email;
        public String greeting;
    }

    private class CopySpec {
        private String subject;
        private String body;
        private String fallbackGreeting;
        private String startText;
        private String endText;
        private Id senderId;
    }

    public SessionPublishSummaryEmailQueueable(Set<Id> sessionIds, Date rangeStart, Date rangeEnd) {
        this(sessionIds, rangeStart, rangeEnd, false);
    }

    public SessionPublishSummaryEmailQueueable(
        Set<Id> sessionIds,
        Date rangeStart,
        Date rangeEnd,
        Boolean studentsOnly
    ) {
        this(sessionIds, rangeStart, rangeEnd, studentsOnly, false);
    }

    /**
     * @description Builds the summary job.
     * @param sessionIds The sessions whose students/faculty are to be emailed.
     * @param rangeStart Earliest session date quoted in the copy.
     * @param rangeEnd Latest session date quoted in the copy.
     * @param studentsOnly True to skip the faculty entirely (they are told by Google instead).
     * @param isRepublish True for the Republish path, which swaps in the "schedule updated" copy.
     */
    public SessionPublishSummaryEmailQueueable(
        Set<Id> sessionIds,
        Date rangeStart,
        Date rangeEnd,
        Boolean studentsOnly,
        Boolean isRepublish
    ) {
        this.sessionIds   = (sessionIds != null) ? sessionIds : new Set<Id>();
        this.rangeStart   = rangeStart;
        this.rangeEnd     = rangeEnd;
        this.studentsOnly = (studentsOnly == true);
        this.isRepublish  = (isRepublish == true);
    }

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
        this.studentsOnly    = false;
        this.isRepublish     = false;
    }

    public void execute(QueueableContext context) {
        List<Recipient> students = (pendingStudents != null) ? pendingStudents : resolveStudents();
        List<Recipient> faculty;
        if (studentsOnly == true) {
            faculty = new List<Recipient>();
        } else {
            faculty = (pendingFaculty != null) ? pendingFaculty : resolveFaculty();
        }

        Id senderId = resolveSenderId();
        if (senderId == null && requireVerifiedSender && !(students.isEmpty() && faculty.isEmpty())) {
            throw new SenderNotConfiguredException(
                'Publish summary not sent: this org has no verified Organization-Wide Email Address '
                + 'to send from. Create one under Setup > Organization-Wide Addresses and click the '
                + 'verification link sent to that mailbox, then re-run the notification. The '
                + 'sessions themselves are already published and are unaffected.'
            );
        }

        String startText  = formatDate(rangeStart);
        String endText    = formatDate(rangeEnd);

        String studentBody = (isRepublish == true) ? STUDENT_BODY_REPUBLISH : STUDENT_BODY;
        CopySpec studentCopy = buildCopy(
            studentBody, STUDENT_FALLBACK_GREETING, startText, endText, senderId
        );
        CopySpec facultyCopy = buildCopy(
            FACULTY_BODY, FACULTY_FALLBACK_GREETING, startText, endText, senderId
        );

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
     * @description Assembles one audience's copy, picking the publish or the republish subject.
     * @param body The body template for this audience.
     * @param fallbackGreeting Greeting used when the recipient has no first name on file.
     * @param startText Formatted earliest session date.
     * @param endText Formatted latest session date.
     * @param senderId Org-wide email address to send from, or null when none is configured.
     * @return The assembled copy for this audience.
     */
    private CopySpec buildCopy(
        String body,
        String fallbackGreeting,
        String startText,
        String endText,
        Id senderId
    ) {
        CopySpec spec = new CopySpec();
        spec.subject          = (isRepublish == true) ? SUBJECT_REPUBLISH : SUBJECT;
        spec.body             = body;
        spec.fallbackGreeting = fallbackGreeting;
        spec.startText        = startText;
        spec.endText          = endText;
        spec.senderId         = senderId;
        return spec;
    }

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

    private static Account learnerOf(Session_Enrollment__c se) {
        if (se.Division_Enrollment__r == null
                || se.Division_Enrollment__r.Academic_Term_Enrollment__r == null) {
            return null;
        }
        return se.Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount;
    }

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
            mail.setSubject(mergeCopy(spec.subject, spec, greeting));
            mail.setHtmlBody(html);
            mail.setPlainTextBody(toPlainText(html));
            messages.add(mail);
        }
        return messages;
    }

    private static String mergeCopy(String template, CopySpec spec, String greeting) {
        if (String.isBlank(template)) {
            return '';
        }
        return template
            .replace('{0}', spec.startText)
            .replace('{1}', spec.endText)
            .replace('{2}', greeting);
    }

    private static String toPlainText(String html) {
        return html
            .replaceAll('<br\\s*/?>', '\n')
            .replaceAll('</p>', '\n')
            .replaceAll('<[^>]+>', '')
            .trim();
    }

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

    private void chainRemainder(List<Recipient> students, List<Recipient> faculty) {
        Boolean nothingLeft = (students == null || students.isEmpty())
            && (faculty == null || faculty.isEmpty());
        if (nothingLeft) {
            return;
        }
        if (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs() <= 0) {
            return;
        }
        // Carry the copy variant across the chain, or a >900-recipient republish would flip back
        // to the publish wording halfway through.
        SessionPublishSummaryEmailQueueable next =
            new SessionPublishSummaryEmailQueueable(students, faculty, rangeStart, rangeEnd);
        next.isRepublish = isRepublish;
        System.enqueueJob(next);
    }

    @TestVisible
    private static Id resolveSenderId() {
        List<OrgWideEmailAddress> owas = (senderOverride != null)
            ? senderOverride
            : [
                SELECT Id
                FROM   OrgWideEmailAddress
                WHERE  IsVerified = true
                ORDER BY Address
                LIMIT  1
            ];
        return owas.isEmpty() ? null : owas[0].Id;
    }

    private static String formatDate(Date value) {
        if (value == null) {
            return '';
        }
        return Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0)).format(DATE_FORMAT);
    }
}
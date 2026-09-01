/**
 * Sends an Email + Salesforce Custom Notification to the approver(s) of a
 * Deferment_Request__c record whenever it's submitted or resubmitted for
 * approval, whether the caller is a Programme Manager (internal) or a
 * student via the Student Portal.
 *
 * Called from DefermentRequestController.submitDefermentRequest() right after
 * a submission/resubmission is successfully routed for approval.
 *
 * KEY DESIGN NOTES
 *
 * 1. WITH SYSTEM_MODE is forced explicitly on every query. Portal
 *    (Experience Cloud) submissions run this under enforced sharing/FLS
 *    somewhere in the call chain, which can silently block queries or
 *    email sends for portal-submitted records even though identical logic
 *    works fine when run as an internal user.
 *
 * 2. Email uses setTargetObjectId() + an Org-Wide Email Address, not
 *    setToAddresses(). The default sender tied to a portal running user
 *    can silently fail delivery (unverified sending domain) even though
 *    Messaging.sendEmail() still reports isSuccess() = true.
 *
 * 3. Never throws back to the caller - a notification failure must never
 *    block or roll back the actual approval submission.
 */
public without sharing class DefermentApprovalNotificationService {

    private static final String CUSTOM_NOTIFICATION_TYPE_DEV_NAME = 'Deferment_Approval_Notification';
    private static final String LOG_PREFIX = 'DefermentApprovalNotificationService: ';
	private static final String STUDENT_REJECTION_NOTIFICATION_TYPE_DEV_NAME =
    'Deferment_Student_Rejection';

    // Must match the Display Name of the Org-Wide Email Address in
    // Setup > Organization-Wide Addresses. Confirm it shows as Verified.
    private static final String ORG_WIDE_EMAIL_DISPLAY_NAME = 'SPJIMR Deferment';

    public static void notifyApprovers(
        Id recordId,
        List<Id> approverIds,
        String roleLabel
    ) {
        try {
            notifyApproversInternal(recordId, approverIds, roleLabel);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_PREFIX + 'UNCAUGHT EXCEPTION: '
                + e.getMessage() + ' | ' + e.getStackTraceString());
        }
    }


    // =====================================================================
// MANAGER NOTIFICATION AFTER L2 APPROVAL
//
// Fires when Associate Dean / Dean approves the Deferment Request.
// Sends Email + Salesforce Custom Notification to Manager(s).
// =====================================================================

public static void notifyProgrammeManagersAfterL2Approval(
    Id recordId,
    List<Id> managerIds
) {
    try {

        notifyProgrammeManagersAfterL2ApprovalInternal(
            recordId,
            managerIds
        );

    } catch (Exception e) {

        System.debug(
            LoggingLevel.ERROR,
            LOG_PREFIX +
            'UNCAUGHT EXCEPTION (Manager Notification): ' +
            e.getMessage() +
            ' | ' +
            e.getStackTraceString()
        );
    }
}

    private static void notifyApproversInternal(
        Id recordId,
        List<Id> approverIds,
        String roleLabel
    ) {
        System.debug(LOG_PREFIX + 'Start. recordId=' + recordId + ' approverIds=' + approverIds + ' role=' + roleLabel);
        System.debug(LOG_PREFIX + 'Running as UserId=' + UserInfo.getUserId()
            + ' ProfileId=' + UserInfo.getProfileId() + ' UserType=' + UserInfo.getUserType());

        if (recordId == null || approverIds == null || approverIds.isEmpty()) {
            System.debug(LOG_PREFIX + 'STOP: recordId or approverIds is null/empty.');
            return;
        }

        // 1. Active approver Users.
        Map<Id, User> usersMap = new Map<Id, User>([
            SELECT Id, Name, Email, IsActive
            FROM User
            WHERE Id IN :approverIds
            AND IsActive = true
            WITH SYSTEM_MODE
        ]);

        if (usersMap.isEmpty()) {
            System.debug(LOG_PREFIX + 'STOP: none of the approverIds resolved to an Active User.');
            return;
        }
        System.debug(LOG_PREFIX + 'Active approver Users found: ' + usersMap.size());

        // 2. Merge data for the email/notification body.
        MergeData data = getMergeData(recordId);

        // 3. Org-Wide Email Address.
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
            System.debug(LOG_PREFIX + 'Using Org-Wide Email Address: ' + owaList[0].Address);
        } else {
            System.debug(LOG_PREFIX + 'WARN: OrgWideEmailAddress \'' + ORG_WIDE_EMAIL_DISPLAY_NAME
                + '\' not found - emails will use the default sender (may silently fail for portal-submitted records).');
        }

        sendApprovalEmails(usersMap.values(), roleLabel, data, orgWideEmailAddressId);
        sendCustomNotifications(usersMap.values(), roleLabel, data, recordId);

        System.debug(LOG_PREFIX + 'Done.');
    }

    public class MergeData {
        public String studentName = 'A student';
        public String studentRollNumber = '';
        public String programmeName = '';
        public String referenceNumber = '';
        public String status = 'Awaiting Approval'; // NEW: default fallback if Status__c is blank
    }

    private static MergeData getMergeData(Id recordId) {
        MergeData data = new MergeData();

        List<Deferment_Request__c> requests = [
            SELECT Id,
                   Name,
                   Programme__r.Name,
                   Account__r.Name,
                   Status__c,
                   Program_Cohort_Member__r.Roll_Number__c
            FROM Deferment_Request__c
            WHERE Id = :recordId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (requests.isEmpty()) {
            System.debug(LOG_PREFIX + 'WARN: Deferment_Request__c ' + recordId + ' not found for merge data.');
            return data;
        }

        Deferment_Request__c req = requests[0];
        data.referenceNumber = req.Name;

        if (req.Programme__r != null && !String.isBlank(req.Programme__r.Name)) {
            data.programmeName = req.Programme__r.Name;
        }
        if (req.Account__r != null && !String.isBlank(req.Account__r.Name)) {
            data.studentName = req.Account__r.Name;
        }
        if (req.Program_Cohort_Member__r != null &&
            !String.isBlank(req.Program_Cohort_Member__r.Roll_Number__c)) {
            data.studentRollNumber = req.Program_Cohort_Member__r.Roll_Number__c;
        }
        
        if (!String.isBlank(req.Status__c)) {
            data.status = req.Status__c; // NEW: use actual current status instead of hardcoded text
        }

        return data;
    }

    private static String getSalutation(String roleLabel) {
        return (roleLabel == 'Chairperson')
            ? 'Programme Chairperson'
            : 'Associate Dean / Dean';
    }

        private static void sendApprovalEmails(
        List<User> approverUsers,
        String roleLabel,
        MergeData data,
        Id orgWideEmailAddressId
    ) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        String subject = 'Deferment Application Awaiting Approval – ' + data.studentName;
        String htmlBody = buildHtmlBody(roleLabel, data);

        for (User approver : approverUsers) {
            if (String.isBlank(approver.Email)) {
                System.debug(LOG_PREFIX + 'SKIP email for ' + approver.Id + ': no Email on User record.');
                continue;
            }

            String plainBody =
                'Dear ' + getSalutation(roleLabel) + ',\n'+
                'A new deferment application has been submitted by the following student ' +
                'and is awaiting your review and approval.\n\n' +
                'Student Name: ' + data.studentName + '\n' +
                'Student ID: ' + data.studentRollNumber + '\n' +
                'Programme: ' + data.programmeName + '\n' +
                'Application Reference Number: ' + data.referenceNumber + '\n' +
                'Application Status:'+ data.status +'\n\n' +
                'Kindly review the application in the ERP system and take the appropriate action.\n\n' +
                'This is an automated notification. Please do not reply to this email.';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(approver.Id);
            mail.setSaveAsActivity(false);
            if (orgWideEmailAddressId != null) {
                mail.setOrgWideEmailAddressId(orgWideEmailAddressId);
            }
            mail.setSubject(subject);
            mail.setPlainTextBody(plainBody);
            mail.setHtmlBody(htmlBody);
            emails.add(mail);
        }

        if (emails.isEmpty()) {
            System.debug(LOG_PREFIX + 'No emails prepared (no approvers with a valid Email).');
            return;
        }

        List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
        Integer sentCount = 0;
        for (Messaging.SendEmailResult r : results) {
            if (r.isSuccess()) {
                sentCount++;
            } else {
                for (Messaging.SendEmailError err : r.getErrors()) {
                    System.debug(LOG_PREFIX + 'Email send FAILED: ' + err.getStatusCode() + ' - ' + err.getMessage());
                }
            }
        }
        System.debug(LOG_PREFIX + 'Emails sent: ' + sentCount + ' of ' + emails.size() + ' prepared.');
    }

    // Builds the styled HTML body entirely in Apex - matches the reference
    // "Withdrawal Request" layout (purple header, logo, bordered table),
    // with real values substituted directly (no stored Email Template,
    // since merge-field templates can't resolve for User recipients).
    private static String buildHtmlBody(String roleLabel, MergeData data) {

        String logoUrl = 'https://platform-energy-10.file.force.com/sfc/dist/version/download/?oid=00DdN00000UKZDF&ids=068OS00000HhGpW&d=%2Fa%2FOS000004pTP4%2FHGj69FkH73m3IykmWhrnPeOUC1sVTbBGMN1KV9Z0RHI&asPdf=false';

        return
            '<html><body style="font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 20px;">' +
            '<table width="600" align="center" style="background-color: #ffffff; border: 1px solid #dddddd;">' +

            '<tr><td align="center" style="background-color: #4B2E83; padding: 20px;">' +
            '<h2 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: bold;">Deferment Request</h2>' +
            '</td></tr>' +

            '<tr><td align="center" style="padding: 25px; background-color: #ffffff;">' +
            '<img src="' + logoUrl + '" width="150" height="60" alt="SPJIMR Logo"/>' +
            '</td></tr>' +

            '<tr><td align="left" style="padding: 0px 30px 20px 30px;">' +
            '<p style="font-size: 16px; font-weight: bold; color: #333333; margin: 0;">' +
            'Dear ' + getSalutation(roleLabel).escapeHtml4() + ',<br/>' +
            'A new deferment application has been submitted by the following student and is awaiting your review and approval.' +
            '</p></td></tr>' +

            '<tr><td style="padding: 0px 30px 30px 30px;">' +
            '<table width="100%" style="border-collapse: collapse;">' +
            buildEmailRow('Student Name', data.studentName) +
            buildEmailRow('Student Roll Number', data.studentRollNumber) +
            buildEmailRow('Programme', data.programmeName) +
            buildEmailRow('Application Reference Number', data.referenceNumber) +
            buildEmailRow('Status', data.status) +
            '</table>' +
            '</td></tr>' +

            '<tr><td style="padding: 0px 30px 30px 30px; font-size: 13px; color: #333333;">' +
            '<p style="margin: 0 0 10px 0;">Kindly log in to the system to review the request and take the necessary action.</p>' +
            '<p style="margin: 0; color: #666666; font-size: 12px;">This is an automated notification. Please do not reply to this email.</p>' +
            '</td></tr>' +

            '</table>' +
            '</body></html>';
    }

    private static String buildEmailRow(String label, String value) {
        String safeValue = String.isBlank(value) ? '-' : value.escapeHtml4();
        return '<tr>' +
            '<td style="padding: 12px; border: 1px solid #dddddd; font-weight: bold; width: 40%;">' +
            label.escapeHtml4() + '</td>' +
            '<td style="padding: 12px; border: 1px solid #dddddd;">' + safeValue + '</td>' +
            '</tr>';
    }
    private static void sendCustomNotifications(
        List<User> approverUsers,
        String roleLabel,
        MergeData data,
        Id recordId
    ) {
        List<CustomNotificationType> types = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :CUSTOM_NOTIFICATION_TYPE_DEV_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (types.isEmpty()) {
            System.debug(LOG_PREFIX + 'WARN: CustomNotificationType \'' + CUSTOM_NOTIFICATION_TYPE_DEV_NAME + '\' not found - custom notifications skipped.');
            return;
        }

        Set<String> recipientIds = new Set<String>();
        for (User approver : approverUsers) {
            recipientIds.add(approver.Id);
        }

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setTitle('Deferment Application Awaiting Approval');
        notification.setBody(
            data.studentName + ' (' + data.referenceNumber + ') needs your ' +
            getSalutation(roleLabel) + ' approval.'
        );
        notification.setNotificationTypeId(types[0].Id);
        notification.setTargetId(recordId);

        try {
            notification.send(recipientIds);
            System.debug(LOG_PREFIX + 'Custom notification sent to ' + recipientIds.size() + ' recipient(s).');
        } catch (Exception notifEx) {
            System.debug(LOG_PREFIX + 'Custom notification FAILED: ' + notifEx.getMessage());
        }
    }
    
    // =====================================================================
// STUDENT REJECTION NOTIFICATION - fires when either level1 rejects
// =====================================================================

public static void notifyStudentOfRejection(
    Id recordId,
    Id accountId,
    String rejectedByRoleLabel,
    String comments
) {
    try {
        notifyStudentOfRejectionInternal(recordId, accountId, rejectedByRoleLabel, comments);
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + 'UNCAUGHT EXCEPTION (Student Reject Notify): '
            + e.getMessage() + ' | ' + e.getStackTraceString());
    }
}

private static void notifyStudentOfRejectionInternal(
    Id recordId,
    Id accountId,
    String rejectedByRoleLabel,
    String comments
) {
    System.debug(LOG_PREFIX + 'Student reject notify Start. recordId=' + recordId + ' accountId=' + accountId);

    if (recordId == null || accountId == null) {
        System.debug(LOG_PREFIX + 'Student reject notify STOP: recordId or accountId is null.');
        return;
    }

    Set<Id> contactIds = new Set<Id>();
for (Contact c : [
    SELECT Id
    FROM Contact
    WHERE AccountId = :accountId
    WITH SYSTEM_MODE
]) {
    contactIds.add(c.Id);
}

List<User> studentUsers = [
    SELECT Id, Name, Email, IsActive
    FROM User
    WHERE IsActive = true
    AND (
        AccountId = :accountId
        OR ContactId IN :contactIds
    )
    WITH SYSTEM_MODE
];

    if (studentUsers.isEmpty()) {
    System.debug(
        LOG_PREFIX +
        'Student reject notify STOP: no active Portal User found for accountId=' +
        accountId
    );
    return;
}
    MergeData data = getMergeData(recordId);

    Id orgWideEmailAddressId = null;
    List<OrgWideEmailAddress> owaList = [
        SELECT Id FROM OrgWideEmailAddress
        WHERE DisplayName = :ORG_WIDE_EMAIL_DISPLAY_NAME
        WITH SYSTEM_MODE
        LIMIT 1
    ];
    if (!owaList.isEmpty()) {
        orgWideEmailAddressId = owaList[0].Id;
    }

    String rejectedByLabel = getSalutation(rejectedByRoleLabel);
    if (!studentUsers.isEmpty()){
        sendStudentRejectionEmail(studentUsers, data, rejectedByLabel, comments, orgWideEmailAddressId);}
    else {
    System.debug(
        LOG_PREFIX +
        'No active Portal User found - rejection email skipped.'
    );
}
 //   sendStudentRejectionCustomNotification(studentUsers, data, rejectedByLabel, recordId);
 createStudentPortalRejectionNotification(
    accountId,
    data,
    rejectedByLabel,
    comments,
    recordId
);

    System.debug(LOG_PREFIX + 'Student reject notify Done.');
}

// =====================================================================
// STUDENT FINAL APPROVAL NOTIFICATION - fires when L2 (Associate Dean/Dean)
// gives final approval on the Deferment Request.
// =====================================================================

public static void notifyStudentOfFinalApproval(
    Id recordId,
    Id accountId
) {
    try {
        notifyStudentOfFinalApprovalInternal(recordId, accountId);
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + 'UNCAUGHT EXCEPTION (Student Final Approval Notify): '
            + e.getMessage() + ' | ' + e.getStackTraceString());
    }
}

private static void notifyStudentOfFinalApprovalInternal(
    Id recordId,
    Id accountId
) {
    System.debug(LOG_PREFIX + 'Student final approval notify Start. recordId=' + recordId + ' accountId=' + accountId);

    if (recordId == null || accountId == null) {
        System.debug(LOG_PREFIX + 'Student final approval notify STOP: recordId or accountId is null.');
        return;
    }

    Set<Id> contactIds = new Set<Id>();
    for (Contact c : [
        SELECT Id
        FROM Contact
        WHERE AccountId = :accountId
        WITH SYSTEM_MODE
    ]) {
        contactIds.add(c.Id);
    }

    List<User> studentUsers = [
        SELECT Id, Name, Email, IsActive
        FROM User
        WHERE IsActive = true
        AND (
            AccountId = :accountId
            OR ContactId IN :contactIds
        )
        WITH SYSTEM_MODE
    ];

    if (studentUsers.isEmpty()) {
        System.debug(LOG_PREFIX + 'Student final approval notify STOP: no active Portal User found for accountId=' + accountId);
        return;
    }

    MergeData data = getMergeData(recordId);

    Id orgWideEmailAddressId = null;
    List<OrgWideEmailAddress> owaList = [
        SELECT Id FROM OrgWideEmailAddress
        WHERE DisplayName = :ORG_WIDE_EMAIL_DISPLAY_NAME
        WITH SYSTEM_MODE
        LIMIT 1
    ];
    if (!owaList.isEmpty()) {
        orgWideEmailAddressId = owaList[0].Id;
    }

    sendStudentFinalApprovalEmail(studentUsers, data, orgWideEmailAddressId);

    System.debug(LOG_PREFIX + 'Student final approval notify Done.');
}

@TestVisible
private static void sendStudentFinalApprovalEmail(
    List<User> studentUsers,
    MergeData data,
    Id orgWideEmailAddressId
) {
    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

    String subject = 'Break in Study Request Approved – ' + data.referenceNumber;
    String htmlBody = buildStudentFinalApprovalHtmlBody(data);

    for (User student : studentUsers) {
        if (String.isBlank(student.Email)) {
            System.debug(LOG_PREFIX + 'SKIP student final approval email for ' + student.Id + ': no Email on User record.');
            continue;
        }

        String plainBody =
            'Dear ' + data.studentName + ',\n' +
            'Your Break in Study request has received final approval.\n\n' +
            'Request Reference Number: ' + data.referenceNumber + '\n' +
            'Programme: ' + data.programmeName + '\n' +
            'Request Status: Approved\n\n' +
            'Please contact the Programme Team for further processing and guidance on the next steps related to your Break in Study.\n\n' +
            'This is an automated notification. Please do not reply to this email.';

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(student.Id);
        mail.setSaveAsActivity(false);
        if (orgWideEmailAddressId != null) {
            mail.setOrgWideEmailAddressId(orgWideEmailAddressId);
        }
        mail.setSubject(subject);
        mail.setPlainTextBody(plainBody);
        mail.setHtmlBody(htmlBody);
        emails.add(mail);
    }

    if (emails.isEmpty()) {
        System.debug(LOG_PREFIX + 'No student final approval emails prepared (no valid Email on student User).');
        return;
    }

    List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
    Integer sentCount = 0;
    for (Messaging.SendEmailResult r : results) {
        if (r.isSuccess()) {
            sentCount++;
        } else {
            for (Messaging.SendEmailError err : r.getErrors()) {
                System.debug(LOG_PREFIX + 'Student final approval email send FAILED: ' + err.getStatusCode() + ' - ' + err.getMessage());
            }
        }
    }
    System.debug(LOG_PREFIX + 'Student final approval emails sent: ' + sentCount + ' of ' + emails.size() + ' prepared.');
}

private static String buildStudentFinalApprovalHtmlBody(
    MergeData data
) {
    String logoUrl = 'https://platform-energy-10.file.force.com/sfc/dist/version/download/?oid=00DdN00000UKZDF&ids=068OS00000HhGpW&d=%2Fa%2FOS000004pTP4%2FHGj69FkH73m3IykmWhrnPeOUC1sVTbBGMN1KV9Z0RHI&asPdf=false';

    return
        '<html><body style="font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 20px;">' +
        '<table width="600" align="center" style="background-color: #ffffff; border: 1px solid #dddddd;">' +

        '<tr><td align="center" style="background-color: #4B2E83; padding: 20px;">' +
        '<h2 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: bold;">Break in Study Request Approved</h2>' +
        '</td></tr>' +

        '<tr><td align="center" style="padding: 25px; background-color: #ffffff;">' +
        '<img src="' + logoUrl + '" width="150" height="60" alt="SPJIMR Logo"/>' +
        '</td></tr>' +

        '<tr><td align="left" style="padding: 0px 30px 20px 30px;">' +
        '<p style="font-size: 16px; font-weight: bold; color: #333333; margin: 0;">' +
        'Dear ' + data.studentName.escapeHtml4() + ',<br/>your Break in Study request has received final approval.' +
        '</p></td></tr>' +

        '<tr><td style="padding: 0px 30px 30px 30px;">' +
        '<table width="100%" style="border-collapse: collapse;">' +
        buildEmailRow('Request Reference Number', data.referenceNumber) +
        buildEmailRow('Programme', data.programmeName) +
        buildEmailRow('Request Status', 'Approved') +
        '</table>' +
        '</td></tr>' +

        '<tr><td style="padding: 0px 30px 30px 30px; font-size: 13px; color: #333333;">' +
        '<p style="margin: 0 0 10px 0;">Please contact the Programme Team for further processing and guidance on the next steps related to your Break in Study.</p>' +
        '<p style="margin: 0; color: #666666; font-size: 12px;">This is an automated notification. Please do not reply to this email.</p>' +
        '</td></tr>' +

        '</table>' +
        '</body></html>';
}

@TestVisible
private static void sendStudentRejectionEmail(
    List<User> studentUsers,
    MergeData data,
    String rejectedByLabel,
    String comments,
    Id orgWideEmailAddressId
) {
    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

    String subject = 'Deferment Application Rejected – ' + data.referenceNumber;
    String safeComments = String.isBlank(comments) ? '-' : comments;
    String htmlBody = buildStudentRejectionHtmlBody(data, rejectedByLabel, safeComments);

    for (User student : studentUsers) {
        if (String.isBlank(student.Email)) {
            System.debug(LOG_PREFIX + 'SKIP student rejection email for ' + student.Id + ': no Email on User record.');
            continue;
        }

        String plainBody =
            'Dear ' + data.studentName + ',\n' +
            'Your deferment application has been reviewed and has not been approved.\n\n' +
            'Application Reference Number: ' + data.referenceNumber + '\n' +
            'Programme: ' + data.programmeName + '\n' +
            'Application Status: Rejected\n' +
            'Remarks: ' + safeComments + '\n\n' +
            'The application is available for resubmission, subject to the applicable policy and submission window.\n' +
            'Please review the remarks provided above before resubmitting your application, if applicable.\n\n' +
            'This is an automated notification. Please do not reply to this email.';

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(student.Id);
        mail.setSaveAsActivity(false);
        if (orgWideEmailAddressId != null) {
            mail.setOrgWideEmailAddressId(orgWideEmailAddressId);
        }
        mail.setSubject(subject);
        mail.setPlainTextBody(plainBody);
        mail.setHtmlBody(htmlBody);
        emails.add(mail);
    }

    if (emails.isEmpty()) {
        System.debug(LOG_PREFIX + 'No student rejection emails prepared (no valid Email on student User).');
        return;
    }

    List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
    Integer sentCount = 0;
    for (Messaging.SendEmailResult r : results) {
        if (r.isSuccess()) {
            sentCount++;
        } else {
            for (Messaging.SendEmailError err : r.getErrors()) {
                System.debug(LOG_PREFIX + 'Student rejection email send FAILED: ' + err.getStatusCode() + ' - ' + err.getMessage());
            }
        }
    }
    System.debug(LOG_PREFIX + 'Student rejection emails sent: ' + sentCount + ' of ' + emails.size() + ' prepared.');
}

private static String buildStudentRejectionHtmlBody(
    MergeData data,
    String rejectedByLabel,
    String safeComments
) {
    String logoUrl = 'https://platform-energy-10.file.force.com/sfc/dist/version/download/?oid=00DdN00000UKZDF&ids=068OS00000HhGpW&d=%2Fa%2FOS000004pTP4%2FHGj69FkH73m3IykmWhrnPeOUC1sVTbBGMN1KV9Z0RHI&asPdf=false';

    return
        '<html><body style="font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 20px;">' +
        '<table width="600" align="center" style="background-color: #ffffff; border: 1px solid #dddddd;">' +

        '<tr><td align="center" style="background-color: #4B2E83; padding: 20px;">' +
        '<h2 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: bold;">Deferment Request Rejected</h2>' +
        '</td></tr>' +

        '<tr><td align="center" style="padding: 25px; background-color: #ffffff;">' +
        '<img src="' + logoUrl + '" width="150" height="60" alt="SPJIMR Logo"/>' +
        '</td></tr>' +

        '<tr><td align="left" style="padding: 0px 30px 20px 30px;">' +
        '<p style="font-size: 16px; font-weight: bold; color: #333333; margin: 0;">' +
        'Dear ' + data.studentName.escapeHtml4() + ',<br/>your deferment application has been reviewed and has not been approved.' +
        '</p></td></tr>' +

        '<tr><td style="padding: 0px 30px 30px 30px;">' +
        '<table width="100%" style="border-collapse: collapse;">' +
        buildEmailRow('Application Reference Number', data.referenceNumber) +
        buildEmailRow('Programme', data.programmeName) +
        buildEmailRow('Application Status', 'Rejected') +
        buildEmailRow('Remarks', safeComments) +
        '</table>' +
        '</td></tr>' +

        '<tr><td style="padding: 0px 30px 30px 30px; font-size: 13px; color: #333333;">' +
        '<p style="margin: 0 0 10px 0;">The application is available for resubmission, subject to the applicable policy and submission window.</p>' +
        '<p style="margin: 0 0 10px 0;">Please review the remarks provided above before resubmitting your application, if applicable.</p>' +
        '<p style="margin: 0; color: #666666; font-size: 12px;">This is an automated notification. Please do not reply to this email.</p>' +
        '</td></tr>' +

        '</table>' +
        '</body></html>';
}

@TestVisible
private static void createStudentPortalRejectionNotification(
    Id accountId,
    MergeData data,
    String rejectedByLabel,
    String comments,
    Id recordId
) {
    System.debug(
        LoggingLevel.ERROR,
        '=== STUDENT PORTAL REJECTION NOTIFICATION START ==='
    );

    try {
        if (accountId == null) {
            System.debug(
                LoggingLevel.ERROR,
                'STOP: accountId is null'
            );
            return;
        }

        if (recordId == null) {
            System.debug(
                LoggingLevel.ERROR,
                'STOP: recordId is null'
            );
            return;
        }

        String safeComments =
            String.isBlank(comments) ? '-' : comments;

        Portal_Notification__c portalNotification =
            new Portal_Notification__c();

        portalNotification.Title__c =
            'Deferment Application Rejected';

        portalNotification.Body__c =
            'Your deferment application (' +
            data.referenceNumber +
            ') was rejected.Please review the rejection remarks: ' +
            safeComments;

        portalNotification.Recipient_Account__c =
            accountId;

        portalNotification.Is_Read__c =
            false;

        Database.insert(
            portalNotification,
            AccessLevel.SYSTEM_MODE
        );

        System.debug(
            LoggingLevel.ERROR,
            'SUCCESS: Student portal rejection notification created. ' +
            'Notification Id=' + portalNotification.Id +
            ' | AccountId=' + accountId
        );

    } catch (Exception e) {
        System.debug(
            LoggingLevel.ERROR,
            'FAILED: Student portal rejection notification'
        );

        System.debug(
            LoggingLevel.ERROR,
            'Exception Type = ' +
            e.getTypeName()
        );

        System.debug(
            LoggingLevel.ERROR,
            'Exception Message = ' +
            e.getMessage()
        );

        System.debug(
            LoggingLevel.ERROR,
            'Stack Trace = ' +
            e.getStackTraceString()
        );
    }

    System.debug(
        LoggingLevel.ERROR,
        '=== STUDENT PORTAL REJECTION NOTIFICATION END ==='
    );
}
private static void notifyProgrammeManagersAfterL2ApprovalInternal(
    Id recordId,
    List<Id> managerIds
) {

    System.debug(
        LOG_PREFIX +
        'Manager notification START. ' +
        'RecordId=' + recordId +
        ' ManagerIds=' + managerIds
    );

    if (
        recordId == null ||
        managerIds == null ||
        managerIds.isEmpty()
    ) {

        System.debug(
            LOG_PREFIX +
            'STOP: recordId or managerIds is null/empty.'
        );

        return;
    }


    // -------------------------------------------------------------
    // 1. Get active Manager users
    // -------------------------------------------------------------

    Map<Id, User> usersMap = new Map<Id, User>([
        SELECT Id,
               Name,
               Email,
               IsActive
        FROM User
        WHERE Id IN :managerIds
        AND IsActive = true
        WITH SYSTEM_MODE
    ]);

    if (usersMap.isEmpty()) {

        System.debug(
            LOG_PREFIX +
            'STOP: No active Manager users found.'
        );

        return;
    }


    // -------------------------------------------------------------
    // 2. Get request data
    // -------------------------------------------------------------

    MergeData data = getMergeData(recordId);


    // -------------------------------------------------------------
    // 3. Get Org Wide Email Address
    // -------------------------------------------------------------

    Id orgWideEmailAddressId = null;

    List<OrgWideEmailAddress> owaList = [
        SELECT Id,
               DisplayName,
               Address
        FROM OrgWideEmailAddress
        WHERE DisplayName = :ORG_WIDE_EMAIL_DISPLAY_NAME
        WITH SYSTEM_MODE
        LIMIT 1
    ];

    if (!owaList.isEmpty()) {

        orgWideEmailAddressId = owaList[0].Id;

        System.debug(
            LOG_PREFIX +
            'Using Org-Wide Email Address: ' +
            owaList[0].Address
        );
    }


    // -------------------------------------------------------------
    // 4. Send Email
    // -------------------------------------------------------------

    sendManagerL2ApprovalEmails(
        usersMap.values(),
        data,
        orgWideEmailAddressId
    );


    // -------------------------------------------------------------
    // 5. Send Custom Notification
    // -------------------------------------------------------------

    sendManagerL2ApprovalCustomNotifications(
        usersMap.values(),
        data,
        recordId
    );


    System.debug(
        LOG_PREFIX +
        'Manager notification DONE.'
    );
}

private static void sendManagerL2ApprovalCustomNotifications(
    List<User> managerUsers,
    MergeData data,
    Id recordId
) {
    List<CustomNotificationType> types = [
        SELECT Id
        FROM CustomNotificationType
        WHERE DeveloperName = :CUSTOM_NOTIFICATION_TYPE_DEV_NAME
        WITH SYSTEM_MODE
        LIMIT 1
    ];

    if (types.isEmpty()) {
        System.debug(
            LOG_PREFIX +
            'WARN: CustomNotificationType not found - Manager custom notifications skipped.'
        );
        return;
    }

    Set<String> recipientIds = new Set<String>();

    for (User manager : managerUsers) {
        if (manager != null && manager.IsActive) {
            recipientIds.add(String.valueOf(manager.Id));
        }
    }

    if (recipientIds.isEmpty()) {
        System.debug(
            LOG_PREFIX +
            'No active Manager recipients found for custom notification.'
        );
        return;
    }

    Messaging.CustomNotification notification =
        new Messaging.CustomNotification();

    notification.setTitle(
        'Deferment Application Approved'
    );

    notification.setBody(
        data.studentName +
        ' (' +
        data.referenceNumber +
        ') has been approved by the Associate Dean / Dean. ' +
        'Please update the Rejoining Details.'
    );

    notification.setNotificationTypeId(
        types[0].Id
    );

    notification.setTargetId(
        recordId
    );

    try {
        notification.send(recipientIds);

        System.debug(
            LOG_PREFIX +
            'Manager custom notification sent to ' +
            recipientIds.size() +
            ' recipient(s).'
        );

    } catch (Exception e) {

        System.debug(
            LoggingLevel.ERROR,
            LOG_PREFIX +
            'Manager custom notification FAILED: ' +
            e.getMessage() +
            ' | ' +
            e.getStackTraceString()
        );
    }
}
private static void sendManagerL2ApprovalEmails(
    List<User> managerUsers,
    MergeData data,
    Id orgWideEmailAddressId
) {

    List<Messaging.SingleEmailMessage> emails =
        new List<Messaging.SingleEmailMessage>();

    String subject =
        'Deferment Application Fully Approved – ' +
        data.studentName;

    String htmlBody =
        buildManagerL2ApprovalHtmlBody(data);


    for (User manager : managerUsers) {

        if (String.isBlank(manager.Email)) {

            System.debug(
                LOG_PREFIX +
                'SKIP Manager email for ' +
                manager.Id +
                ': no Email.'
            );

            continue;
        }


        String plainBody =
    'Dear Programme Manager,\n' +

    'The deferment application for the following student has received ' +
    'approval from both required approval levels and is now fully approved.\n\n' +

    'Student Name: ' +
    data.studentName + '\n' +

    'Student ID: ' +
    data.studentRollNumber + '\n' +

    'Programme: ' +
    data.programmeName + '\n' +

    'Application Reference Number: ' +
    data.referenceNumber + '\n' +

    'Application Status: Fully Approved\n\n' +

    'The deferment request may now be processed further as per the applicable programme process.\n\n' +

    'This is an automated notification. Please do not reply to this email.';


        Messaging.SingleEmailMessage mail =
            new Messaging.SingleEmailMessage();

        mail.setTargetObjectId(manager.Id);

        mail.setSaveAsActivity(false);

        if (orgWideEmailAddressId != null) {
            mail.setOrgWideEmailAddressId(
                orgWideEmailAddressId
            );
        }

        mail.setSubject(subject);

        mail.setPlainTextBody(plainBody);

        mail.setHtmlBody(htmlBody);

        emails.add(mail);
    }


    if (emails.isEmpty()) {

        System.debug(
            LOG_PREFIX +
            'No Manager emails prepared.'
        );

        return;
    }


    List<Messaging.SendEmailResult> results =
        Messaging.sendEmail(
            emails,
            false
        );


    Integer sentCount = 0;

    for (Messaging.SendEmailResult result : results) {

        if (result.isSuccess()) {

            sentCount++;

        } else {

            for (Messaging.SendEmailError error :
                result.getErrors()) {

                System.debug(
                    LOG_PREFIX +
                    'Manager email FAILED: ' +
                    error.getStatusCode() +
                    ' - ' +
                    error.getMessage()
                );
            }
        }
    }


    System.debug(
        LOG_PREFIX +
        'Manager emails sent: ' +
        sentCount +
        ' of ' +
        emails.size()
    );
}
private static String buildManagerL2ApprovalHtmlBody(
    MergeData data
) {

    String logoUrl =
        'https://platform-energy-10.file.force.com/sfc/dist/version/download/?oid=00DdN00000UKZDF&ids=068OS00000HhGpW&d=%2Fa%2FOS000004pTP4%2FHGj69FkH73m3IykmWhrnPeOUC1sVTbBGMN1KV9Z0RHI&asPdf=false';


    return
        '<html>' +
        '<body style="font-family: Arial, sans-serif; ' +
        'background-color: #f4f4f4; padding: 20px;">' +

        '<table width="600" align="center" ' +
        'style="background-color: #ffffff; ' +
        'border: 1px solid #dddddd;">' +


        '<tr>' +
        '<td align="center" ' +
        'style="background-color: #4B2E83; padding: 20px;">' +

        '<h2 style="color: #ffffff; margin: 0; ' +
        'font-size: 24px; font-weight: bold;">' +

        'Deferment Request Fully Approved' +

        '</h2>' +

        '</td>' +
        '</tr>' +


        '<tr>' +
        '<td align="center" ' +
        'style="padding: 25px; background-color: #ffffff;">' +

        '<img src="' +
        logoUrl +
        '" width="150" height="60" alt="SPJIMR Logo"/>' +

        '</td>' +
        '</tr>' +


        '<tr>' +
        '<td align="left" ' +
        'style="padding: 0px 30px 20px 30px;">' +

        '<p style="font-size: 16px; font-weight: bold; ' +
        'color: #333333; margin: 0;">' +

        'Dear Programme Manager,<br/>the deferment application for the ' +
        'following student has received approval from both required ' +
        'approval levels and is now fully approved.' +

        '</p>' +

        '</td>' +
        '</tr>' +


        '<tr>' +
        '<td style="padding: 0px 30px 30px 30px;">' +

        '<table width="100%" style="border-collapse: collapse;">' +

        buildEmailRow(
            'Student Name',
            data.studentName
        ) +

        buildEmailRow(
            'Student Roll Number',
            data.studentRollNumber
        ) +

        buildEmailRow(
            'Programme',
            data.programmeName
        ) +

        buildEmailRow(
            'Application Reference Number',
            data.referenceNumber
        ) +

        buildEmailRow(
            'Status',
            'Fully Approved'
        ) +

        '</table>' +

        '</td>' +
        '</tr>' +


        '<tr>' +
        '<td style="padding: 0px 30px 30px 30px; ' +
        'font-size: 13px; color: #333333;">' +

        '<p style="margin: 0 0 10px 0;">' +

        'The deferment request may now be processed further as per ' +
        'the applicable programme process.' +

        '</p>' +

        '<p style="margin: 0; color: #666666; font-size: 12px;">' +

        'This is an automated notification. Please do not reply to this email.' +

        '</p>' +

        '</td>' +
        '</tr>' +


        '</table>' +

        '</body>' +
        '</html>';
}
    // =====================================================================
// STUDENT DEFERMENT PROCESS COMPLETE NOTIFICATION - fires when the
// Programme Manager marks the Deferment Request as
// Status__c = 'Deferment Process Complete'.
// =====================================================================

public static void notifyStudentOfDefermentProcessComplete(
    Id recordId,
    Id accountId
) {
    try {
        notifyStudentOfDefermentProcessCompleteInternal(recordId, accountId);
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + 'UNCAUGHT EXCEPTION (Deferment Process Complete Notify): '
            + e.getMessage() + ' | ' + e.getStackTraceString());
    }
}

private static void notifyStudentOfDefermentProcessCompleteInternal(
    Id recordId,
    Id accountId
) {
    System.debug(LOG_PREFIX + 'Deferment process complete notify Start. recordId=' + recordId + ' accountId=' + accountId);

    if (recordId == null || accountId == null) {
        System.debug(LOG_PREFIX + 'Deferment process complete notify STOP: recordId or accountId is null.');
        return;
    }

    Set<Id> contactIds = new Set<Id>();
    for (Contact c : [
        SELECT Id
        FROM Contact
        WHERE AccountId = :accountId
        WITH SYSTEM_MODE
    ]) {
        contactIds.add(c.Id);
    }

    List<User> studentUsers = [
        SELECT Id, Name, Email, IsActive
        FROM User
        WHERE IsActive = true
        AND (
            AccountId = :accountId
            OR ContactId IN :contactIds
        )
        WITH SYSTEM_MODE
    ];

  /*  if (studentUsers.isEmpty()) {
        System.debug(LOG_PREFIX + 'Deferment process complete notify STOP: no active Portal User found for accountId=' + accountId);
        return;
    }*/

    MergeData data = getMergeData(recordId);

    Id orgWideEmailAddressId = null;
    List<OrgWideEmailAddress> owaList = [
        SELECT Id FROM OrgWideEmailAddress
        WHERE DisplayName = :ORG_WIDE_EMAIL_DISPLAY_NAME
        WITH SYSTEM_MODE
        LIMIT 1
    ];
    if (!owaList.isEmpty()) {
        orgWideEmailAddressId = owaList[0].Id;
    }

    sendStudentDefermentProcessCompleteEmail(studentUsers, data, orgWideEmailAddressId);

    System.debug(LOG_PREFIX + 'Deferment process complete notify Done.');
}

@TestVisible
private static void sendStudentDefermentProcessCompleteEmail(
    List<User> studentUsers,
    MergeData data,
    Id orgWideEmailAddressId
) {
    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

    String subject = 'Deferment Process Completed – ' + data.referenceNumber;
    String htmlBody = buildStudentDefermentProcessCompleteHtmlBody(data);

    for (User student : studentUsers) {
        if (String.isBlank(student.Email)) {
            System.debug(LOG_PREFIX + 'SKIP deferment process complete email for ' + student.Id + ': no Email on User record.');
            continue;
        }

        String plainBody =
            'Dear ' + data.studentName + ',\n' +
            'This is to confirm that your deferment process has been successfully completed.\n\n' +
            'Application Reference Number: ' + data.referenceNumber + '\n' +
            'Programme: ' + data.programmeName + '\n' +
            'Deferment Status: Completed\n' +
            'No Dues Status: Completed\n\n' +
            'The deferment and applicable No Dues process have been completed successfully. ' +
            'No further action is required from your end at this stage.\n\n' +
            'This is an automated notification. Please do not reply to this email.';

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(student.Id);
        mail.setSaveAsActivity(false);
        if (orgWideEmailAddressId != null) {
            mail.setOrgWideEmailAddressId(orgWideEmailAddressId);
        }
        mail.setSubject(subject);
        mail.setPlainTextBody(plainBody);
        mail.setHtmlBody(htmlBody);
        emails.add(mail);
    }

    if (emails.isEmpty()) {
        System.debug(LOG_PREFIX + 'No deferment process complete emails prepared (no valid Email on student User).');
        return;
    }

    List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
    Integer sentCount = 0;
    for (Messaging.SendEmailResult r : results) {
        if (r.isSuccess()) {
            sentCount++;
        } else {
            for (Messaging.SendEmailError err : r.getErrors()) {
                System.debug(LOG_PREFIX + 'Deferment process complete email send FAILED: ' + err.getStatusCode() + ' - ' + err.getMessage());
            }
        }
    }
    System.debug(LOG_PREFIX + 'Deferment process complete emails sent: ' + sentCount + ' of ' + emails.size() + ' prepared.');
}

private static String buildStudentDefermentProcessCompleteHtmlBody(
    MergeData data
) {
    String logoUrl = 'https://platform-energy-10.file.force.com/sfc/dist/version/download/?oid=00DdN00000UKZDF&ids=068OS00000HhGpW&d=%2Fa%2FOS000004pTP4%2FHGj69FkH73m3IykmWhrnPeOUC1sVTbBGMN1KV9Z0RHI&asPdf=false';

    return
        '<html><body style="font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 20px;">' +
        '<table width="600" align="center" style="background-color: #ffffff; border: 1px solid #dddddd;">' +

        '<tr><td align="center" style="background-color: #4B2E83; padding: 20px;">' +
        '<h2 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: bold;">Deferment Process Completed</h2>' +
        '</td></tr>' +

        '<tr><td align="center" style="padding: 25px; background-color: #ffffff;">' +
        '<img src="' + logoUrl + '" width="150" height="60" alt="SPJIMR Logo"/>' +
        '</td></tr>' +

        '<tr><td align="left" style="padding: 0px 30px 20px 30px;">' +
        '<p style="font-size: 16px; font-weight: bold; color: #333333; margin: 0;">' +
        'Dear ' + data.studentName.escapeHtml4() + ',<br/>this is to confirm that your deferment process has been successfully completed.' +
        '</p></td></tr>' +

        '<tr><td style="padding: 0px 30px 30px 30px;">' +
        '<table width="100%" style="border-collapse: collapse;">' +
        buildEmailRow('Application Reference Number', data.referenceNumber) +
        buildEmailRow('Programme', data.programmeName) +
        buildEmailRow('Deferment Status', 'Completed') +
        buildEmailRow('No Dues Status', 'Completed') +
        '</table>' +
        '</td></tr>' +

        '<tr><td style="padding: 0px 30px 30px 30px; font-size: 13px; color: #333333;">' +
        '<p style="margin: 0 0 10px 0;">The deferment and applicable No Dues process have been completed successfully. No further action is required from your end at this stage.</p>' +
        '<p style="margin: 0; color: #666666; font-size: 12px;">This is an automated notification. Please do not reply to this email.</p>' +
        '</td></tr>' +

        '</table>' +
        '</body></html>';
}

}
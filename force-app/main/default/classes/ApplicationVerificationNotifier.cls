public without sharing class ApplicationVerificationNotifier {

    @AuraEnabled 
    public static String notifyApplicant(Id appVerId) {

        // Step 1 — Query Document Details
        List<Document_Details__c> docs = [
            SELECT Id, Name, Document_Review_Status__c, Remarks__c
            FROM Document_Details__c
            WHERE Application_Verification__c = :appVerId
        ];

        if (docs.isEmpty()) {
            return 'NO_DOCS';
        }

        Boolean allVerified = true;
        Boolean hasRejected = false;

        // Step 2 — Determine overall status
        for (Document_Details__c d : docs) {

            if (d.Document_Review_Status__c == 'Assigned' ||
                d.Document_Review_Status__c == 'Not Assigned') {
                return 'PENDING_DOCS';
            }

            if (d.Document_Review_Status__c == 'Rejected' ||
                d.Document_Review_Status__c == 'Change Requested') {
                hasRejected = true;
            }

            if (d.Document_Review_Status__c != 'Verified') {
                allVerified = false;
            }
        }

        if (allVerified && !hasRejected) {
            return 'Nothing to notify applicant since all documents are verified';
        }

        if (!hasRejected) {
            return 'NO_REJECTED_DOCS';
        }

        // Step 3 — Query parent Application Verification
        Application_Verification__c av = [
            SELECT Id,
                   Application__r.Applicant__r.PersonEmail,
                   Application__r.Applicant__r.PersonContactId
            FROM Application_Verification__c
            WHERE Id = :appVerId LIMIT 1
        ];

        if (av.Application__r.Applicant__r.PersonEmail == null) {
            return 'NO_EMAIL';
        }

        // Step 4 — Fetch email template dynamically
        EmailTemplate tpl;
        try {
            tpl = [
                SELECT Id 
                FROM EmailTemplate 
                WHERE DeveloperName = 'Application_Verification_Rejection'
                LIMIT 1
            ];
        }
        catch(Exception e){
            return 'TEMPLATE_NOT_FOUND';
        }

        // Step 5 — Send Email
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(av.Application__r.Applicant__r.PersonContactId);
        mail.setWhatId(appVerId);
        mail.setTemplateId(tpl.Id);
        mail.setSaveAsActivity(false);

        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

        // Step 6 — Create Website Notification record
        CustomNotification__c notif = new CustomNotification__c(
            Recipient_Email__c = av.Application__r.Applicant__r.PersonEmail,
            Title__c = 'Your Application has been Rejected',
            IsRead__c = false,
            Message__c = 'Your application documents have been reviewed.'+
            'Some were rejected. Please re-upload the required documents.'
        );
        
        

        try {
            insert notif;

            if(av.Application__r.Applicant__r.PersonEmail!=null){
            List<User> applicantUser = [SELECT Id FROM User 
                WHERE Email=:av.Application__r.Applicant__r.PersonEmail 
                AND IsActive=true LIMIT 1];

            CustomNotification__share shareNotification = new CustomNotification__share(
                ParentId = notif.Id, UserOrGroupId = applicantUser[0].Id, 
                AccessLevel = 'Read', RowCause =Schema.CustomNotification__share.RowCause.Manual
            );
            insert shareNotification;
        }
        }
        catch(DmlException e){
            System.debug('Could not insert notification: '+e.getMessage());
        }

        return 'SUCCESS';
    }
}
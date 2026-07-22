public with sharing class LeadEmailHelper {
    
    
    
    
    
    @future
    public static void sendWelcomeEmail(List<Id> leadIds) {
        // Get the leads with required fields
        List<Lead> leads = [SELECT Id, FirstName, LastName, Email, Company, Phone, LeadSource, 
                           CreatedBy.Name, CreatedDate 
                           FROM Lead 
                           WHERE Id IN :leadIds AND Email != NULL];
        
        if(leads.isEmpty()) return;
        
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Task> activities = new List<Task>();
        
        // Get organization-wide email address or use current user's email
        OrgWideEmailAddress[] owea = [SELECT Id, Address, DisplayName FROM OrgWideEmailAddress LIMIT 1];
        
        for(Lead ld : leads) {
            // Create email
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            
            // Set email properties
            email.setToAddresses(new List<String>{ld.Email});
            // email.setToAddresses(new List<String>{'huzaifa@finessedirect.com','Ankur@finessedirect.com'});
            // email.setToAddresses(new List<String>{'huzaifaansari.sfdx@gmail.com'});
            email.setSubject('Thank You for Your Interest in SPJIMR');
            if (!owea.isEmpty()) {
                email.setOrgWideEmailAddressId(owea.get(0).Id);
            }

            // Load static resource logo as Blob
            StaticResource logoRes = [
                SELECT Body FROM StaticResource 
                WHERE Name = 'SPJMIR_logo' 
                LIMIT 1
            ];
            Blob logoBlob = logoRes.Body;

            // Messaging.EmailFileAttachment inlineImg = new Messaging.EmailFileAttachment();
            // inlineImg.setBody(logoBlob);
            // inlineImg.setContentType('image/png'); // change if jpg/gif
            // inlineImg.setInline(true);
            // inlineImg.setFileName('logo.png');
            
            // Build email body
            String firstName = String.isNotBlank(ld.FirstName) ? ld.FirstName : '';
            String lastName = String.isNotBlank(ld.LastName) ? ' ' + ld.LastName : '';
            String strEmail = ld.Email;
            String strPassword = '';
            
            String htmlBody = getEmailBody(escapeHtml(firstName + lastName), strEmail, strPassword);
            // htmlBody = htmlBody.replaceAll('(actual image tag)', '<img src="cid:logo.png" alt="Company Logo" style="width:200px;height:auto;" />');

            email.setHtmlBody(htmlBody);
            // email.setPlainTextBody(getPlainTextBody(firstName + lastName));

            email.setTargetObjectId(ld.Id);
            email.setSaveAsActivity(true);
            
            emails.add(email);
            
        }
        
        // Send emails
        if(!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
                // Create task for failed email
                for(Lead ld : leads) {
                    Task t = new Task(
                        Subject = 'Welcome Email send on ' +System.now(),
                        Status = 'Completed',
                        Priority = 'High',
                        WhoId = ld.Id,
                        ActivityDate = Date.today(),
                        // Description = 'Failed to send welcome email: ' + e.getMessage(),
                        Type = 'Email',
                        TaskSubtype = 'Email'
                    );
                    activities.add(t);
                }


                if(!activities.isEmpty()) {
                    // upsert activities;
                }
                
            } catch(Exception e) {
                // Log error
                System.debug('Error sending welcome emails: ' + e.getMessage());
                
                // Create task for failed email
                for(Lead ld : leads) {
                    Task t = new Task(
                        Subject = 'Failed to Send Welcome Email',
                        Status = 'Completed',
                        Priority = 'High',
                        WhoId = ld.Id,
                        ActivityDate = Date.today(),
                        Description = 'Failed to send welcome email: ' + e.getMessage(),
                        Type = 'Email',
                        TaskSubtype = 'Email'
                    );
                    activities.add(t);
                }
                
                if(!activities.isEmpty()) {
                    upsert activities;
                }
            }
        }
    }
    
    // Overloaded method to accept List<Lead> for trigger context
    public static void sendWelcomeEmail(List<Lead> leads) {
        List<Id> leadIds = new List<Id>();
        for(Lead ld : leads) {
            leadIds.add(ld.Id);
        }
        sendWelcomeEmail(leadIds);
    }
    
    // Method to generate HTML email body
    private static String getEmailBody(String fullName, String email, String password) {
        String baseUrl = System.Url.getOrgDomainUrl().toExternalForm();
        String logoUrl = baseUrl + '/resource/SPJMIR_logo';

        return '<!DOCTYPE html>' +
            '<html>' +
            '<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333333; max-width: 600px; margin: 0 auto;">' +
            '    <div style="text-align: center;">' +
            '        <img src="' + logoUrl + '" alt="Company Logo" style="width:200px;height:auto;" />' +
            // '        <img src="cid:SPJMIR_logo" alt="Company Logo" style="width:200px;height:auto;" />' +
            '    </div>' +
            '    <p>Dear ' + fullName + ',</p>' +
            '    <p>Thank you for applying.</p>' +
            '    <p>Thanks<br>Admissions Office<br><b>SPJIMR</b> PGPM</p>' +
            '</body>' +
            '</html>';

        // return '<!DOCTYPE html>' +
        //     '<html>' +
        //     '<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333333; max-width: 600px; margin: 0 auto;">' +
        //     '    <div style="text-align: center;">' +
        //     '        <img src="' + logoUrl + '" alt="Company Logo" style="width:200px;height:auto;" />' +
        //     // '        <img src="cid:SPJMIR_logo" alt="Company Logo" style="width:200px;height:auto;" />' +
        //     '    </div>' +
        //     '    <p>Dear ' + fullName + ',</p>' +
        //     '    <p>Thank you for applying/verifying at <b>SPJIMR</b> PGPM</p>' +
        //     '    <p>You may now directly login and start filling your application by clicking <a href="https://pgpmadmissions.spjimr.org">here</a>.</p>' +
        //     '    <p>If clicking the link doesn\'t work, you can copy and paste the link into your browser\'s address window, or retype it there.</p>' +
        //     '    <p><a href="https://pgpmadmissions.spjimr.org">https://pgpmadmissions.spjimr.org</a></p>' +
        //     '    <p><b>Email</b> - <a href="mailto:' + email + '">' + email + '</a></p>' +
        //     '    <p><b>Password</b> - ' + password + '</p>' +
        //     '    <p>For any query click on the below link:</p>' +
        //     '    <p><a href="https://pgpmadmissions.spjimr.org">https://pgpmadmissions.spjimr.org</a></p>' +
        //     '    <p>Thanks<br>Admissions Office<br><b>SPJIMR</b> PGPM</p>' +
        //     '</body>' +
        //     '</html>';
    }

    
    // Method to generate plain text email body
    private static String getPlainTextBody(String fullName) {
        return 'Welcome to SPJIMR\n\n' +
               'Dear ' + fullName + ',\n\n' +
               'Thank you for your interest in our programs at SPJIMR. We\'re excited to have you join our community of learners and leaders.\n\n' +
               'Our team will review your information and get back to you shortly with the next steps in the application process.\n\n' +
               'In the meantime, feel free to explore our website to learn more about our programs and campus life.\n\n' +
               'Visit Our Website: https://www.spjimr.org\n\n' +
               'If you have any questions, please don\'t hesitate to contact us at admissions@spjimr.org or call us at +91 22 61454200.\n\n' +
               'Best regards,\nThe SPJIMR Team\n\n' +
               'SP Jain Institute of Management & Research\n' +
               'Munshi Nagar, Dadabhai Road, Andheri West, Mumbai - 400 058, India\n' +
               '© ' + System.today().year() + ' SPJIMR. All rights reserved.';
    }

    private static String escapeHtml(String input) {
        if (input == null) return '';
        String output = input;
        output = output.replaceAll('&', '&amp;');
        output = output.replaceAll('<', '&lt;');
        output = output.replaceAll('>', '&gt;');
        output = output.replaceAll('"', '&quot;');
        output = output.replaceAll('\'', '&#39;'); // single quote escaped
        return output;
    }



}
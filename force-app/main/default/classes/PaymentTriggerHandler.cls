public with sharing class PaymentTriggerHandler {

    public static void updateLeadSubmittedDate(
        List<Payment__c> newList,
        Map<Id, Payment__c> oldMap
    ) {

       
        Map<Id, Datetime> applicationToTimestamp = new Map<Id, Datetime>();

        for (Payment__c p : newList) {

            // Only Application Fee
            if (p.Payment_Type__c != 'Application Fee') continue;

            if (p.Application__c == null) continue;
            if (p.Razorpay_Order_Creation_Timestamp__c == null) continue;

            // Insert OR meaningful update
            if (oldMap == null ||
                oldMap.get(p.Id).Razorpay_Order_Creation_Timestamp__c !=
                p.Razorpay_Order_Creation_Timestamp__c
            ) {
                applicationToTimestamp.put(
                    p.Application__c,
                    p.Razorpay_Order_Creation_Timestamp__c
                );
            }
        }

        if (applicationToTimestamp.isEmpty()) return;

        
        Map<Id, Id> applicationToAccount = new Map<Id, Id>();

        for (Application__c app : [
            SELECT Id, Applicant__c
            FROM Application__c
            WHERE Id IN :applicationToTimestamp.keySet()
            AND Applicant__c != null
        ]) {
            applicationToAccount.put(app.Id, app.Applicant__c);
        }

        if (applicationToAccount.isEmpty()) return;

      
        Map<Id, Id> accountToContact = new Map<Id, Id>();

        for (Account acc : [
            SELECT Id, PersonContactId
            FROM Account
            WHERE Id IN :applicationToAccount.values()
            AND PersonContactId != null
        ]) {
            accountToContact.put(acc.Id, acc.PersonContactId);
        }

        if (accountToContact.isEmpty()) return;

        
        Map<Id, Id> contactToLead = new Map<Id, Id>();

        for (Lead l : [
            SELECT Id, ConvertedContactId
            FROM Lead
            WHERE IsConverted = true
            AND ConvertedContactId IN :accountToContact.values()
        ]) {
            contactToLead.put(l.ConvertedContactId, l.Id);
        }

        if (contactToLead.isEmpty()) return;

       
        List<Lead> leadsToUpdate = new List<Lead>();

        for (Id appId : applicationToAccount.keySet()) {

            Id accId     = applicationToAccount.get(appId);
            Id contactId = accountToContact.get(accId);
            Id leadId    = contactToLead.get(contactId);

            if (leadId == null) continue;

            leadsToUpdate.add(new Lead(
                Id = leadId,
                Application_Submitted_Date_Time__c =
                    applicationToTimestamp.get(appId)
            ));
        }

        
        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }
     public static void sendApplicationFeeConformationEmail(Id paymentId) {
        
        // Query Payment Record
        Payment__c payment = [
            SELECT Id, Application__c,Application__r.Program__r.Name,Application__r.Applicant__r.Name, Status__c, Payment_Type__c 
            FROM Payment__c 
            WHERE Id = :paymentId 
            LIMIT 1
        ];
        // Update Payment with Programme Full Name
        Payment__c updatePayment = new Payment__c();
        updatePayment.Id = payment.Id;
        updatePayment.Programme_Full_Name__c = payment.Application__r.Program__r.Name;
        updatePayment.Applicant_Name__c = payment.Application__r.Applicant__r.Name;
        update updatePayment;
        
        // Set Flow Input Variables
        Map<String, Object> flowInputs = new Map<String, Object>();
        flowInputs.put('recordId', payment.id);
        
        // Invoke the Flow
        Flow.Interview.createInterview(
            'Application_Fee_Payment_Confirmation_Email_Notification', 
            flowInputs
        ).start();
    }
}
public without sharing class PaymentReceiptController {
     public String payeename{get;set;}
     public String payee_email{get;set;}
     public Decimal amount{get;set;}
     public String orderId{get;set;}
     public String paymentId{get;set;}
     public String applicationNumber {get;set;}
     public String dateVal{get;set;}
    public String programName {get;set;}
    public String typeOfId {get;set;}
    public String paymentTypeMessage {get;set;}
    public String recId {get;set;}
        
     public PaymentReceiptController(){
        recId = ApexPages.currentPage().getParameters().get('id');
        String orderCompletionDate = ApexPages.currentPage().getParameters().get('orderCompletionDate');
        
        system.debug('Received Order Id :'+orderId);
        List<Payment__c> paymentRecord = [SELECT Id, Payee_Name__c, Payee_Email__c,Application__r.Name,Payment_Type__c,
                                          Amount_Paid__c,Razorpay_Payment_Id__c,Razorpay_Order_Creation_Timestamp__c,
                                         Application__r.Program__r.Name, Payment_Completion_Date__c,Gateway_Transaction_Id__c
        FROM Payment__c WHERE Id =:recId];
        system.debug('Payment Record: '+paymentRecord);
        paymentTypeMessage = paymentRecord[0].Payment_Type__c=='Application Fee'?'Registration Fee Submission successful':'Acceptance Fee Submission successful';
        // dateVal = paymentRecord[0].Razorpay_Order_Creation_Timestamp__c!=null? String.valueOf(paymentRecord[0].Razorpay_Order_Creation_Timestamp__c.date()).replace('-','/'):
        // String.valueOf(paymentRecord[0].Payment_Completion_Date__c.date()).replace('-','/');

        if(paymentRecord[0].Payment_Type__c== 'Offer Acceptance Fee'){
            String datePart =ApexPages.currentPage().getParameters().get('orderCompletionDate').split(' ')[0]; // 04/03/2026
    
            List<String> parts = datePart.split('/');
            
            Integer month = Integer.valueOf(parts[0]);
            Integer day   = Integer.valueOf(parts[1]);
            Integer year  = Integer.valueOf(parts[2]);
            
            Date d = Date.newInstance(year, month, day);
            
            String formattedDate = String.valueOf(d);
                
               
                dateVal = formattedDate;
                amount = Decimal.valueOf(ApexPages.currentPage().getParameters().get('orderAmount'));
                paymentId = ApexPages.currentPage().getParameters().get('transactionId');
        }else{
            dateVal = String.valueOf(paymentRecord[0].Razorpay_Order_Creation_Timestamp__c.date()).replace('-','/');
            paymentId = paymentRecord[0].Razorpay_Payment_Id__c != null?paymentRecord[0].Razorpay_Payment_Id__c:paymentRecord[0].Gateway_Transaction_Id__c;
            amount = paymentRecord[0].Amount_Paid__c;
        }
        typeOfId = paymentRecord[0].Payment_Type__c=='Application Fee'?'Payment Id':'Transaction Id';
		applicationNumber = [SELECT Name FROM Application__c WHERE Id=:paymentRecord[0].Application__c LIMIT 1].Name;
        payeename = paymentRecord[0].Payee_Name__c;
        payee_email = paymentRecord[0].Payee_Email__c;
       
        
        
         programName = paymentRecord[0].Application__r.Program__r.Name;
    }
    

}
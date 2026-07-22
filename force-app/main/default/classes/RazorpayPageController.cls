public without sharing class RazorpayPageController {
    public class RazorPayResponseOrder {
        public String id;
        public String status;
        public String amount;
        public String attempts;
        public String amount_paid;
        public String created_at;
        public String entity;
    }
    
    public String razorpayKey { get; private set; }
    public String homePageUrl {get;set;}
    public String recordId{get;set;}
    public String orderId {get;set;}
    public String amount {get;set;}
    public String payeename {get;set;}
    public String payee_email {get;set;}
    public String paymentStatus {get; set;}
    public String paymentId {get; set;}
    public string callbackUrl{get; set;}
    public string cancelUrl{get; set;}
    public string description{get;set;}
    public RazorpayPageController() {
        
       String networkId, urlPathPrefix;
                            List<Network> networks = [
                                SELECT Id, UrlPathPrefix
                                FROM Network
                                WHERE Name = 'Application Portal'
                                LIMIT 1
                            ];
                            if (!networks.isEmpty()) {
                                networkId = networks[0].Id;
                                urlPathPrefix = networks[0].UrlPathPrefix;
                            }

                            homePageUrl = Network.getLoginUrl(networkId);
                            if (homePageUrl.endsWith('/login')) {
                                homePageUrl = homePageUrl.substring(0, homePageUrl.length() - 7);
                            }
        					
        
        
        List<Razorpay_APIKeys__mdt> apiKeys = [SELECT Public_Key__c FROM Razorpay_APIKeys__mdt WHERE DeveloperName='Live_Key' LIMIT 1]; 
        razorpayKey = apiKeys[0].Public_Key__c; 
        callbackUrl=homePageUrl+'services/apexrest/razorpay/callback';
        
        recordId = ApexPages.currentPage().getParameters().get('Id');
        List<Payment__c> paymentList = [SELECT Id, Amount__c, Payee_Name__c,Payee_Email__c, 
                                        Gateway_Order_Id__c,Status__c,Razorpay_Payment_Id__c,
                                       	Application__r.Program__r.Program_Code__c,
                                        Application__r.Name
                                        FROM Payment__c WHERE Id=:recordId LIMIT 1];
        if(!paymentList.isEmpty()){
            description = paymentList[0].Application__r.Name + ' - Application Fee Payment for ' +paymentList[0].Application__r.Program__r.Program_Code__c;
            cancelUrl=homePageUrl+'/s/paymentcancelpage?id='+paymentList[0].Id;
            orderId = paymentList[0].Gateway_Order_Id__c;
            payeename = paymentList[0].Payee_Name__c;
            amount = String.valueOf(paymentList[0].Amount__c);
            payee_email = paymentList[0].Payee_Email__c;
            paymentId =paymentList[0].Razorpay_Payment_Id__c;
            paymentStatus = paymentList[0].Status__c;
        }
        
       // callbackUrl = URL.getOrgDomainUrl().toExternalForm()+'/applicationportal/s/paymentredirectpage';
        
    }
    
    @RemoteAction
public static Payment__c checkExistingPayment(String orderId) {
 List<Razorpay_APIKeys__mdt> apiKeys = [SELECT Public_Key__c,Secret_Key__c FROM Razorpay_APIKeys__mdt WHERE DeveloperName='Live_Key' LIMIT 1];

    
    // Query once
    Payment__c existing = [
        SELECT Id, Status__c, Razorpay_Payment_Id__c
        FROM Payment__c
        WHERE Gateway_Order_Id__c = :orderId
        LIMIT 1
    ];

    HttpRequest req = new HttpRequest();
    req.setEndpoint('https://api.razorpay.com/v1/orders/' + orderId + '/payments');
    req.setMethod('GET');
    req.setHeader(
  'Authorization',
  'Basic ' + EncodingUtil.base64Encode(
      Blob.valueOf(apiKeys[0].Public_Key__c + ':' + apiKeys[0].Secret_Key__c)
  )
);

    HttpResponse res = new Http().send(req);

    if (res.getStatusCode() == 200) {

        Map<String, Object> responseMap =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        List<Object> payments =
            (List<Object>) responseMap.get('items');

        for (Object obj : payments) {

            Map<String, Object> payment =
                (Map<String, Object>) obj;

            if ((String)payment.get('status') == 'captured') {

                String paymentId = (String)payment.get('id');

                // Update only if mismatch
                if (existing.Razorpay_Payment_Id__c != paymentId
                    || existing.Status__c != 'paid') {

                    existing.Razorpay_Payment_Id__c = paymentId;
                    existing.Status__c = 'paid';
                    update existing;
                }

                return existing;
            }
        }
    }

    return null;
}
    
    
    @AuraEnabled
public static void generatePaymentReceipt(String orderId,String paymentId) {
    PageReference pdfPage = Page.PaymentReceiptPDF;
    
    List<Payment__c> paymentRecord = [SELECT Id FROM Payment__c WHERE Gateway_Order_Id__c=:orderId LIMIT 1];
    Id paymentRecordId = paymentRecord[0].Id;
    List<ContentDocumentLink> existing = [
        SELECT Id 
        FROM ContentDocumentLink 
        WHERE LinkedEntityId = :paymentRecordId
        LIMIT 1
    ];

    if(!existing.isEmpty()){
        System.debug('Receipt already exists. Skipping generation.');
        return;
    }
    pdfPage.getParameters().put('id', paymentRecordId);
     String networkId, urlPathPrefix;
                            List<Network> networks = [
                                SELECT Id, UrlPathPrefix
                                FROM Network
                                WHERE Name = 'Application Portal'
                                LIMIT 1
                            ];
                            if (!networks.isEmpty()) {
                                networkId = networks[0].Id;
                                urlPathPrefix = networks[0].UrlPathPrefix;
                            }

                            String homePageUrl = Network.getLoginUrl(networkId);
                            if (homePageUrl.endsWith('/s/login')) {
                                homePageUrl = homePageUrl.substring(0, homePageUrl.length() - 7);
                            }

   
     Blob pdfBlob;

if(Test.isRunningTest()){
    pdfBlob = Blob.valueOf('Test PDF');
} else {
    pdfBlob = pdfPage.getContentAsPDF();
}
    
	ContentVersion contentVersion = new ContentVersion();
    contentVersion.ContentLocation = 'S'; 
    contentVersion.PathOnClient = orderId+'.pdf';
    contentVersion.Title = orderId+'.pdf';
    contentVersion.VersionData = pdfBlob;
    try{
        insert contentVersion;
    }
    catch(DMLException e){
        system.debug('Could not insert contentVersion '+e.getMessage());
    }
    
    Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id LIMIT 1].ContentDocumentId;
    List<Payment__c> listPayments = [SELECT Id FROM Payment__c WHERE Razorpay_Payment_Id__c=:paymentId LIMIT 1];
    ContentDocumentLink contentDocumentLink = new ContentDocumentLink();
    contentDocumentLink.ContentDocumentId = contentDocId;
    contentDocumentLink.LinkedEntityId = listPayments[0].Id;
    contentDocumentLink.ShareType = 'I'; // Inferred permission
    contentDocumentLink.Visibility = 'AllUsers';
    try{
        insert contentDocumentLink;
        String returnUrl = homePageUrl+'sfc/servlet.shepherd/document/download/'+contentDocId+'?operationContext=S1';
        paymentRecord[0].PDFUrl__c = returnUrl;
        update paymentRecord;
    }
    catch(DMLEXception e){
        system.debug('Could not insert content Doc Link '+e.getMessage());
        
    }  
    
}
    
    @RemoteAction
    public static List<Payment__c> updatePayment(String orderId,String paymentId,String paymentSignature){
        Boolean authenticSignature = false;
        List<Razorpay_APIKeys__mdt> apiKeys = [SELECT Public_Key__c,Secret_Key__c FROM Razorpay_APIKeys__mdt WHERE DeveloperName='Live_Key' LIMIT 1]; 
        Blob generatedSignatureBlob = Crypto.generateMac('HmacSHA256',
                                                         Blob.valueOf(orderId+'|'+paymentId),
                                                         Blob.valueOf(apiKeys[0].Secret_Key__c));
        
		String generatedSignatureHex = EncodingUtil.convertToHex(generatedSignatureBlob);
        system.debug('Generated Signature from OrderId: '+orderId+' | '+paymentId+' is '+generatedSignatureHex);
        system.debug('Received Payment Signature is: '+paymentSignature);
        if(generatedSignatureHex.equalsIgnoreCase(paymentSignature)){
            
            authenticSignature = true;
        }
        else{
            System.debug('Unauthorized payment attempt. Stopping execution.');
            throw new CalloutException('Unauthorized Payment');
        }        
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.razorpay.com/v1/orders/' + orderId);
        req.setMethod('GET');
       req.setHeader(
  'Authorization',
  'Basic ' + EncodingUtil.base64Encode(
      Blob.valueOf(apiKeys[0].Public_Key__c + ':' + apiKeys[0].Secret_Key__c)
  )
);
        
        HttpResponse res = new Http().send(req);
        
        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            RazorPayResponseOrder responseValues = 
                (RazorPayResponseOrder)JSON.deserialize(res.getBody(),RazorPayResponseOrder.class);
            system.debug('Response is '+responseValues);
            List<Payment__c> paymentRecord = [SELECT Id, Application__c ,Application__r.Program__r.Name,Payment_Type__c,
                                              Payee_Email__c
                                              FROM Payment__c 
                                              WHERE Gateway_Order_Id__c = :orderId 
                                              LIMIT 1];
            paymentRecord[0].Payment_Signature__c = paymentSignature;
            paymentRecord[0].Razorpay_Order_Creation_Timestamp__c = DateTime.newInstance(1970, 1, 1, 0, 0, 0).addSeconds(Integer.valueOf(responseValues.created_at));
            paymentRecord[0].Status__c = responseValues.status;
            paymentRecord[0].Amount__c = Decimal.valueOf(responseValues.amount)/100;
            paymentRecord[0].Amount_Paid__c = Decimal.valueOf(responseValues.amount_paid)/100;
            paymentRecord[0].Razorpay_Payment_Id__c = paymentId;
            paymentRecord[0].Is_Authorized__c = authenticSignature;
            Boolean updateApplication = paymentRecord[0].Payment_Type__c == 'Application Fee';
            if(responseValues.status == 'paid'){
                
                List<Application__c> applicationList = [SELECT Id,Application_Status__c,Program__r.Name 
                                                        FROM Application__c 
                                                        WHERE Id = :paymentRecord[0].Application__c
                                                       	LIMIT 1];
                if(applicationList.size()>0){
                    
                    try{
                        if(updateApplication){
                            applicationList[0].Application_Status__c = 'Paid';
                            applicationList[0].Application_Stage__c = 'Payment';
                            update applicationList;
                        }
                        
                      CustomNotification__c notif =  new CustomNotification__c(Title__c='Application Fee Payment',
                        Message__c='Your Application Fees for '+applicationList[0].Program__r?.Name +' has been paid. ',
                        IsRead__c = false,Recipient_Email__c = paymentRecord[0].Payee_Email__c);

                        Insert notif;
                  
                    }
                    catch(DMLException e){
                        system.debug('Could not Update Application Record '+e.getMessage());
                    }
                    
                    
                    
                    String networkId, urlPathPrefix;
                            List<Network> networks = [
                                SELECT Id, UrlPathPrefix
                                FROM Network
                                WHERE Name = 'Application Portal'
                                LIMIT 1
                            ];
                            if (!networks.isEmpty()) {
                                networkId = networks[0].Id;
                                urlPathPrefix = networks[0].UrlPathPrefix;
                            }

                            String pdfPageUrl = Network.getLoginUrl(networkId);
                            if (pdfPageUrl.endsWith('/login')) {
                                pdfPageUrl = pdfPageUrl.substring(0, pdfPageUrl.length() - 5);
                            }
                    
                    pdfPageUrl+='paymentredirect2/'+paymentRecord[0].Id;
                    paymentRecord[0].PDFUrl__c = pdfPageUrl;
                }
            }
            
            try{
                update paymentRecord;
                system.debug('Successfully Updated payment record :'+paymentRecord);
                return paymentRecord;
            }
            catch(DMLException e){
               // throw new AuraHandledException('Error updating payment record '+e.getMessage() );
                system.debug('Exception updating Payment Record '+e.getMessage());
                 return new List<Payment__c>();
            }
        }
        else{
            System.debug('Razorpay Fetch Payment call failed. Status: ' + res.getStatusCode() + 
                         ' Body: ' + res.getBody());
            return new List<Payment__c>();
            
        }
    }
}
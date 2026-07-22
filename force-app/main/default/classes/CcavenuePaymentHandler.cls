public without sharing class CcavenuePaymentHandler {

   @AuraEnabled(cacheable=true)
public static String getPaymentStatusByOrderId(String orderId){

    if(String.isBlank(orderId)){
        return null;
    }

    List<Payment__c> paymentList = [
        SELECT Status__c
        FROM Payment__c
        WHERE Gateway_Order_Id__c = :orderId
        AND Payment_Gateway__c = 'CC Avenue'
        LIMIT 1
    ];

    if(paymentList.isEmpty()){
        return null;
    }

    return paymentList[0].Status__c;
}
   @AuraEnabled
public static String createOrUpdateOrder(String orderId, String programCode){

    List<Application__c> applicationList = [
        SELECT Id,Program__r.Name
        FROM Application__c
        WHERE Program__r.Program_Code__c = :programCode 
        AND Applicant__r.PersonEmail = :UserInfo.getUserEmail()
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];

    if(applicationList.isEmpty()){
        return null;
    }

    Id applicationId = applicationList[0].Id;

    // Check existing Offer Acceptance Fee payment
    List<Payment__c> paymentList = [
        SELECT Id, Status__c
        FROM Payment__c 
        WHERE Application__c = :applicationId
        AND Payment_Type__c = 'Offer Acceptance Fee'
        AND Payment_Gateway__c = 'CC Avenue'
        LIMIT 1
    ];

    try{

        // 🔎 If record exists
        if(!paymentList.isEmpty()){

            Payment__c existingPayment = paymentList[0];

            // ✅ If already paid → return immediately
            if(existingPayment.Status__c == 'paid'){
                return 'paid';
            }

            // 🔄 If not paid → update orderId and reset state
            existingPayment.Gateway_Order_Id__c = orderId;
            existingPayment.Status__c = 'created';
            existingPayment.Is_Authorized__c = false;
            existingPayment.Gateway_Status__c = null;
            existingPayment.Amount_Paid__c = null;

            update existingPayment; 

            return 'created';
        }

        // 🆕 No existing record → create new
        insert new Payment__c(
            Amount__c = 200.00,
            Application__c = applicationId,
            Payment_Type__c = 'Offer Acceptance Fee',
            Payment_Gateway__c = 'CC Avenue',
            Status__c = 'created',
            Payee_Email__c = UserInfo.getUserEmail(),
            Payee_Name__c = UserInfo.getName(),
            Gateway_Order_Id__c = orderId
        );

        return 'created';

    }
    catch(DMLException e){
        throw new AuraHandledException(e.getMessage());
    }
}

@TestVisible
private static String normalizeCCAvenueStatus(String gatewayStatus){
    system.debug('Inside normazile status, got gateway status: '+gatewayStatus);
    if(gatewayStatus == 'Success'){
        
        return 'paid';
    }
    else if(gatewayStatus == 'Failure'){
        return 'failed';
    }
    else if(gatewayStatus == 'Aborted'){
        return 'attempted';
    }
    else{
        return 'created';
    }
}

@AuraEnabled
public static String handleCCAvenueResponse(String decryptedResponse){

    if(String.isBlank(decryptedResponse)){
        throw new AuraHandledException('Empty response from CC Avenue');
    }

    // 1️⃣ Convert query string to Map
    Map<String, String> responseMap = new Map<String, String>();

    for(String pair : decryptedResponse.split('&')){
        List<String> keyValue = pair.split('=');
        if(keyValue.size() == 2){
            responseMap.put(
                EncodingUtil.urlDecode(keyValue[0], 'UTF-8'),
                EncodingUtil.urlDecode(keyValue[1], 'UTF-8')
            );
        }
    }

    // 2️⃣ Extract required fields
    String orderId       = responseMap.get('order_id');
    String trackingId    = responseMap.get('tracking_id');
    String bankRefNo     = responseMap.get('bank_ref_no');
    String gatewayStatus = responseMap.get('order_status');
    String paymentMode   = responseMap.get('payment_mode');
    String cardName      = responseMap.get('card_name');
    String amountStr     = responseMap.get('amount');
    String transDateStr  = responseMap.get('trans_date');
    String statusMessage = responseMap.get('status_message');
    if(String.isBlank(orderId)){
        throw new AuraHandledException('Order ID missing in CC Avenue response');
    }

    // 3️⃣ Fetch Payment Record
    List<Payment__c> paymentList = [
        SELECT Id, Status__c,Application__c
        FROM Payment__c
        WHERE Gateway_Order_Id__c = :orderId
        AND Payment_Gateway__c = 'CC Avenue'
        LIMIT 1
    ];
if(paymentList.isEmpty()){
        throw new AuraHandledException('No matching Payment record found');
    }
    
    List<Application__c> applicationList = [SELECT Id,Program__r.Name FROM
    Application__c WHERE Id =:paymentList[0].Application__c LIMIT 1];

    if(applicationList.isEmpty()){
        throw new AuraHandledException('No Application record found');
    }

    // String networkId, urlPathPrefix;
    //                 List<Network> networks = [
    //                             SELECT Id, UrlPathPrefix
    //                             FROM Network
    //                             WHERE Name = 'Application Portal'
    //                             LIMIT 1
    //                         ];
    //                 if (!networks.isEmpty()) {
    //                     networkId = networks[0].Id;
    //                     urlPathPrefix = networks[0].UrlPathPrefix;
    //                 }
                    
    //                 String Url = Network.getLoginUrl(networkId);
    //                 if (Url.endsWith('/login')) {
    //                     Url = Url.substring(0, Url.length() - 5);
    //                 }
    //                 Url += 'payment/';

    

    Payment__c payment = paymentList[0];

    // 4️⃣ Normalize Status
    String internalStatus = normalizeCCAvenueStatus(gatewayStatus);

    // 5️⃣ Prevent duplicate paid updates
    if(payment.Status__c == 'paid' && internalStatus == 'paid'){
        return 'already paid'; // already processed
    }

    // 6️⃣ Convert amount
    Decimal amountPaid = 0;
    if(!String.isBlank(amountStr)){
        amountPaid = Decimal.valueOf(amountStr);
    }

    // 7️⃣ Parse Date (DD/MM/YYYY HH:mm:ss)
    DateTime gatewayDate;
    if(!String.isBlank(transDateStr)){
        List<String> parts = transDateStr.split(' ');
        List<String> dateParts = parts[0].split('/');
        List<String> timeParts = parts[1].split(':');

        gatewayDate = DateTime.newInstance(
            Integer.valueOf(dateParts[2]), // year
            Integer.valueOf(dateParts[1]), // month
            Integer.valueOf(dateParts[0]), // day
            Integer.valueOf(timeParts[0]),
            Integer.valueOf(timeParts[1]),
            Integer.valueOf(timeParts[2])
        );
    }

    // 8️⃣ Update Payment
    payment.Gateway_Transaction_Id__c   = trackingId;
    payment.Bank_Reference_Number__c    = bankRefNo;
    payment.Gateway_Status__c           = gatewayStatus;
    payment.Status__c                   = internalStatus;
    payment.Amount_Paid__c              = amountPaid;
    payment.Payment_Mode__c             = paymentMode;
    payment.Card_Type__c                = cardName;
    payment.Gateway_Response__c         = decryptedResponse;
    payment.Status_Message__c = statusMessage;
    
    // payment.PDFUrl__c = url+payment.Id;

    // Only mark authorized if successful
    payment.Is_Authorized__c = (internalStatus == 'paid');
    if(internalStatus == 'paid') payment.Payment_Completion_Date__c = gatewayDate;
    try{
        system.debug('Internal Status '+internalStatus);
        system.debug('Payment '+payment);
        update payment;
        if(internalStatus == 'failed')return 'failed';
        if(internalStatus == 'paid'){
            
            PageReference pdfPage = Page.PaymentReceiptPDF;
            pdfPage.getParameters().put('id', payment.Id);
            pdfPage.getParameters().put('orderCompletionDate', transDateStr);
            pdfPage.getParameters().put('orderAmount', amountStr);
            pdfPage.getParameters().put('transactionId',trackingId );
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

                if (!Test.isRunningTest()) {
                    pdfBlob = pdfPage.getContentAsPDF();
                } else {
                    pdfBlob = Blob.valueOf('Test PDF');
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
                ContentDocumentLink contentDocumentLink = new ContentDocumentLink();
                contentDocumentLink.ContentDocumentId = contentDocId;
                contentDocumentLink.LinkedEntityId = payment.Id;
                contentDocumentLink.ShareType = 'I'; // Inferred permission
                contentDocumentLink.Visibility = 'AllUsers';

                try{
                    insert contentDocumentLink;
                    String returnUrl = homePageUrl+'sfc/servlet.shepherd/document/download/'+contentDocId+'?operationContext=S1';
                    payment.PDFUrl__c = returnUrl;
                    update payment;
                    // return returnUrl;
                }
                catch(DMLEXception e){
                    system.debug('Could not insert content Doc Link '+e.getMessage());
                    return 'Failed '+e.getMessage();
            }     
                                // String pdfUrl =  RazorpayPageController.generatePaymentReceipt(orderId, trackingId);

                      CustomNotification__c notif =  new CustomNotification__c(Title__c='Acceptance Fee Payment',
                            Message__c='Your Acceptance Fees for '+applicationList[0].Program__r?.Name +' has been paid. ',
                            IsRead__c = false,Recipient_Email__c = UserInfo.getUserEmail());
                        
                        insert notif;
                        
                        CustomNotification__share shareNotif = new CustomNotification__share(
                            ParentId = notif.Id,
                            UserOrGroupId = UserInfo.getUserId(),
                            AccessLevel = 'Read',
                            RowCause = Schema.CustomNotification__share.RowCause.Manual
                        );
                        insert shareNotif;
                        return 'success';
                    
        }
    }
    catch(DMLException e){
        system.debug('Error Updating Payment '+e.getMessage() );
    }
    

    return internalStatus;
}
   

    @AuraEnabled
    public static Map<String, String> generatePaymentLink() {

        Map<String, String> resultMap = new Map<String, String>();

        try {
            List<CC_Avenue_Key__mdt> ccAvenueKeys = [
                SELECT AccessCode__c, MerchantId__c, Workingkey__c,IV__c
                FROM CC_Avenue_Key__mdt WHERE DeveloperName='Test_Key_3'
                LIMIT 1
            ];

            if (ccAvenueKeys.isEmpty()) {
                return new Map<String, String>{ 'ERROR' => 'CCAvenue Keys Not Found' };
            }

            CC_Avenue_Key__mdt keyRecord = ccAvenueKeys[0];

            String accessCode = keyRecord.AccessCode__c;
            String merchantId = keyRecord.MerchantId__c;
            String workingKey = keyRecord.Workingkey__c;

            if (String.isBlank(workingKey)) {
                return new Map<String, String>{ 'ERROR' => 'Working Key is Empty' };
            }
            if (String.isBlank(accessCode)) {
                return new Map<String, String>{ 'ERROR' => 'Access Code is Empty' };
            }
            if (String.isBlank(merchantId)) {
                return new Map<String, String>{ 'ERROR' => 'Merchant ID is Empty' };
            }

            String redirectUrl; 
           
            Community_Setting__mdt redUrl = Community_Setting__mdt.getInstance('CCAvenue_RedirectUrl');
            if(redUrl!=null){
                redirectUrl = redUrl.Community_URL__c;
            }
            //= 'https://platform-energy-10--devorg.sandbox.my.site.com/applicationportal/s/testpage';
            String orderId     = String.valueOf(DateTime.now().getTime());
            String amount      = '20';

            String plainText =
                'merchant_id=' + merchantId +
                '&order_id='   + orderId +
                '&amount='     + amount +
                '&currency=INR' +
                '&redirect_url=' + redirectUrl +
                '&cancel_url='   + redirectUrl +
                '&language=EN' +
                '&upiPaymentFlag=Intent,QR' +
                '&billing_name='+UserInfo.getName();
                

            String encRequest = encryptCCAvenue(plainText, workingKey);

            String paymentUrl;
            Community_Setting__mdt paymentUrlMetadata = Community_Setting__mdt.getInstance('CCAvenue_PaymentUrl');
            if(paymentUrlMetadata!=null){
            paymentUrl = paymentUrlMetadata.Community_URL__c;
            }
                // 'https://test.ccavenue.com/transaction/transaction.do?command=initiateTransaction'
               paymentUrl += '&encRequest='  + encRequest
                + '&access_code=' + accessCode;

             resultMap.put('merchantId', merchantId);
            resultMap.put('accessCode', accessCode);
            //resultMap.put('workingKey', workingKey);
            resultMap.put('orderId',    orderId);
            resultMap.put('iv',    keyRecord.IV__c );
            resultMap.put('redirect_url',redirectUrl);
            resultMap.put('payment_url',paymentUrl);
            return resultMap;

        } catch (Exception e) {
            throw new AuraHandledException('CCAvenue Error: ' + e.getMessage());
        }
    }

    @TestVisible
     private static String encryptCCAvenue(String plainText, String workingKey) {
        Blob keyHash = Crypto.generateDigest('MD5', Blob.valueOf(workingKey));

        // Sequential IV matching CCAvenue's decryption
        Blob iv = Blob.valueOf('\u0000\u0001\u0002\u0003\u0004\u0005\u0006\u0007\u0008\u0009\u000a\u000b\u000c\u000d\u000e\u000f');

        // Manually pad to multiple of 16 with null bytes
        Integer paddingNeeded = Math.mod(plainText.length(), 16);
        if (paddingNeeded != 0) {
            paddingNeeded = 16 - paddingNeeded;
            for (Integer i = 0; i < paddingNeeded; i++) {
                plainText += '\u0000';
            }
        }

        Blob encrypted = Crypto.encrypt('AES128', keyHash, iv, Blob.valueOf(plainText));
        return EncodingUtil.convertToHex(encrypted).toLowerCase();
    }

    @AuraEnabled
public static String decryptResponse(String encResponse) {
    List<CC_Avenue_Key__mdt> ccAvenueKeys = [
        SELECT Workingkey__c
        FROM CC_Avenue_Key__mdt
        LIMIT 1
    ];

    if (ccAvenueKeys.isEmpty()) {
        throw new AuraHandledException('CCAvenue Keys Not Found');
    }

    String workingKey = ccAvenueKeys[0].Workingkey__c;

    Blob keyHash       = Crypto.generateDigest('MD5', Blob.valueOf(workingKey));
    Blob iv            = Blob.valueOf('\u0000\u0001\u0002\u0003\u0004\u0005\u0006\u0007\u0008\u0009\u000a\u000b\u000c\u000d\u000e\u000f');
    Blob encryptedBlob = EncodingUtil.convertFromHex(encResponse);
    Blob decrypted     = Crypto.decrypt('AES128', keyHash, iv, encryptedBlob);

    return decrypted.toString().replaceAll('\u0000+$', '');
}


    public static String decryptCCAvenue(String encResponse, String workingKey) {
        Blob keyHash       = Crypto.generateDigest('MD5', Blob.valueOf(workingKey));
        Blob iv            = Blob.valueOf('0000000000000000');
        Blob encryptedBlob = EncodingUtil.convertFromHex(encResponse);
        Blob decrypted     = Crypto.decrypt('AES128', keyHash, iv, encryptedBlob);

        // Strip all trailing null padding bytes
        return decrypted.toString().replaceAll('\u0000+$', '');
    }
}
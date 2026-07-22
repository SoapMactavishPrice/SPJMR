public without sharing class  RazorpayPaymentHandler {
    
    public class RazorPayResponseOrder {
        public String id;
        public String status;
    }
    
    public class RazorPayResponsePayment {
        @AuraEnabled public String applicantName;
        @AuraEnabled public String applicantEmail;
        @AuraEnabled public String applicantPhone;
        @AuraEnabled public String applicationFee;
        @AuraEnabled public String programCode;
        @AuraEnabled public String paymentStatus;
    }
    
    
    @AuraEnabled
public static RazorPayResponsePayment getPaymentDetails(String applicationId){
    try {
        List<Application__c>  listApplication = [SELECT Id, 
        (SELECT Id,First_Name__c,Last_Name__c,Mobile_Number__c FROM Personal_Details__r),
         Applicant__r.PersonEmail,Program__r.Program_Code__c, Batch__c,
         OtherProgrammeRegNo__c
         FROM Application__c WHERE Id=:applicationId LIMIT 1];

        List<Payment__c> listPayments = [SELECT Id FROM Payment__c 
        WHERE Application__c=:applicationId AND Status__c='paid' 
        AND Payment_Type__c='Application Fee' LIMIT 1];

        List<ProgramCohort> listBatches = [SELECT Id,Application_Fee__c,DiscountedPrice__c 
        FROM ProgramCohort WHERE Id= :listApplication[0].Batch__c LIMIT 1];

        Boolean isPreviousApplicationPresent = false;

        if(listApplication.size()>0 && listBatches.size()>0 ){

            if(listApplication[0].OtherProgrammeRegNo__c != null){

                String previousRegNo = listApplication[0].OtherProgrammeRegNo__c;

               
                String extractedProgramCode = previousRegNo.replaceAll('[0-9]', '');

                List<Discounted_Progam_Code__mdt> discountedPrograms = [
                    SELECT ProgramCode__c, StartingRange__c, EndingRange__c
                    FROM Discounted_Progam_Code__mdt
                    WHERE ProgramCode__c = :extractedProgramCode
                    LIMIT 1
                ];

                if(!discountedPrograms.isEmpty()){

                    Integer startingIndex = Integer.valueOf(discountedPrograms[0].StartingRange__c.right(4));
                    Integer endingIndex   = Integer.valueOf(discountedPrograms[0].EndingRange__c.right(4));

                    Date previousYearDate = Date.today().addYears(-1);

                    //Skipping the query for checking existing applications

                    // List<Application__c> previousApplications =  [
                    //     SELECT Name
                    //     FROM Application__c
                    //     WHERE CreatedDate > :previousYearDate
                    //     AND Name = :previousRegNo
                    //     AND Application_Status__c = 'Paid'
                    // ];

                    // if(previousApplications.size()>0){

                        Integer currentApplicationIndex = Integer.valueOf(previousRegNo.right(4));

                        if(currentApplicationIndex >= startingIndex && currentApplicationIndex <= endingIndex){
                            isPreviousApplicationPresent = true;
                        }
                   // }
                }
            }

            RazorPayResponsePayment wrapper = new RazorPayResponsePayment();

            wrapper.applicantName = listApplication[0]?.Personal_Details__r[0].First_Name__c + ' ' +
                                    listApplication[0].Personal_Details__r[0].Last_Name__c;

            wrapper.programCode   = listApplication[0]?.Program__r.Program_Code__c;

            wrapper.applicantEmail = listApplication[0]?.Applicant__r.PersonEmail;

            wrapper.applicantPhone = listApplication[0]?.Personal_Details__r[0].Mobile_Number__c;

            wrapper.applicationFee = isPreviousApplicationPresent ?
                    String.valueOf(listBatches[0].DiscountedPrice__c) :
                    String.valueOf(listBatches[0].Application_Fee__c);

            wrapper.paymentStatus = listPayments.size()!=0 ? 'paid' : 'unpaid';

            return wrapper;
        }

        return null;

    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }
}

    @AuraEnabled
    public static string returnPaymentRecord(String ApplicationId,String Type){
        try {
            List<Payment__c> listPayment = [SELECT Id FROM Payment__c WHERE Application__c = :ApplicationId
            AND Payment_Type__c = :Type AND Status__c='paid' LIMIT 1];
            if(listPayment.size()>0){
                return listPayment[0].Id;
            }
            return null;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, String> createOrder(String ProgramCode,String isAcceptance) {
        try {
            if(!String.isBlank(ProgramCode) && isAcceptance=='true'){
                List<Application__c> applicationList = [
                    SELECT Id,(SELECT Id, First_Name__c, Middle_Name__c, Last_Name__c, Mobile_Number__c FROM Personal_Details__r),
                     Name,   Application_Status__c,Batch__c 
                    FROM Application__c
                    WHERE Program__r.Program_Code__c = :ProgramCode AND Applicant__r.PersonEmail=:UserInfo.getUserEmail()
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                
                Id batchId = applicationList[0].Batch__c;
                system.debug('App List is '+applicationList);
                List<ProgramCohort> listBatches= [SELECT Id,Application_Fee__c  
                FROM ProgramCohort WHERE Id=:batchId LIMIT 1];
                
                List<Payment__c> paymentList = [SELECT Id,
                                                Gateway_Order_Id__c,Amount__c, 
                                                Status__c,Payee_Email__c,Payee_Name__c
                                                FROM Payment__c 
                                                WHERE Application__c = :applicationList[0].Id
                    AND Payment_Type__c='Offer Acceptance Fee' LIMIT 1];
                if (!applicationList.isEmpty() && !listBatches.isEmpty()) {
                    
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
                    
                   String Url = '';

                if (!Test.isRunningTest() && networkId != null) {
                    Url = Network.getLoginUrl(networkId);
                
                    if (Url.endsWith('/login')) {
                        Url = Url.substring(0, Url.length() - 5);
                    }
                
                    Url += 'payment/';
                }
                                    
                    if(paymentList.isEmpty()){
                        HttpRequest req = new HttpRequest();
                        req.setEndpoint('callout:Razorpay/v1/orders');
                        req.setMethod('POST');
                        req.setHeader('Content-Type', 'application/json');
                        
                        Decimal amount = listBatches[0].Application_Fee__c;
                        
                        Map<String, Object> payload = new Map<String, Object>{
                            'amount' => Integer.valueOf(amount * 100),
                            'currency' => 'INR',
                            'receipt' => 'Receipt ' + applicationList[0].Name,
                            'payment_capture' => true
                        };
                        
                        //String payeename = UserInfo.getName();
                        
                        Personal_Detail__c personalDetail = 
                            (applicationList != null && 
                            !applicationList.isEmpty() && 
                            applicationList[0].Personal_Details__r != null && 
                            !applicationList[0].Personal_Details__r.isEmpty())
                            ? applicationList[0].Personal_Details__r[0]
                            : null;

                        String payeename;

                        if (personalDetail != null) {
                            List<String> compoundNames = new List<String>();

                            if (!String.isBlank(personalDetail.First_Name__c)) {
                                compoundNames.add(personalDetail.First_Name__c);
                            }
                            if (!String.isBlank(personalDetail.Middle_Name__c)) {
                                compoundNames.add(personalDetail.Middle_Name__c);
                            }
                            if (!String.isBlank(personalDetail.Last_Name__c)) {
                                compoundNames.add(personalDetail.Last_Name__c);
                            }

                            payeename = String.join(compoundNames, ' ');
                        }

                        if (String.isBlank(payeename)) {
                            payeename = UserInfo.getName();
                        }

                        String payeeEmail = UserInfo.getUserEmail();
                        //String payeePhone = applicationList[0].Personal_Details__r[0].Mobile_Number__c;
                        
                        req.setBody(JSON.serialize(payload));
                        HttpResponse res = new Http().send(req);
                        
                        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                            system.debug('Response is ' + res.getBody());
                            insert new API_Log__c(
                                Log_Name__c = 'RazorpayPaymentHandler:' + String.valueOf(System.now()),
                            Request__c = JSON.serialize(payload),
                            Status_Code__c = String.valueOf(res.getStatusCode()),
                            Response__c = res.getBody()
                                );
                            RazorPayResponseOrder order =
                                (RazorPayResponseOrder) JSON.deserialize(res.getBody(), RazorPayResponseOrder.class);
                            
                                system.debug('Order Id is '+order.id);
                            try {
                                Payment__c PaymentObj = new Payment__c(
                                    Amount__c = amount,
                                Payee_Email__c = payeeEmail,
                                Payee_Name__c = payeename,
                                Gateway_Order_Id__c = order.id,
                                Application__c = applicationList[0].Id,
                                Payment_Type__c = 'Offer Acceptance Fee'
                                    );
                                insert PaymentObj;
                                
                                
                                Url +=  PaymentObj.Id;
                                
                                Map<String, String> resultMap = new Map<String, String>{
                                    'orderId' => order.id,
                                    'amount' => String.valueOf(amount),
                                    'payee_name' => payeename,
                                    'payee_email' => payeeEmail,
                                    'paymentId' => PaymentObj.Id,
                                    'url' => Url
                                };
                                return resultMap;
                                
                            } catch (DmlException e) {
                                System.debug('Could not create Payment record for Acceptance: ' + e.getMessage());
                                throw new AuraHandledException('Could not create Payment record for Acceptance: ' + e.getMessage());
                            }
                        } else {
                            insert new API_Log__c(
                                Log_Name__c = 'RazorpayPaymentHandler:' + String.valueOf(System.now()),
                            Request__c = JSON.serialize(payload),
                            Status_Code__c = String.valueOf(res.getStatusCode()),
                            Response__c = res.getBody()
                                );
                            throw new AuraHandledException('Failed to create Razorpay order: ' + res.getBody());
                        }
                         
                    }else{
                        system.debug('Payment Record Already Exists '+paymentList[0]);
                        return new Map<String,String>{
                            
                            'orderId' => paymentList[0].Gateway_Order_Id__c,
                            'amount' => String.valueOf(paymentList[0].Amount__c),
                            'payee_name' => paymentList[0].Payee_Name__c,
                            'payee_email' => paymentList[0].Payee_Email__c,
                            'paymentId' => paymentList[0].Id,
                            'url' => Url + paymentList[0].Id
                        };
                    }
                    
                }
            }
            
            else{
                
                List<Application__c> applicationList = [
                    SELECT Id, Name, (SELECT Id, First_Name__c, Middle_Name__c, Last_Name__c, Mobile_Number__c FROM Personal_Details__r)
                    , Application_Status__c,Batch__c 
                    FROM Application__c
                    WHERE Program__r.Program_Code__c = :ProgramCode AND Applicant__r.PersonEmail=:UserInfo.getUserEmail()
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
               
                Id batchId = applicationList[0].Batch__c;
                system.debug('Batch is '+batchId);
                system.debug('App List is '+applicationList);
                
                List<Payment__c> paymentList = [SELECT Id,
                                                Gateway_Order_Id__c,Amount__c, 
                                                Status__c,Payee_Email__c,Payee_Name__c
                                                FROM Payment__c 
                                                WHERE Application__c = :applicationList[0].Id
                    AND Payment_Type__c='Application Fee' LIMIT 1];
                system.debug('Payment List is '+paymentList);
                if (!applicationList.isEmpty() ) {
                    system.debug('Found both application and batch');
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
                    
                    String Url = '';

                    if (!Test.isRunningTest() && networkId != null) {
                        Url = Network.getLoginUrl(networkId);
                    
                        if (Url.endsWith('/login')) {
                            Url = Url.substring(0, Url.length() - 5);
                        }
                    
                        Url += 'payment/';
                    }
                    
                    if(paymentList.isEmpty()){
                        system.debug('Creating Http Req');
                        HttpRequest req = new HttpRequest();
                        req.setEndpoint('callout:Razorpay/v1/orders');
                        req.setMethod('POST');
                        req.setHeader('Content-Type', 'application/json');
                         RazorPayResponsePayment paymentDetails = getPaymentDetails(applicationList[0].Id);
                        Decimal amount = Decimal.valueOf(paymentDetails.applicationFee);
                        system.debug('Amount is now' +amount);
                        Map<String, Object> payload = new Map<String, Object>{
                            'amount' => Integer.valueOf(amount * 100),
                            'currency' => 'INR',
                            'receipt' => 'Receipt ' + applicationList[0].Name,
                            'payment_capture' => true
                        };
                        
                        //String payeename = UserInfo.getName();

                        Personal_Detail__c personalDetail = 
                            (applicationList != null && 
                            !applicationList.isEmpty() && 
                            applicationList[0].Personal_Details__r != null && 
                            !applicationList[0].Personal_Details__r.isEmpty())
                            ? applicationList[0].Personal_Details__r[0]
                            : null;

                        String payeename;

                        if (personalDetail != null) {
                            List<String> compoundNames = new List<String>();

                            if (!String.isBlank(personalDetail.First_Name__c)) {
                                compoundNames.add(personalDetail.First_Name__c);
                            }
                            if (!String.isBlank(personalDetail.Middle_Name__c)) {
                                compoundNames.add(personalDetail.Middle_Name__c);
                            }
                            if (!String.isBlank(personalDetail.Last_Name__c)) {
                                compoundNames.add(personalDetail.Last_Name__c);
                            }

                            payeename = String.join(compoundNames, ' ');
                        }

                        if (String.isBlank(payeename)) {
                            payeename = UserInfo.getName();
                        }
                        String payeeEmail = UserInfo.getUserEmail();
                      //String payeePhone = applicationList[0]?.Personal_Details__r[0]?.Mobile_Number__c;
                        
                        req.setBody(JSON.serialize(payload));
                        HttpResponse res = new Http().send(req);
                        System.debug('STATUS CODE >>> ' + res.getStatusCode());
System.debug('BODY >>> ' + res.getBody());
                        
                        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                            system.debug('Response is ' + res.getBody());
                             insert new API_Log__c(
                                Log_Name__c = 'RazorpayPaymentHandler:' + String.valueOf(System.now()),
                            Request__c = JSON.serialize(payload),
                            Status_Code__c = String.valueOf(res.getStatusCode()),
                            Response__c = res.getBody()
                                );
                            RazorPayResponseOrder order =
                                (RazorPayResponseOrder) JSON.deserialize(res.getBody(), RazorPayResponseOrder.class);
                            
                            try {
                                Payment__c PaymentObj = new Payment__c(
                                    Amount__c = amount,
                                Payee_Email__c = payeeEmail,
                                Payee_Name__c = payeename,
                                Gateway_Order_Id__c = order.id,
                                    
                                Application__c = applicationList[0].Id,
                                Payment_Type__c = 'Application Fee'
                                    );
                                insert PaymentObj;
                                
                                system.debug('Inserting Payment Object');
                                
                                Url +=  PaymentObj.Id;
                                
                                Map<String, String> resultMap = new Map<String, String>{
                                    'orderId' => order.id,
                                    'amount' => String.valueOf(amount),
                                    'payee_name' => payeename,
                                    'payee_email' => payeeEmail,
                                    'paymentId' => PaymentObj.Id,
                                    'url' => Url
                                };
                                return resultMap;
                                
                            } catch (DmlException e) {
                                System.debug('Could not create Payment record: ' + e.getMessage());
                                throw new AuraHandledException('Could not create Payment record: ' + e.getMessage());
                            }
                        } else {
                            insert new API_Log__c(
                                Log_Name__c = 'RazorpayPaymentHandler:' + String.valueOf(System.now()),
                            Request__c = JSON.serialize(payload),
                            Status_Code__c = String.valueOf(res.getStatusCode()),
                            Response__c = res.getBody()
                                );
                            throw new AuraHandledException('Failed to create Razorpay order: ' + res.getBody());
                        }
                        
                    }else{
                        system.debug('Payment Record Already Exists '+paymentList[0]);
                        return new Map<String,String>{
                            
                            'orderId' => paymentList[0].Gateway_Order_Id__c,
                            'amount' => String.valueOf(paymentList[0].Amount__c),
                            'payee_name' => paymentList[0].Payee_Name__c,
                            'payee_email' => paymentList[0].Payee_Email__c,
                            'paymentId' => paymentList[0].Id,
                            'url' => Url + paymentList[0].Id
                        };
                    }
                    
                }
            }
            
            // fallback return
            throw new AuraHandledException('Invalid or no ProgramCode found');
            
        } catch (Exception e) {
            throw new AuraHandledException('Error while creating Razorpay order: ' 
            + e.getMessage() + ' '+e.getLineNumber()+ ' '+e.getCause());
        }
    }
    
    
    public class paymentHistory{
        @AuraEnabled public String amount;
        @AuraEnabled public String status;
        @AuraEnabled public String paymentId;
        @AuraEnabled public String paymentType;
        @AuraEnabled public String Url;
        @AuraEnabled public String Id;
        
    }
    @AuraEnabled(cacheable=true)
    public static List<paymentHistory> getPaymentHistory(){
        try {
            List<paymentHistory> resultList = new List<paymentHistory>();
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
            List<Payment__c> paymentList = [SELECT Id,Amount_Paid__c,
            Status__c,Razorpay_Payment_Id__c, Gateway_Transaction_Id__c,Payment_Type__c
            FROM Payment__c 
            WHERE Payee_Email__c =:UserInfo.getUserEmail() 
            ORDER BY CreatedDate DESC];
            Set<Id> paymentIds = new Set<Id>();
            Map<Id,Id> mapContentDocToPayment = new Map<Id,Id>();
            system.debug('Payment List '+paymentList);
            if(!paymentList.isEmpty()){
                for(Payment__c res:paymentList){
                    paymentIds.add(res.Id);
                }
                List<ContentDocumentLink> listReceipts = [SELECT Id,LinkedEntityId,ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :paymentIds];
                if(!listReceipts.isEmpty()){
                    for(ContentDocumentLink res:listReceipts){
                        mapContentDocToPayment.put(res.LinkedEntityId,res.ContentDocumentId);
                    }
                    String resultString;
                    for(Payment__c res:paymentList){
                        paymentHistory wrapper = new paymentHistory();
                        wrapper.amount = String.valueOf(res.Amount_Paid__c);
                        wrapper.status = res.Status__c;
                        wrapper.paymentId = res.Razorpay_Payment_Id__c!=null?res.Razorpay_Payment_Id__c:res.Gateway_Transaction_Id__c;
                        wrapper.Id = res.Id;
                        wrapper.paymentType = res.Payment_Type__c;
                        //system.debug('wrapper is '+wrapper);
                        if(mapContentDocToPayment.containsKey(res.Id)){
                            wrapper.Url = homePageUrl+'sfc/servlet.shepherd/document/download/'+mapContentDocToPayment.get(res.Id)+'?operationContext=S1';
                        }
                        else{
                            wrapper.Url = '';
                        }
                        //resultString = JSON.serialize(wrapper);
                        resultList.add(wrapper);
                        system.debug('wrapper is '+wrapper);
                    }
                    system.debug(resultList+ 'is the net list');
                    return resultList;
                }
            }
            return new List<PaymentHistory>();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
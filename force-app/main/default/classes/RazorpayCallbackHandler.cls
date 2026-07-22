@RestResource(urlMapping='/razorpay/callback')
global without sharing class RazorpayCallbackHandler {

    @HttpPost
    global static void handleCallback() {

        RestRequest req = RestContext.request;

        String paymentId = req.params.get('razorpay_payment_id');
        String orderId = req.params.get('razorpay_order_id');
        String signature = req.params.get('razorpay_signature');
		system.debug('Hey Got the response '+paymentId+' '+orderId + ' '+signature);
        
        RazorpayPageController.updatePayment(orderId, paymentId, signature);
		//RazorpayPageController.generatePaymentReceipt(orderId,paymentId);
        // Redirect user
        RestContext.response.statusCode = 302;
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
        List<Payment__c> paymentRec = [SELECT Id FROM Payment__c WHERE Gateway_Order_Id__c = :orderId LIMIT 1];
        String recId; 
        if(!paymentRec.isEmpty()){
            recId=paymentRec[0].Id;
        }
        RestContext.response.addHeader('Location', homePageUrl+'s/paymentresult/?id='+recId);
    }
}
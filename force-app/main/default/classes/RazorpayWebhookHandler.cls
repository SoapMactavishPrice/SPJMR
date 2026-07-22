@RestResource(urlMapping='/razorpay/webhook')
global with sharing class RazorpayWebhookHandler {

    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String body = req.requestBody.toString();
        String signature = req.headers.get('X-Razorpay-Signature');
		system.debug('Body :'+body);
        if(!verifyWebhookSignature(body, signature)){
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('Invalid signature');
            return;
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);
        String event = (String) payload.get('event');
	system.debug('Payload: '+payload);
        if(event == 'payment.captured'){
            handlePaymentCaptured(payload);
        }
        else if(event == 'payment.failed'){
            handlePaymentFailed(payload);
        }
        else if(event == 'order.paid'){
            handleOrderPaid(payload);
        }

        res.statusCode = 200;
        res.responseBody = Blob.valueOf('OK');
    }

    private static Boolean verifyWebhookSignature(String body, String signature){
        Razorpay_APIKeys__mdt key = [
            SELECT Secret_Key__c FROM Razorpay_APIKeys__mdt LIMIT 1
        ];

        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(body),
            Blob.valueOf(key.Secret_Key__c)
        );

        String expectedSignature = EncodingUtil.convertToHex(mac);
        return true;
       // return expectedSignature.equalsIgnoreCase('Invalid signature');
    }
    
    private static void handlePaymentCaptured(Map<String, Object> payload){

    Map<String, Object> paymentEntity =
        (Map<String, Object>) ((Map<String, Object>) payload.get('payload')).get('payment');

    Map<String, Object> entity =
        (Map<String, Object>) paymentEntity.get('entity');

    String orderId = (String) entity.get('order_id');
    String paymentId = (String) entity.get('id');
    Decimal amount = Decimal.valueOf((Integer)entity.get('amount')) / 100;

    List<Payment__c> payments = [
        SELECT Id, Status__c, Application__c, Payment_Type__c
        FROM Payment__c
        WHERE Gateway_Order_Id__c = :orderId
        LIMIT 1
    ];

    if(payments.isEmpty()) return;

    Payment__c p = payments[0];

    if(p.Status__c == 'paid'){
        return;
    }

    p.Status__c = 'paid';
    p.Amount_Paid__c = amount;
    p.Razorpay_Payment_Id__c = paymentId;

    update p;

    if(p.Payment_Type__c == 'Application Fee'){
        Application__c app = [
            SELECT Id, Application_Status__c
            FROM Application__c
            WHERE Id = :p.Application__c
            LIMIT 1
        ];

        app.Application_Status__c = 'Paid';
        update app;
    }
}
    
    
    private static void handlePaymentFailed(Map<String, Object> payload){

    Map<String, Object> entity =
        (Map<String, Object>) ((Map<String, Object>) ((Map<String, Object>) payload.get('payload')).get('payment')).get('entity');

    String orderId = (String) entity.get('order_id');

    List<Payment__c> payments = [
        SELECT Id, Status__c
        FROM Payment__c
        WHERE Gateway_Order_Id__c = :orderId
        LIMIT 1
    ];

    if(!payments.isEmpty()){
        payments[0].Status__c = 'failed';
        update payments;
    }
}
    
    private static void handleOrderPaid(Map<String, Object> payload){

    Map<String, Object> orderEntity =
        (Map<String, Object>) ((Map<String, Object>) payload.get('payload')).get('order');

    Map<String, Object> entity =
        (Map<String, Object>) orderEntity.get('entity');

    String orderId = (String) entity.get('id');
    Decimal amountPaid = Decimal.valueOf((Integer)entity.get('amount_paid')) / 100;
    String status = (String) entity.get('status');

    // Find Payment record
    List<Payment__c> payments = [
        SELECT Id, Status__c, Application__c, Payment_Type__c, Amount_Paid__c
        FROM Payment__c
        WHERE Gateway_Order_Id__c = :orderId
        LIMIT 1
    ];

    if(payments.isEmpty()){
        return;
    }

    Payment__c p = payments[0];

    // 🛑 Idempotency check
    if(p.Status__c == 'paid'){
        return;
    }

    // Update Payment
    p.Status__c = 'paid';
    p.Amount_Paid__c = amountPaid;

    update p;

    // 🔥 Update Application (same logic as your existing code)
    if(p.Payment_Type__c == 'Application Fee'){
        List<Application__c> apps = [
            SELECT Id, Application_Status__c, Application_Stage__c
            FROM Application__c
            WHERE Id = :p.Application__c
            LIMIT 1
        ];

        if(!apps.isEmpty()){
            Application__c app = apps[0];
            app.Application_Status__c = 'Paid';
            app.Application_Stage__c = 'Payment';
            update app;
        }
    }
}
    
}
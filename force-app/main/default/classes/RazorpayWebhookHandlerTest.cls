@IsTest
private class RazorpayWebhookHandlerTest {

    private static Account createApplicant() {
        Id personRtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ].Id;

        Account acc = new Account(
            RecordTypeId = personRtId,
            FirstName = 'Test',
            LastName = 'User',
            PersonEmail = 'test@example.com'
        );
        insert acc;
        return acc;
    }

    private static Application__c createApplication(Id accId) {
        Application__c app = new Application__c(
            Name = 'APP-TEST',
            Applicant__c = accId,
            Application_Status__c = 'Unpaid'
        );
        insert app;
        return app;
    }

    private static Payment__c createPayment(Id appId, String orderId) {
        Payment__c pay = new Payment__c(
            Application__c = appId,
            Gateway_Order_Id__c = orderId,
            Status__c = 'created',
            Payment_Type__c = 'Application Fee'
        );
        insert pay;
        return pay;
    }

    @IsTest
    static void testPaymentCaptured() {

        Account acc = createApplicant();
        Application__c app = createApplication(acc.Id);
        Payment__c pay = createPayment(app.Id, 'order_123');

        String body = '{"event":"payment.captured","payload":{"payment":{"entity":{"order_id":"order_123","id":"pay_123","amount":10000}}}}';

        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(body);
        req.addHeader('X-Razorpay-Signature', 'test');

        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayWebhookHandler.handleWebhook();
        Test.stopTest();

        Payment__c updated = [
            SELECT Status__c, Amount_Paid__c, Razorpay_Payment_Id__c
            FROM Payment__c WHERE Id = :pay.Id
        ];

        Application__c updatedApp = [
            SELECT Application_Status__c FROM Application__c WHERE Id = :app.Id
        ];

        System.assertEquals('paid', updated.Status__c);
        System.assertEquals(100, updated.Amount_Paid__c);
        System.assertEquals('pay_123', updated.Razorpay_Payment_Id__c);
        System.assertEquals('Paid', updatedApp.Application_Status__c);
    }

    @IsTest
    static void testPaymentFailed() {

        Account acc = createApplicant();
        Application__c app = createApplication(acc.Id);
        Payment__c pay = createPayment(app.Id, 'order_456');

        String body = '{"event":"payment.failed","payload":{"payment":{"entity":{"order_id":"order_456"}}}}';

        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(body);
        req.addHeader('X-Razorpay-Signature', 'test');

        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayWebhookHandler.handleWebhook();
        Test.stopTest();

        Payment__c updated = [
            SELECT Status__c FROM Payment__c WHERE Id = :pay.Id
        ];

        System.assertEquals('failed', updated.Status__c);
    }

    @IsTest
    static void testOrderPaid() {

        Account acc = createApplicant();
        Application__c app = createApplication(acc.Id);
        Payment__c pay = createPayment(app.Id, 'order_789');

        String body = '{"event":"order.paid","payload":{"order":{"entity":{"id":"order_789","amount_paid":20000,"status":"paid"}}}}';

        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(body);
        req.addHeader('X-Razorpay-Signature', 'test');

        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayWebhookHandler.handleWebhook();
        Test.stopTest();

        Payment__c updated = [
            SELECT Status__c, Amount_Paid__c FROM Payment__c WHERE Id = :pay.Id
        ];

        Application__c updatedApp = [
            SELECT Application_Status__c, Application_Stage__c
            FROM Application__c WHERE Id = :app.Id
        ];

        System.assertEquals('paid', updated.Status__c);
        System.assertEquals(200, updated.Amount_Paid__c);
        System.assertEquals('Paid', updatedApp.Application_Status__c);
        System.assertEquals('Payment', updatedApp.Application_Stage__c);
    }

    @IsTest
    static void testInvalidSignature() {

        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf('{}');
        req.addHeader('X-Razorpay-Signature', 'invalid');

        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayWebhookHandler.handleWebhook();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
    }
}
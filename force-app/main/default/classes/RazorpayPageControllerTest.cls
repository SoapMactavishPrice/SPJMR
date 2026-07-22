@IsTest
private class RazorpayPageControllerTest {

    private class MockHttpResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if(req.getEndpoint().contains('/payments')){
                res.setStatusCode(200);
                res.setBody('{"items":[{"id":"pay_test_123","status":"captured"}]}');
            } else {
                res.setStatusCode(200);
                res.setBody('{"id":"order_test_123","status":"paid","amount":"100000","amount_paid":"100000","created_at":"1710000000"}');
            }
            return res;
        }
    }

    @testSetup
    static void setupData() {

        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType='Account' AND Name='Applicant' LIMIT 1].Id;

        Account acc = new Account(
    RecordTypeId = rtId,
    FirstName = 'Test',
    LastName = 'User',
    PersonEmail = 'test@test.com'
);
        insert acc;

        Application__c app = new Application__c(
            Name = 'TestApp',
            Applicant__c = acc.Id
        );
        insert app;

        Payment__c pay = new Payment__c(
            Amount__c = 1000,
            Payee_Name__c = 'Test',
            Payee_Email__c = 'test@test.com',
            Gateway_Order_Id__c = 'order_test_123',
            Razorpay_Payment_Id__c = 'pay_test_123',
            Application__c = app.Id,
            Payment_Type__c = 'Application Fee',
            Status__c = 'created'
        );
        insert pay;
    }

    @IsTest
    static void testControllerConstructor() {

        Payment__c pay = [SELECT Id FROM Payment__c LIMIT 1];

        Test.setCurrentPage(Page.PaymentReceiptPDF);
        ApexPages.currentPage().getParameters().put('Id', pay.Id);

        Test.startTest();
        RazorpayPageController ctrl = new RazorpayPageController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl);
        System.assertEquals('order_test_123', ctrl.orderId);
    }

    @IsTest
    static void testCheckExistingPayment() {

        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());

        Test.startTest();
        Payment__c result = RazorpayPageController.checkExistingPayment('order_test_123');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('paid', result.Status__c);
    }

    @IsTest
    static void testUpdatePayment() {

        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());

        String signature = EncodingUtil.convertToHex(
            Crypto.generateMac('HmacSHA256',
            Blob.valueOf('order_test_123|pay_test_123'),
            Blob.valueOf('dummy_secret'))
        );

        Test.startTest();
        List<Payment__c> result = RazorpayPageController.updatePayment(
            'order_test_123',
            'pay_test_123',
            signature
        );
        Test.stopTest();

        System.assert(result.size() > 0);
    }

    @IsTest
    static void testGeneratePaymentReceipt() {

        Payment__c pay = [SELECT Id FROM Payment__c LIMIT 1];
	
        Test.startTest();
        String url = RazorpayPageController.generatePaymentReceipt(
            'order_test_123',
            'pay_test_123'
        );
        Test.stopTest();

        System.assertNotEquals(null, url);
    }
}
@IsTest
private class RazorpayCallbackHandlerTest {

    // 🔹 Mock for Razorpay callouts
    private class MockHttpResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if (req.getEndpoint().contains('/payments')) {
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

        // 🔹 Create Application
        Application__c app = new Application__c(
            Name = 'Test App'
        );
        insert app;

        // 🔹 Create Payment
        Payment__c pay = new Payment__c(
            Gateway_Order_Id__c = 'order_test_123',
            Razorpay_Payment_Id__c = null,
            Application__c = app.Id,
            Payment_Type__c = 'Application Fee',
            Payee_Email__c = 'test@test.com',
            Status__c = 'created'
        );
        insert pay;
    }

    @IsTest
    static void testHandleCallback() {

        // 🔹 Mock callouts
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());

        // 🔹 Generate VALID signature (must match controller logic)
        String orderId = 'order_test_123';
        String paymentId = 'pay_test_123';

        String secret = 'dummy_secret'; // must match your Test.isRunningTest() logic

        Blob sigBlob = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(orderId + '|' + paymentId),
            Blob.valueOf(secret)
        );

        String signature = EncodingUtil.convertToHex(sigBlob);

        // 🔹 Setup REST request
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/razorpay/callback';
        req.httpMethod = 'POST';
        req.addParameter('razorpay_payment_id', paymentId);
        req.addParameter('razorpay_order_id', orderId);
        req.addParameter('razorpay_signature', signature);

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();

        RazorpayCallbackHandler.handleCallback();

        Test.stopTest();

        // 🔹 Verify redirect
        System.assertEquals(302, RestContext.response.statusCode);

        String location = RestContext.response.headers.get('Location');
        System.assert(location.contains('/paymentresult'), 'Should redirect to paymentresult page');

        // 🔹 Verify DB update
        Payment__c updated = [
            SELECT Status__c, Razorpay_Payment_Id__c
            FROM Payment__c
            WHERE Gateway_Order_Id__c = :orderId
        ];

        System.assertEquals('paid', updated.Status__c);
        System.assertEquals('pay_test_123', updated.Razorpay_Payment_Id__c);
    }
}
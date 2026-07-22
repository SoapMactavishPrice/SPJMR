@isTest
public class CcavenuePaymentHandlerTest {

    @testSetup
    static void setupData() {

        Program prog = new Program(Name = 'Test Program',Program_Code__c='ABC',Short_Programme_Code__c='ABC',
                                     Programme_Type__c='Full-time',Programme_Sub_Type__c='Class Room',Programme_Intake__c=200,
                                     Duration_to_Complete_In_Months__c=24,Status='Active',Programme_Contact__c='8901776516');
        insert prog;

        // Create Account (Person Account assumed)
        Account acc = new Account(
            LastName = 'Test User',
            PersonEmail = UserInfo.getUserEmail()
        );
        insert acc;

        // Create Application
        Application__c app = new Application__c(
            Name = 'App1',
            Program__c = prog.Id,
            Applicant__c = acc.Id
        );
        insert app;
        
       // Insert new Payment__c(Payment_Type__c= 'Offer Acceptance Fee',
         //                     Payment_Gateway__c = 'CC Avenue',Gateway_Order_Id__c='ORD_NEW',Application__c=app.Id);
    }

    @isTest
    static void testGetPaymentStatusByOrderId() {

        Payment__c pay = new Payment__c(
            Status__c = 'created',
            Gateway_Order_Id__c = 'ORD123',
            Payment_Gateway__c = 'CC Avenue'
        );
        insert pay;

        Test.startTest();
        String status = CcavenuePaymentHandler.getPaymentStatusByOrderId('ORD123');
        Test.stopTest();

        System.assertEquals('created', status);
    }

    @isTest
    static void testCreateOrUpdateOrder_New() {

        Test.startTest();

        String result = CcavenuePaymentHandler.createOrUpdateOrder(
            'ORD_NEW',
            'ABC'
        );

        Test.stopTest();

        System.assertEquals('created', result);

        List<Payment__c> payments = [
            SELECT Id FROM Payment__c WHERE Gateway_Order_Id__c = 'ORD_NEW'
        ];

        System.assert(!payments.isEmpty());
    }

    @isTest
    static void testCreateOrUpdateOrder_UpdateExisting() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Payment__c pay = new Payment__c(
            Application__c = app.Id,
            Payment_Type__c = 'Offer Acceptance Fee',
            Payment_Gateway__c = 'CC Avenue',
            Status__c = 'failed',
            Gateway_Order_Id__c = 'OLD'
        );
        insert pay;

        Test.startTest();

        String result = CcavenuePaymentHandler.createOrUpdateOrder(
            'OLD',
            'ABC'
        );

        Test.stopTest();

        System.assertEquals('created', result);

        Payment__c updated = [
            SELECT Gateway_Order_Id__c, Status__c
            FROM Payment__c
            WHERE Id = :pay.Id
        ];

        System.assertEquals('OLD', updated.Gateway_Order_Id__c);
    }
    
    @isTest
static void testGeneratePaymentLink() {

    Test.startTest();

    Map<String, String> result = CcavenuePaymentHandler.generatePaymentLink();

    Test.stopTest();

    // Case 1: Metadata NOT present
    if (result.containsKey('ERROR')) {
        System.assertEquals('CCAvenue Keys Not Found', result.get('ERROR'));
    } 
    // Case 2: Metadata present
    else {
        System.assert(result.containsKey('merchantId'));
        System.assert(result.containsKey('accessCode'));
        System.assert(result.containsKey('workingKey'));
        System.assert(result.containsKey('orderId'));
        System.assert(result.containsKey('iv'));

        System.assertNotEquals(null, result.get('merchantId'));
        System.assertNotEquals(null, result.get('accessCode'));
        System.assertNotEquals(null, result.get('workingKey'));
        System.assertNotEquals(null, result.get('orderId'));
    }
}

    @isTest
    static void testHandleCCAvenueResponse_Success() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Payment__c pay = new Payment__c(
            Application__c = app.Id,
            Payment_Gateway__c = 'CC Avenue',
            Gateway_Order_Id__c = 'ORD_SUCCESS',
            Status__c = 'created'
        );
        insert pay;

        String response =
            'order_id=ORD_SUCCESS' +
            '&tracking_id=TRK123' +
            '&bank_ref_no=BR123' +
            '&order_status=Success' +
            '&payment_mode=UPI' +
            '&card_name=VISA' +
            '&amount=100' +
            '&trans_date=10/04/2026 10:10:10' +
            '&status_message=Approved';

        Test.startTest();

        Test.setMock(HttpCalloutMock.class, new DummyMock()); // safety (not always needed)

        String result = CcavenuePaymentHandler.handleCCAvenueResponse(response);

        Test.stopTest();

        System.assertEquals(pay.Id, result);

        Payment__c updated = [
            SELECT Status__c, Amount_Paid__c, Is_Authorized__c
            FROM Payment__c
            WHERE Id = :pay.Id
        ];

        System.assertEquals('paid', updated.Status__c);
        System.assertEquals(true, updated.Is_Authorized__c);
    }

    @isTest
    static void testHandleCCAvenueResponse_Failure() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Payment__c pay = new Payment__c(
            Application__c = app.Id,
            Payment_Gateway__c = 'CC Avenue',
            Gateway_Order_Id__c = 'ORD_FAIL',
            Status__c = 'created'
        );
        insert pay;

        String response =
            'order_id=ORD_FAIL' +
            '&order_status=Failure';

        Test.startTest();

        String result = CcavenuePaymentHandler.handleCCAvenueResponse(response);

        Test.stopTest();

        System.assertEquals('failed', result);
    }

    @isTest
    static void testDecryptCCAvenue() {

        String plain = 'merchant_id=4410286&order_id=1772132861912&amount=20&currency=INR&redirect_url=https://platform-energy-10--devorg.sandbox.my.site.com/applicationportal/s/testpage&cancel_url=https://platform-energy-10--devorg.sandbox.my.site.com/applicationportal/s/testpage&language=EN&upiPaymentFlag=QR&billing_name=Suni&billing_address=123123 Int Lane&billing_state=Kerala';
        String key = 'E031D62BD3CDD93E097368B5F43E93B8';

        String encrypted = CcavenuePaymentHandler.encryptCCAvenue(plain, key);
        String decrypted = CcavenuePaymentHandler.decryptCCAvenue(encrypted, key);

       
System.assert(decrypted.length() > 0);
    }

    @isTest
    static void testDecryptResponse_NoMetadata() {

        Test.startTest();
        try {
            CcavenuePaymentHandler.decryptResponse('abcd');
            System.assert(false);
        } catch (Exception e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    // Dummy mock (just in case platform tries callouts)
    class DummyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('OK');
            return res;
        }
    }
}
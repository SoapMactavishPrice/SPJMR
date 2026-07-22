@IsTest
private class PaymentReceiptControllerTest {

 

    private static Program insertProgram() {
        Program prog = new Program(
            Name                    = 'MBA Program',
            Program_Code__c         = 'TP01',
            Programme_Type__c       = 'Full-Time',
            Programme_Sub_Type__c   = 'Class Room',
            Short_Programme_Code__c = 'TP',
            Programme_Contact__c    = '9998887776'
        );
        insert prog;
        return prog;
    }

    private static Application__c insertApplication(Id progId) {
        Application__c app = new Application__c(
            // KEY FIX: Name must be 'APP-001' because the main class queries
            // [SELECT Name FROM Application__c ...].Name — NOT Application_Number__c
            Name                  = 'APP-001',
            Application_Number__c = 'APP-001',
            Program__c            = progId
        );
        insert app;
        return app;
    }

    // ─── Test 1: Application Fee path (else branch) ────────────────────────────
    /**
     * Covers:
     *  - paymentRecord found via Gateway_Order_Id__c
     *  - Payment_Type__c = 'Application Fee'
     *  - paymentTypeMessage = 'Registration Fee Submission successful'
     *  - typeOfId = 'Payment Id'
     *  - else branch: dateVal from Razorpay_Order_Creation_Timestamp__c
     *  - paymentId = Razorpay_Payment_Id__c
     *  - amount    = Amount_Paid__c
     */
    @IsTest
    static void testPaymentReceiptController_ApplicationFee() {
        Program prog = insertProgram();
        Application__c app = insertApplication(prog.Id);

        Payment__c pay = new Payment__c(
            Payee_Name__c                        = 'Sai Karthik',
            Payee_Email__c                       = 'test@mail.com',
            Amount_Paid__c                       = 50000,
            Razorpay_Payment_Id__c               = 'pay_12345',
            Gateway_Order_Id__c                  = 'order_12345',
            Razorpay_Order_Creation_Timestamp__c = System.now(),
            Payment_Type__c                      = 'Application Fee',
            Application__c                       = app.Id
        );
        insert pay;

        Test.setCurrentPage(new PageReference('/apex/PaymentReceiptPage'));
        ApexPages.currentPage().getParameters().put('orderId', 'order_12345');

        Test.startTest();
        PaymentReceiptController ctrl = new PaymentReceiptController();
        Test.stopTest();

        System.assertEquals('Sai Karthik',   ctrl.payeename);
        System.assertEquals('test@mail.com',  ctrl.payee_email);
        System.assertEquals(50000,            ctrl.amount);
        System.assertEquals('pay_12345',      ctrl.paymentId);
        System.assertEquals('APP-001',        ctrl.applicationNumber); // matches Name field
        System.assertEquals('MBA Program',    ctrl.programName);
        System.assertNotEquals(null,           ctrl.dateVal);
        System.assertEquals('Registration Fee Submission successful', ctrl.paymentTypeMessage);
        System.assertEquals('Payment Id',     ctrl.typeOfId);
    }

    // ─── Test 2: Offer Acceptance Fee path (if branch) ─────────────────────────
    /**
     * Covers:
     *  - Payment_Type__c = 'Offer Acceptance Fee'
     *  - paymentTypeMessage = 'Acceptance Fee Submission successful'
     *  - typeOfId = 'Transaction Id'
     *  - if branch: dateVal parsed from orderCompletionDate page param
     *  - amount from orderAmount page param
     *  - paymentId from transactionId page param
     */
    @IsTest
    static void testPaymentReceiptController_OfferAcceptanceFee() {
        Program prog = insertProgram();
        Application__c app = insertApplication(prog.Id);

        Payment__c pay = new Payment__c(
            Payee_Name__c                        = 'Ravi Kumar',
            Payee_Email__c                       = 'ravi@mail.com',
            Amount_Paid__c                       = 75000,
            Gateway_Order_Id__c                  = 'order_67890',
            Gateway_Transaction_Id__c            = 'txn_67890',
            Razorpay_Order_Creation_Timestamp__c = System.now(),
            Payment_Type__c                      = 'Offer Acceptance Fee',
            Application__c                       = app.Id
        );
        insert pay;

        Test.setCurrentPage(new PageReference('/apex/PaymentReceiptPage'));
        ApexPages.currentPage().getParameters().put('orderId',             'order_67890');
        ApexPages.currentPage().getParameters().put('orderCompletionDate', '03/04/2026 10:30:00');
        ApexPages.currentPage().getParameters().put('orderAmount',         '75000');
        ApexPages.currentPage().getParameters().put('transactionId',       'txn_67890');

        Test.startTest();
        PaymentReceiptController ctrl = new PaymentReceiptController();
        Test.stopTest();

        System.assertEquals('Ravi Kumar',    ctrl.payeename);
        System.assertEquals('ravi@mail.com', ctrl.payee_email);
        System.assertEquals(75000,           ctrl.amount);
        System.assertEquals('txn_67890',     ctrl.paymentId);
        System.assertEquals('APP-001',       ctrl.applicationNumber); // matches Name field
        System.assertEquals('MBA Program',   ctrl.programName);
        System.assertNotEquals(null,          ctrl.dateVal);
        System.assertEquals('Acceptance Fee Submission successful', ctrl.paymentTypeMessage);
        System.assertEquals('Transaction Id', ctrl.typeOfId);
    }

    // ─── Test 3: Gateway_Transaction_Id__c fallback when Razorpay_Payment_Id__c is null
    /**
     * Covers: paymentId ternary → Razorpay_Payment_Id__c is null
     *         → falls back to Gateway_Transaction_Id__c
     */
    @IsTest
    static void testPaymentReceiptController_GatewayTransactionIdFallback() {
        Program prog = insertProgram();
        Application__c app = insertApplication(prog.Id);

        Payment__c pay = new Payment__c(
            Payee_Name__c                        = 'Anjali Sharma',
            Payee_Email__c                       = 'anjali@mail.com',
            Amount_Paid__c                       = 30000,
            Razorpay_Payment_Id__c               = null,
            Gateway_Transaction_Id__c            = 'gtxn_99999',
            Gateway_Order_Id__c                  = 'order_99999',
            Razorpay_Order_Creation_Timestamp__c = System.now(),
            Payment_Type__c                      = 'Application Fee',
            Application__c                       = app.Id
        );
        insert pay;

        Test.setCurrentPage(new PageReference('/apex/PaymentReceiptPage'));
        ApexPages.currentPage().getParameters().put('orderId', 'order_99999');

        Test.startTest();
        PaymentReceiptController ctrl = new PaymentReceiptController();
        Test.stopTest();

        System.assertEquals('gtxn_99999', ctrl.paymentId,
            'Should fall back to Gateway_Transaction_Id__c when Razorpay_Payment_Id__c is null');
        System.assertEquals(30000,        ctrl.amount);
        System.assertEquals('APP-001',    ctrl.applicationNumber);
    }
}
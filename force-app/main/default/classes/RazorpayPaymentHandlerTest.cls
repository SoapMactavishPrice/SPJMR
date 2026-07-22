@IsTest
private class RazorpayPaymentHandlerTest {

    // ✅ SUCCESS MOCK (200)
    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"order_test_123","status":"created"}');
            return res;
        }
    }

    // ✅ Create Applicant (Person Account safe)
    private static Account createApplicant() {

        Id personRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ].Id;

        Account acc = new Account(
            RecordTypeId = personRtId,
            FirstName = 'Test',
            LastName = 'User',
            PersonEmail = UserInfo.getUserEmail(),
            Phone = '9999999999'
        );
        insert acc;

        return acc;
    }

    // ✅ Create Program
    private static Program createProgram(String code,String shortCode) {
        Program p = new Program(
            Name = 'Test Program',
            Program_Code__c = code,
            Programme_Type__c = 'Full-Time',
            Programme_Sub_Type__c = 'Class Room',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Contact__c = '8910294512',
            Short_Programme_Code__c=shortCode
        );
        insert p;
        return p;
    }

    // ✅ Create Batch (CRITICAL for hitting callout)
    private static ProgramCohort createBatch(Id progId) {
        ProgramCohort batch = new ProgramCohort(
            Name = 'Batch 1',
            Application_Fee__c = 1000,
            DiscountedPrice__c = 500,
            ProgramId=progId,
            Batch_Code__c=progId+'RANDOMTEXT123',
            Short_Batch_Code__c = '123',
            Status='Active',
            StartDate = Date.Today().addYears(-2),
            EndDate = Date.Today().addYears(1),
            Batch_Sub_Type__c = 'Online',
            Batch_Intake__c=200
        );
        insert batch;
        return batch;
    }

    // ✅ Create Application
    private static Application__c createApplication(Id accId, Id progId, Id batchId) {

        Application__c app = new Application__c(
            Name = 'APP-TEST',
            Applicant__c = accId,
            Program__c = progId,
            Batch__c = batchId,
            Application_Status__c = 'In Progress'
        );
        insert app;

        insert new Personal_Detail__c(
            Application__c = app.Id,
            First_Name__c = 'Test',
            Last_Name__c = 'User',
            Mobile_Number__c = '9999999999'
        );

        return app;
    }

    @IsTest
    static void testCreateOrder_Hits200Block() {

        // ✅ Setup data
        Account acc = createApplicant();
        Program prog = createProgram('PGDM','PDM'); // must match query
        ProgramCohort batch = createBatch(prog.Id);
        Application__c app = createApplication(acc.Id, prog.Id, batch.Id);

        Test.startTest();

        // ✅ IMPORTANT: mock INSIDE startTest
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Map<String, String> result =
            RazorpayPaymentHandler.createOrder(prog.Program_Code__c, 'false');

        Test.stopTest();

        // ✅ ASSERT → proves 200 block executed
        System.assertNotEquals(null, result);
        System.assertEquals('order_test_123', result.get('orderId'));

        // ✅ Verify Payment created
        List<Payment__c> payments = [
            SELECT Id, Gateway_Order_Id__c
            FROM Payment__c
            WHERE Application__c = :app.Id
        ];

        System.assertEquals(1, payments.size());
        System.assertEquals('order_test_123', payments[0].Gateway_Order_Id__c);
    }
    
    @IsTest
static void testCreateOrder_OfferAcceptance_200() {

    Account acc = createApplicant();
    Program prog = createProgram('PGDM2','PDM');
    ProgramCohort batch = createBatch(prog.Id);
    Application__c app = createApplication(acc.Id, prog.Id, batch.Id);

    Test.startTest();
    Test.setMock(HttpCalloutMock.class, new SuccessMock());

    Map<String, String> result =
        RazorpayPaymentHandler.createOrder(prog.Program_Code__c, 'true');

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals('order_test_123', result.get('orderId'));
}
    
    @IsTest
static void testCreateOrder_ExistingPayment() {

    Account acc = createApplicant();
    Program prog = createProgram('PGDM3','PDM');
    ProgramCohort batch = createBatch(prog.Id);
    Application__c app = createApplication(acc.Id, prog.Id, batch.Id);

    // ✅ Create existing payment
    insert new Payment__c(
        Application__c = app.Id,
        Payment_Type__c = 'Application Fee',
        Status__c = 'created',
        Gateway_Order_Id__c = 'existing123',
        Amount__c = 1000,
        Payee_Email__c = UserInfo.getUserEmail(),
        Payee_Name__c = 'Test User'
    );

    Test.startTest();

    Map<String, String> result =
        RazorpayPaymentHandler.createOrder(prog.Program_Code__c, 'false');

    Test.stopTest();

    System.assertEquals('existing123', result.get('orderId'));
}
    
    private class FailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(500);
        res.setBody('error');
        return res;
    }
}

@IsTest
static void testCreateOrder_Failure() {

    Account acc = createApplicant();
    Program prog = createProgram('PGDM4','PDM');
    ProgramCohort batch = createBatch(prog.Id);
    createApplication(acc.Id, prog.Id, batch.Id);

    Test.startTest();
    Test.setMock(HttpCalloutMock.class, new FailureMock());

    Boolean thrown = false;

    try {
        RazorpayPaymentHandler.createOrder(prog.Program_Code__c, 'false');
    } catch (AuraHandledException e) {
        thrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, thrown);
}
    
    @IsTest
static void testGetPaymentDetails_Discount() {

    Account acc = createApplicant();
    Program prog = createProgram('PGDM','PDM');
    ProgramCohort batch = createBatch(prog.Id);

    Application__c app = new Application__c(
        Name = 'APP-DISC',
        Applicant__c = acc.Id,
        Program__c = prog.Id,
        Batch__c = batch.Id,
        OtherProgrammeRegNo__c = 'pgdm20260001'
    );
    insert app;

    insert new Personal_Detail__c(
        Application__c = app.Id,
        First_Name__c = 'Test',
        Last_Name__c = 'User',
        Mobile_Number__c = '9999999999'
    );

    Test.startTest();

    RazorpayPaymentHandler.RazorPayResponsePayment res =
        RazorpayPaymentHandler.getPaymentDetails(app.Id);

    Test.stopTest();

    System.assertNotEquals(null, res);
}
    
    @IsTest
static void testReturnPaymentRecord() {

    Account acc = createApplicant();
    Program prog = createProgram('PGDM5','PDM');
    ProgramCohort batch = createBatch(prog.Id);
    Application__c app = createApplication(acc.Id, prog.Id, batch.Id);

    Payment__c pay = new Payment__c(
        Application__c = app.Id,
        Payment_Type__c = 'Application Fee',
        Status__c = 'paid'
    );
    insert pay;

    Test.startTest();

    String result =
        RazorpayPaymentHandler.returnPaymentRecord(app.Id, 'Application Fee');

    Test.stopTest();

    System.assertEquals(pay.Id, result);
}
    
    @IsTest
static void testGetPaymentHistory() {

    Payment__c pay = new Payment__c(
        Amount_Paid__c = 100,
        Status__c = 'paid',
        Payee_Email__c = UserInfo.getUserEmail(),
        Payment_Type__c = 'Application Fee'
    );
    insert pay;

    ContentVersion cv = new ContentVersion(
        Title = 'Receipt',
        PathOnClient = 'receipt.pdf',
        VersionData = Blob.valueOf('test')
    );
    insert cv;

    Id docId = [
        SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
    ].ContentDocumentId;

    insert new ContentDocumentLink(
        LinkedEntityId = pay.Id,
        ContentDocumentId = docId,
        ShareType = 'V'
    );

    Test.startTest();

    List<RazorpayPaymentHandler.paymentHistory> result =
        RazorpayPaymentHandler.getPaymentHistory();

    Test.stopTest();

    System.assert(result.size() > 0);
}
}
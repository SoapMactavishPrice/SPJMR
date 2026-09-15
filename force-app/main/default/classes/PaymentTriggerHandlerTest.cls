@isTest
private class PaymentTriggerHandlerTest {

    // ─────────────────────────────────────────────
    // Utility: picklist helper via describeSObjects
    // ─────────────────────────────────────────────
    private static String getPicklistValue(String obj, String field, String fallback) {
        Schema.DescribeSObjectResult d =
            Schema.describeSObjects(new List<String>{ obj })[0];
        Map<String, Schema.SObjectField> fm = d.fields.getMap();
        if (!fm.containsKey(field)) return fallback;
        for (Schema.PicklistEntry pe : fm.get(field).getDescribe().getPicklistValues()) {
            if (pe.isActive()) return pe.getValue();
        }
        return fallback;
    }

    // ─────────────────────────────────────────────
    // Helper: Person Account
    // ─────────────────────────────────────────────
    private static Account createPersonAccount(String suffix) {
        Id rtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1
        ].Id;

        Account acc = new Account(
            RecordTypeId = rtId,
            FirstName    = 'Test',
            LastName     = 'User ' + suffix,
            PersonEmail  = 'test' + suffix + '@mail.com',
            Phone        = '9999999999'
        );
        insert acc;
        return [SELECT Id, PersonContactId, Name FROM Account WHERE Id = :acc.Id];
    }

    // ─────────────────────────────────────────────
    // Helper: Program (standard EDA object)
    // ─────────────────────────────────────────────
    private static Program createProgram(String suffix) {
        String shortCode = 'PP' + (suffix != null && suffix.length() > 0
            ? suffix.substring(0, 1) : 'X');

        Program prog = new Program(
            Name                    = 'Program ' + suffix,
            Program_Code__c         = 'PC' + suffix,
            Short_Programme_Code__c = shortCode,
            Programme_Contact__c    = '9999999999',
            StartDate               = Date.today(),
            EndDate                 = Date.today().addDays(10),
            Programme_Type__c       = getPicklistValue('Program', 'Programme_Type__c',   'Full-Time'),
            Programme_Sub_Type__c   = getPicklistValue('Program', 'Programme_Sub_Type__c','Class Room')
        );
        insert prog;
        return prog;
    }

    // ─────────────────────────────────────────────
    // Helper: Application__c
    // ─────────────────────────────────────────────
    private static Application__c createApplication(Id accId, Id progId, String suffix) {
        Application__c app = new Application__c(
            Name                  = 'APP-' + suffix,
            Applicant__c          = accId,
            Program__c            = progId,
            Application_Status__c = getPicklistValue(
                'Application__c', 'Application_Status__c', 'Initiated'
            )
        );
        insert app;
        return app;
    }

    // ─────────────────────────────────────────────
    // Helper: Payment Status
    // ─────────────────────────────────────────────
    private static String getPaymentStatus() {
        return getPicklistValue('Payment__c', 'Status__c', null);
    }

    // ═══════════════════════════════════════════════════════════════
    // TEST 1 – Happy path: Programme_Full_Name__c and
    //          Applicant_Name__c are stamped on the Payment record
    // ═══════════════════════════════════════════════════════════════
    @isTest
    static void testSendEmail_FieldsStamped() {
        Program        prog = createProgram('E1');
        Account        acc  = createPersonAccount('E1');
        Application__c app  = createApplication(acc.Id, prog.Id, 'E1');

        Payment__c pmt = new Payment__c(
            Application__c  = app.Id,
            Payment_Type__c = 'Application Fee',
            Status__c       = getPaymentStatus()
        );
        insert pmt;

        Test.startTest();
        try {
            PaymentTriggerHandler.sendApplicationFeeConformationEmail(pmt.Id);
        } catch (Exception e) {
            // Flow may be unavailable in test context; field-update is still verified below
            System.debug('Flow exception (expected in sandbox): ' + e.getMessage());
        }
        Test.stopTest();

        Payment__c result = [
            SELECT Programme_Full_Name__c, Applicant_Name__c
            FROM Payment__c WHERE Id = :pmt.Id
        ];

        System.assertEquals(
            prog.Name,
            result.Programme_Full_Name__c,
            'Programme_Full_Name__c should match Program name'
        );
        System.assertNotEquals(
            null,
            result.Applicant_Name__c,
            'Applicant_Name__c should be stamped from Applicant__r.Name'
        );
    }

    // ═══════════════════════════════════════════════════════════════
    // TEST 2 – Verify Programme_Full_Name__c exact value matches
    //          Program.Name and Applicant_Name__c matches Account.Name
    // ═══════════════════════════════════════════════════════════════
    @isTest
    static void testSendEmail_FieldValuesAreCorrect() {
        Program        prog = createProgram('E2');
        Account        acc  = createPersonAccount('E2');
        Application__c app  = createApplication(acc.Id, prog.Id, 'E2');

        Payment__c pmt = new Payment__c(
            Application__c  = app.Id,
            Payment_Type__c = 'Application Fee',
            Status__c       = getPaymentStatus()
        );
        insert pmt;

        Test.startTest();
        try {
            PaymentTriggerHandler.sendApplicationFeeConformationEmail(pmt.Id);
        } catch (Exception e) {
            System.debug('Flow exception: ' + e.getMessage());
        }
        Test.stopTest();

        Payment__c result = [
            SELECT Programme_Full_Name__c, Applicant_Name__c
            FROM Payment__c WHERE Id = :pmt.Id
        ];

        // Verify exact values
        System.assertEquals(
            prog.Name,
            result.Programme_Full_Name__c,
            'Programme_Full_Name__c must equal the Program record Name'
        );
        System.assertEquals(
            acc.Name,
            result.Applicant_Name__c,
            'Applicant_Name__c must equal the Account (Person Account) Name'
        );
    }

    // ═══════════════════════════════════════════════════════════════
    // TEST 3 – Calling with a different Payment_Type__c still
    //          stamps the fields (method does not filter by type)
    // ═══════════════════════════════════════════════════════════════
    @isTest
    static void testSendEmail_OtherPaymentType_StillStampsFields() {
        Program        prog = createProgram('E3');
        Account        acc  = createPersonAccount('E3');
        Application__c app  = createApplication(acc.Id, prog.Id, 'E3');

        Payment__c pmt = new Payment__c(
            Application__c  = app.Id,
            Payment_Type__c = 'Offer Acceptance Fee',
            Status__c       = getPaymentStatus()
        );
        insert pmt;

        Test.startTest();
        try {
            PaymentTriggerHandler.sendApplicationFeeConformationEmail(pmt.Id);
        } catch (Exception e) {
            System.debug('Flow exception: ' + e.getMessage());
        }
        Test.stopTest();

        Payment__c result = [
            SELECT Programme_Full_Name__c, Applicant_Name__c
            FROM Payment__c WHERE Id = :pmt.Id
        ];

        System.assertEquals(prog.Name, result.Programme_Full_Name__c,
            'Fields should be stamped regardless of payment type');
        System.assertNotEquals(null, result.Applicant_Name__c);
    }
}
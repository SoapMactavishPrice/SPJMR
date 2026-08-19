@isTest
private class SessionPortalNotificationQueueableTest {

    @testSetup

static void setupData() {

    // Create Learner Account
    Account learner = new Account(
        Name = 'Test Learner'
    );
    insert learner;

    // Create Learner Contact
    Contact learnerContact = new Contact(
        LastName = 'Learner',
        AccountId = learner.Id
    );
    insert learnerContact;

    // Create Academic Term
    AcademicTerm term = new AcademicTerm(
        Name = 'Test Term'
    );
    insert term;

    // Create Academic Term Enrollment
   AcademicTermEnrollment termEnrollment = new AcademicTermEnrollment(
        LearnerAccountId = learner.Id,
        LearnerContactId = learnerContact.Id,
        AcademicTermId = term.Id
    );
   Database.SaveResult sr = Database.insert(termEnrollment, false);

if (!sr.isSuccess()) {
    System.assert(false,
        sr.getErrors()[0].getStatusCode() + ' : ' +
        sr.getErrors()[0].getMessage());
}

// Get the Id from the SaveResult
Id ateId = sr.getId();

System.assertNotEquals(null, ateId);

    Division_Enrollment__c divisionEnrollment = new Division_Enrollment__c(
    Academic_Term_Enrollment__c = ateId
);

insert divisionEnrollment;

// Verify Division Enrollment was created correctly
System.assertNotEquals(null, divisionEnrollment.Id);

Division_Enrollment__c div = [
    SELECT Id,
           Academic_Term_Enrollment__c
    FROM Division_Enrollment__c
    WHERE Id = :divisionEnrollment.Id
];

System.assertEquals(
    ateId,
    div.Academic_Term_Enrollment__c,
    'Academic Term Enrollment lookup was not saved'
);

// Create Session
Session__c session = new Session__c(
    Name = 'Test Session'
);
insert session;

    // Create Session Enrollment
    Session_Enrollment__c sessionEnrollment = new Session_Enrollment__c(
        Session__c = session.Id,
        Division_Enrollment__c = divisionEnrollment.Id,
         Academic_Term_Enrollment__c = ateId
    );
    insert sessionEnrollment;
}

    @isTest
    static void testQueueableCreatesPortalNotification() {

        Session__c session = [
            SELECT Id, Name
            FROM Session__c
            LIMIT 1
        ];

        Test.startTest();

        System.enqueueJob(
            new SessionPortalNotificationQueueable(
                new Set<Id>{ session.Id }
            )
        );

        Test.stopTest();

        List<Portal_Notification__c> notifications = [
            SELECT Id,
                   Title__c
               //    Body__c,
               //    Recipient_Account__c,
              //     Session__c,
             //      Is_Read__c
            FROM Portal_Notification__c
        ];

        System.assertEquals(1, notifications.size());
        System.assertEquals('Session Now Available', notifications[0].Title__c);
  /*      System.assertEquals(
            'The session "' + session.Name + '" is now published.',
            notifications[0].Body__c
        );*/
   //     System.assertEquals(false, notifications[0].Is_Read__c);
   //     System.assertEquals(session.Id, notifications[0].Session__c);
    }

    @isTest
    static void testQueueableWithNoEnrollments() {

        Session__c session = new Session__c(
            Name = 'Session Without Enrollments'
        );
        insert session;
        
        List<Session_Enrollment__c> enrollments = [
    SELECT Id,
           Session__c,
           Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccountId
    FROM Session_Enrollment__c
];

System.assertEquals(1, enrollments.size(), 'Session Enrollment not created');

System.assertNotEquals(
    null,
    enrollments[0].Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccountId,
    'LearnerAccountId is null'
);

        Test.startTest();

        System.enqueueJob(
            new SessionPortalNotificationQueueable(
                new Set<Id>{ session.Id }
            )
        );

        Test.stopTest();

        Integer countNotifications = [
            SELECT COUNT()
            FROM Portal_Notification__c
        ];

        System.assertEquals(0, countNotifications);
    }
    @isTest
static void testQueueableWithNullLearner() {

    Contact learnerContact = new Contact(
        LastName = 'Test Contact'
    );
    insert learnerContact;

    AcademicTerm term = new AcademicTerm(
        Name = 'Term 2'
    );
    insert term;

    AcademicTermEnrollment termEnrollment = new AcademicTermEnrollment(
        LearnerContactId = learnerContact.Id,
        AcademicTermId = term.Id
        // LearnerAccountId intentionally omitted
    );
    insert termEnrollment;

    Division_Enrollment__c divisionEnrollment = new Division_Enrollment__c(
        Academic_Term_Enrollment__c = termEnrollment.Id
    );
    insert divisionEnrollment;

    Session__c session = new Session__c(
        Name = 'Null Learner Session'
    );
    insert session;

    Session_Enrollment__c enrollment = new Session_Enrollment__c(
        Session__c = session.Id,
        Division_Enrollment__c = divisionEnrollment.Id,
        Academic_Term_Enrollment__c = termEnrollment.Id
    );
    insert enrollment;

    Test.startTest();
    System.enqueueJob(
        new SessionPortalNotificationQueueable(
            new Set<Id>{ session.Id }
        )
    );
    Test.stopTest();

    Integer countNotifications = [
        SELECT COUNT()
        FROM Portal_Notification__c
   //     WHERE Session__c = :session.Id
    ];

    System.assertEquals(0, countNotifications);
}

}
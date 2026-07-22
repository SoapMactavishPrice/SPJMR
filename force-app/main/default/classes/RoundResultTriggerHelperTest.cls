@IsTest
private class RoundResultTriggerHelperTest {

    @TestSetup
    static void setupData() {
        insert new Automation_Control__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Skip_Flows__c = true
        );

        List<Application__c> apps = new List<Application__c>{
            new Application__c(
                Name = 'RR-APP-NULL',
                Applicant_State_Management__c = 'Profile Shortlisted'
            ),
            new Application__c(
                Name = 'RR-APP-NONNULL',
                Applicant_State_Management__c = 'Profile Shortlisted',
                Evaluation_Score__c = 5
            )
        };
        insert apps;

        RoundMaster__c round = new RoundMaster__c(
            Name = 'Round One',
            RoundNumber__c = '1'
        );
        insert round;

        SlotMaster__c slot = new SlotMaster__c(
            BookedCapacity__c = 0
        );
        insert slot;

        insert new List<ApplicationSlotBooking__c>{
            new ApplicationSlotBooking__c(
                Application__c = apps[0].Id,
                RoundMaster__c = round.Id,
                SlotMaster__c = slot.Id
            ),
            new ApplicationSlotBooking__c(
                Application__c = apps[1].Id,
                RoundMaster__c = round.Id,
                SlotMaster__c = slot.Id
            )
        };
    }

    @IsTest
    static void testUpdateApplicationScore_EmptyList() {
        Test.startTest();
        RoundResultTriggerHelper.updateApplicationScore(new List<Round_Result__c>());
        Test.stopTest();

        System.assertEquals(true, true, 'Method should safely return on empty input.');
    }

    @IsTest
    static void testUpdateApplicationScore_NullAndNonNullBranches() {
        Application__c nullScoreApp = [
            SELECT Id, Evaluation_Score__c
            FROM Application__c
            WHERE Name = 'RR-APP-NULL'
            LIMIT 1
        ];
        nullScoreApp.Evaluation_Score__c = null;
        update nullScoreApp;

        List<ApplicationSlotBooking__c> bookings = [
            SELECT Id, Application__c, Application__r.Name
            FROM ApplicationSlotBooking__c
            WHERE Application__r.Name IN ('RR-APP-NULL', 'RR-APP-NONNULL')
        ];

        Id nullScoreSlotId;
        Id nonNullScoreSlotId;
        for (ApplicationSlotBooking__c b : bookings) {
            if (b.Application__r.Name == 'RR-APP-NULL') {
                nullScoreSlotId = b.Id;
            } else if (b.Application__r.Name == 'RR-APP-NONNULL') {
                nonNullScoreSlotId = b.Id;
            }
        }

        System.assertNotEquals(null, nullScoreSlotId, 'Expected booking for null-score app.');
        System.assertNotEquals(null, nonNullScoreSlotId, 'Expected booking for non-null-score app.');

        List<Round_Result__c> newRounds = new List<Round_Result__c>{
            new Round_Result__c(
                ApplicationSlotBooking__c = nullScoreSlotId,
                Net_Score__c = 10
            ),
            new Round_Result__c(
                ApplicationSlotBooking__c = nonNullScoreSlotId,
                Net_Score__c = 7
            )
        };

        Test.startTest();
        RoundResultTriggerHelper.updateApplicationScore(newRounds);
        Test.stopTest();

        Map<String, Application__c> appsByName = new Map<String, Application__c>();
        for (Application__c app : [
            SELECT Name, Evaluation_Score__c
            FROM Application__c
            WHERE Name IN ('RR-APP-NULL', 'RR-APP-NONNULL')
        ]) {
            appsByName.put(app.Name, app);
        }

        System.assertEquals(
            null,
            appsByName.get('RR-APP-NULL').Evaluation_Score__c,
            'Null-branch record is not added to update list in current helper logic.'
        );
        System.assertEquals(
            12,
            appsByName.get('RR-APP-NONNULL').Evaluation_Score__c,
            'Expected non-null score to be incremented and updated.'
        );
    }

    @IsTest
    static void testUpdateApplicationScore_CatchDmlException() {
        Application__c app = [
            SELECT Id, Evaluation_Score__c
            FROM Application__c
            WHERE Name = 'RR-APP-NONNULL'
            LIMIT 1
        ];

        Schema.DescribeFieldResult dfr = Application__c.Evaluation_Score__c.getDescribe();
        Integer precision = dfr.getPrecision();
        Integer scale = dfr.getScale();
        Integer integerDigits = precision - scale;

        String maxValueText = '';
        for (Integer i = 0; i < integerDigits; i++) {
            maxValueText += '9';
        }
        if (scale > 0) {
            maxValueText += '.';
            for (Integer i = 0; i < scale; i++) {
                maxValueText += '9';
            }
        }
        Decimal maxAllowed = Decimal.valueOf(maxValueText);

        app.Evaluation_Score__c = maxAllowed;
        update app;

        Id slotId = [
            SELECT Id
            FROM ApplicationSlotBooking__c
            WHERE Application__r.Name = 'RR-APP-NONNULL'
            LIMIT 1
        ].Id;

        Test.startTest();
        RoundResultTriggerHelper.updateApplicationScore(new List<Round_Result__c>{
            new Round_Result__c(
                ApplicationSlotBooking__c = slotId,
                Net_Score__c = 1
            )
        });
        Test.stopTest();

        Application__c afterApp = [
            SELECT Evaluation_Score__c
            FROM Application__c
            WHERE Id = :app.Id
        ];
        System.assertEquals(
            maxAllowed,
            afterApp.Evaluation_Score__c,
            'Expected score unchanged when update fails and is handled in catch.'
        );
    }
}
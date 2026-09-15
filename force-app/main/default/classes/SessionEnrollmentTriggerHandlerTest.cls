@IsTest
private class SessionEnrollmentTriggerHandlerTest {

    private static Session__c makeSession(String name, Id courseId) {
        Session__c sessionRecord = new Session__c(
            Name = name,
            Course__c = courseId,
            Session_Date__c = Date.today(),
            Start_Time__c = Datetime.now(),
            End_Time__c = Datetime.now().addHours(1),
            Schedule_Type__c = 'Published',
            Color__c = 'blue'
        );
        insert sessionRecord;
        return sessionRecord;
    }

    private static Session_Enrollment__c makeEnrollment(
        Id sessionId,
        Id termEnrollmentId,
        String enrollmentName
    ) {
        Session_Enrollment__c enrollment = new Session_Enrollment__c(
            Name = enrollmentName,
            Session__c = sessionId,
            Academic_Term_Enrollment__c = termEnrollmentId,
            Attendance__c = 'Present'
        );
        insert enrollment;
        return enrollment;
    }

    @IsTest
    static void createsNotificationsForChangedTargetStatuses() {
        // Reuses the project test-data factory, as done in existing test classes.
        Account learner =
            SpjimrPortalTestDataFactory.buildLearnerPersonAccount('seh');

        Id termId = SpjimrPortalTestDataFactory.insertAcademicTerm();

        Id termEnrollmentId =
            SpjimrPortalTestDataFactory.insertAcademicTermEnrollment(
                learner.Id,
                termId
            );

        Id offeringId =
            SpjimrPortalTestDataFactory.insertCourseOffering(termId);

        Id courseId = [
            SELECT LearningCourseId
            FROM CourseOffering
            WHERE Id = :offeringId
        ].LearningCourseId;

        Session_Enrollment__c absentEnrollment = makeEnrollment(
            makeSession('Finance Workshop', courseId).Id,
            termEnrollmentId,
            'Absent Enrollment'
        );

        Session_Enrollment__c lateEnrollment = makeEnrollment(
            makeSession('Orientation', null).Id,
            termEnrollmentId,
            'Late Enrollment'
        );

        Map<Id, Session_Enrollment__c> newMap =
            new Map<Id, Session_Enrollment__c>{
                absentEnrollment.Id => new Session_Enrollment__c(
                    Id = absentEnrollment.Id,
                    Attendance__c = 'Absent'
                ),
                lateEnrollment.Id => new Session_Enrollment__c(
                    Id = lateEnrollment.Id,
                    Attendance__c = 'Late'
                )
            };

        Map<Id, Session_Enrollment__c> oldMap =
            new Map<Id, Session_Enrollment__c>{
                absentEnrollment.Id => new Session_Enrollment__c(
                    Id = absentEnrollment.Id,
                    Attendance__c = 'Present'
                ),
                lateEnrollment.Id => new Session_Enrollment__c(
                    Id = lateEnrollment.Id,
                    Attendance__c = 'Present'
                )
            };

        // The handler queries the database, so save the updated values first.
        update new List<Session_Enrollment__c>{
            new Session_Enrollment__c(
                Id = absentEnrollment.Id,
                Attendance__c = 'Absent'
            ),
            new Session_Enrollment__c(
                Id = lateEnrollment.Id,
                Attendance__c = 'Late'
            )
        };

        Integer notificationCountBefore = [
            SELECT COUNT()
            FROM Portal_Notification__c
        ];

        Test.startTest();
        SessionEnrollmentTriggerHandler.handleAttendanceChanged(newMap, oldMap);
        Test.stopTest();

        Integer notificationCountAfter = [
            SELECT COUNT()
            FROM Portal_Notification__c
        ];

        Assert.areEqual(
            notificationCountBefore + 2,
            notificationCountAfter,
            'Absent and Late attendance must each create one notification.'
        );
    }

    @IsTest
    static void coversStatusHelpersAndNoOpChanges() {
        Assert.isTrue(
            SessionEnrollmentTriggerHandler.valuesEqual(null, '  ')
        );
        Assert.isTrue(
            SessionEnrollmentTriggerHandler.valuesEqual(' Late ', 'late')
        );
        Assert.isFalse(
            SessionEnrollmentTriggerHandler.valuesEqual('Absent', 'Late')
        );

        for (String statusValue : new List<String>{
            'Absent',
            'a',
            'Late',
            'Sanctioned Leave',
            'sanctioned',
            'sl'
        }) {
            Assert.isTrue(
                SessionEnrollmentTriggerHandler.isTargetAttendanceStatus(
                    statusValue
                ),
                statusValue + ' should be a target attendance status.'
            );
        }

        Assert.isFalse(
            SessionEnrollmentTriggerHandler.isTargetAttendanceStatus(null)
        );
        Assert.isFalse(
            SessionEnrollmentTriggerHandler.isTargetAttendanceStatus('Present')
        );

        Assert.areEqual(
            'updated',
            SessionEnrollmentTriggerHandler.attendanceLabelForMessage(null)
        );
        Assert.areEqual(
            'absent',
            SessionEnrollmentTriggerHandler.attendanceLabelForMessage('A')
        );
        Assert.areEqual(
            'late',
            SessionEnrollmentTriggerHandler.attendanceLabelForMessage(' Late ')
        );
        Assert.areEqual(
            'sanctioned leave',
            SessionEnrollmentTriggerHandler.attendanceLabelForMessage('sl')
        );
        Assert.areEqual(
            'Eligible',
            SessionEnrollmentTriggerHandler.attendanceLabelForMessage(
                ' Eligible '
            )
        );

        Id fakeEnrollmentId = Id.valueOf(
            Session_Enrollment__c.SObjectType.getDescribe().getKeyPrefix()
            + '000000000001'
        );

        Test.startTest();

        // Same value, ignoring spaces/case: handler returns without creating a notification.
        SessionEnrollmentTriggerHandler.handleAttendanceChanged(
            new Map<Id, Session_Enrollment__c>{
                fakeEnrollmentId => new Session_Enrollment__c(
                    Id = fakeEnrollmentId,
                    Attendance__c = ' Present '
                )
            },
            new Map<Id, Session_Enrollment__c>{
                fakeEnrollmentId => new Session_Enrollment__c(
                    Id = fakeEnrollmentId,
                    Attendance__c = 'present'
                )
            }
        );

        // Blank attendance is not a notification status.
        SessionEnrollmentTriggerHandler.handleAttendanceChanged(
            new Map<Id, Session_Enrollment__c>{
                fakeEnrollmentId => new Session_Enrollment__c(
                    Id = fakeEnrollmentId,
                    Attendance__c = null
                )
            },
            new Map<Id, Session_Enrollment__c>{
                fakeEnrollmentId => new Session_Enrollment__c(
                    Id = fakeEnrollmentId,
                    Attendance__c = 'Present'
                )
            }
        );

        Test.stopTest();
    }
}
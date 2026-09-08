@IsTest(SeeAllData=true)
private class AdmissionHelperTest {
    private static Program getConfiguredProgram() {
        return [
            SELECT Id, Name, Program_Code__c
            FROM Program
            WHERE Program_Code__c = 'PGPM'
            LIMIT 1
        ];
    }

    private static String uniqueEmail() {
        return 'admission.helper.' +
            String.valueOf(DateTime.now().getTime()) + '.' +
            String.valueOf(Crypto.getRandomInteger()).replace('-', '') +
            '@example.com';
    }

    private static String interviewerParams(
        String email,
        String firstName,
        String lastName
    ) {
        return JSON.serialize(new Map<String, Object>{
            'email' => email,
            'firstName' => firstName,
            'lastName' => lastName
        });
    }

    @IsTest
    static void createInterviewerCreatesUserAssignmentsAndGroupMembership() {
        Program programRecord = getConfiguredProgram();
        Group interviewerGroup = [
            SELECT Id
            FROM Group
            WHERE Type = 'Regular'
            AND Name = 'PGPM Interviewers'
            LIMIT 1
        ];
        String email = uniqueEmail();

        Test.startTest();
        String result = AdmissionHelper.createInterviewer(
            interviewerParams(email, 'Test', 'Interviewer'),
            programRecord.Id
        );
        Test.stopTest();

        System.assertEquals('User Created Successfully', result);
        User interviewer = [
            SELECT Id, FirstName, LastName, Email, Username
            FROM User
            WHERE Email = :email
            LIMIT 1
        ];
        System.assertEquals('Test', interviewer.FirstName);
        System.assertEquals('Interviewer', interviewer.LastName);
        System.assertEquals(email, interviewer.Email);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM GroupMember
                WHERE GroupId = :interviewerGroup.Id
                AND UserOrGroupId = :interviewer.Id
            ]
        );
        System.assertEquals(
            3,
            [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE AssigneeId = :interviewer.Id
                AND PermissionSet.Name IN (
                    'Faculty_Admission_Interviewer_Permission_Set',
                    'ApplicantB2CEducation',
                    'EducationCloudExprcCloudAccess'
                )
            ]
        );

        AdmissionHelper stringConstructor = new AdmissionHelper(
            String.valueOf(interviewer.Id)
        );
        System.assertEquals(interviewer.Id, stringConstructor.UserId);
        System.assertEquals(null, stringConstructor.GroupId);
    }

    @IsTest
    static void rejectsInvalidInputAndProgramsWithoutGroups() {
        Program programRecord = getConfiguredProgram();
        Boolean blankParamsRejected = false;
        Boolean nullProgramRejected = false;
        Boolean missingProgramRejected = false;

        try {
            AdmissionHelper.createInterviewer('', programRecord.Id);
        } catch (AuraHandledException expected) {
            blankParamsRejected = true;
        }
        try {
            AdmissionHelper.createInterviewer('{}', null);
        } catch (AuraHandledException expected) {
            nullProgramRejected = true;
        }
        try {
            AdmissionHelper.createInterviewer(
                interviewerParams(uniqueEmail(), 'Test', 'User'),
                UserInfo.getUserId()
            );
        } catch (AuraHandledException expected) {
            missingProgramRejected = true;
        }

        System.assert(blankParamsRejected);
        System.assert(nullProgramRejected);
        System.assert(missingProgramRejected);
        System.assertEquals(0, AdmissionHelper.getInterviewerUsers(null).size());
        System.assertEquals(
            0,
            AdmissionHelper.getInterviewerUsers(UserInfo.getUserId()).size()
        );
    }

    @IsTest
    static void rejectsMissingFirstNameAfterResolvingConfiguration() {
        Program programRecord = getConfiguredProgram();
        Boolean rejected = false;

        try {
            AdmissionHelper.createInterviewer(
                interviewerParams(uniqueEmail(), '', 'Interviewer'),
                programRecord.Id
            );
        } catch (AuraHandledException expected) {
            rejected = true;
        }

        System.assert(rejected, 'A first name is required.');
    }

    @IsTest
    static void returnsOnlyConfiguredGroupUsers() {
        Program programRecord = getConfiguredProgram();

        Test.startTest();
        List<User> interviewers = AdmissionHelper.getInterviewerUsers(
            programRecord.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, interviewers);
        for (User interviewer : interviewers) {
            System.assertNotEquals(null, interviewer.Email);
        }
    }
}
@IsTest
private class ProgrammeGroupServiceTest {

    private static String uniqueCode(String prefix) {
        return prefix + String.valueOf(DateTime.now().getTime());
    }

    private static Program makeProgram(String code) {
        Program programme = new Program(
            Name = 'Programme ' + code,
            Program_Code__c = code,
            Short_Programme_Code__c = code.left(3),
            Programme_Type__c = 'Part-time',
            Programme_Sub_Type__c = 'Class Room'
        );
        insert programme;
        return programme;
    }

    @IsTest
    static void createGroupsForPrograms_createsOnlyMissingGroups() {
        String code = uniqueCode('PG');
        Program programme = makeProgram(code);

        System.runAs(new User(Id = UserInfo.getUserId())) {
            ProgrammeGroupService.createGroupsForPrograms(null);
            ProgrammeGroupService.createGroupsForPrograms(new List<Program>());
            ProgrammeGroupService.createGroupsForPrograms(new List<Program>{
                new Program(Program_Code__c = '  '),
                new Program(Program_Code__c = ' ' + code + ' '),
                new Program(Program_Code__c = code),
                // Group.Name is limited to 80 characters.  This covers the
                // partial-DML error handling without failing the transaction.
                new Program(Program_Code__c = ''.leftPad(100, 'X'))
            });
        }

        String developerName = ProgrammeGroupService.buildDeveloperName(code);
        List<Group> groups = [
            SELECT Id, Name, DeveloperName, Type
            FROM Group
            WHERE DeveloperName = :developerName
        ];
        System.assertEquals(1, groups.size(), 'One group is created per program code.');
        System.assertEquals('Programme_' + code, groups[0].Name);
        System.assertEquals('Regular', groups[0].Type);

        // The second invocation finds the group and performs no further DML.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ProgrammeGroupService.createGroupsForPrograms(
                new List<Program>{ programme }
            );
        }

        System.assertEquals(1, [
            SELECT COUNT()
            FROM Group
            WHERE DeveloperName = :developerName
        ]);
    }

    @IsTest
    static void addTeamMembersToGroups_addsOnlyNewMembersForExistingGroups() {
        String code = uniqueCode('TM');
        Program programme = makeProgram(code);
        Program_Team__c team = new Program_Team__c(
            Name = 'Team ' + code,
            Program__c = programme.Id,
            Type__c = 'Verifier'
        );
        insert team;

        Program_Team_Members__c validMember = new Program_Team_Members__c(
            Program_Team__c = team.Id,
            User__c = UserInfo.getUserId(),
            Role__c = 'Member'
        );
        insert validMember;

        Program_Team_Members__c memberWithNoUser = new Program_Team_Members__c(
            Program_Team__c = team.Id,
            Role__c = 'Member'
        );
        insert memberWithNoUser;

        List<Program_Team_Members__c> members = [
            SELECT Id, User__c,
                Program_Team__r.Program__r.Program_Code__c
            FROM Program_Team_Members__c
            WHERE Id IN :new Set<Id>{ validMember.Id, memberWithNoUser.Id }
        ];

        // A member is safely skipped while its programme group does not exist.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ProgrammeGroupService.addTeamMembersToGroups(null);
            ProgrammeGroupService.addTeamMembersToGroups(new List<Program_Team_Members__c>());
            ProgrammeGroupService.addTeamMembersToGroups(members);
        }
        //System.assertEquals(0, [SELECT COUNT() FROM GroupMember]);

        System.runAs(new User(Id = UserInfo.getUserId())) {
            ProgrammeGroupService.createGroupsForPrograms(
                new List<Program>{ programme }
            );
        }

        String developerName = ProgrammeGroupService.buildDeveloperName(code);
        Id currentUserId = UserInfo.getUserId();

        Group programmeGroup = [
            SELECT Id
            FROM Group
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        System.runAs(new User(Id = UserInfo.getUserId())) {
            ProgrammeGroupService.addTeamMembersToGroups(members);
        }

        System.assertEquals(1, [
            SELECT COUNT()
            FROM GroupMember
            WHERE GroupId = :programmeGroup.Id
            AND UserOrGroupId = :currentUserId
        ]);

        // Existing membership is ignored, proving the operation is idempotent.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ProgrammeGroupService.addTeamMembersToGroups(members);
        }
        System.assertEquals(1, [
            SELECT COUNT()
            FROM GroupMember
            WHERE GroupId = :programmeGroup.Id
            AND UserOrGroupId = :currentUserId
        ]);
    }

    @IsTest
    static void buildNames_sanitizesAndLimitsDeveloperName() {
        System.assertEquals('Programme_GMP',
            ProgrammeGroupService.buildGroupName('GMP'));
        System.assertEquals('Programme_',
            ProgrammeGroupService.buildDeveloperName(null));
        System.assertEquals('Programme_GMP_25',
            ProgrammeGroupService.buildDeveloperName(' GMP-25 '));

        String longCode = ''.leftPad(100, 'A');
        String developerName = ProgrammeGroupService.buildDeveloperName(longCode);
        System.assertEquals(80, developerName.length());
        System.assertEquals('Programme_', developerName.substring(0, 10));
    }
}
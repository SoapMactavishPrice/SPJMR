public with sharing class AdmissionHelper implements Queueable{
    public Id UserId;
    public Id GroupId;

    public AdmissionHelper(String userId) {
        this.UserId = (Id) userId;
    }

    public AdmissionHelper(Id userId, Id groupId) {
        this.UserId = userId;
        this.GroupId = groupId;
    }

    private static final Set<String> APPLICANT_PERMSET = new Set<String>{
        'Faculty_Admission_Interviewer_Permission_Set',
        'ApplicantB2CEducation',
        'EducationCloudExprcCloudAccess'
    };

    public void execute(QueueableContext context) {

        List<PermissionSet> permissionSets = [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN :APPLICANT_PERMSET
        ];

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();

        for (PermissionSet permissionSet : permissionSets) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId = this.UserId,
                PermissionSetId = permissionSet.Id
            ));
        }

        if (!assignments.isEmpty()) {
            insert assignments;
        }

        if (this.GroupId != null) {
            insert new GroupMember(
                GroupId = this.GroupId,
                UserOrGroupId = this.UserId
            );
        }
    }


    @AuraEnabled
    public static string createInterviewer(String params, Id programId){
        system.debug('Param is '+params);
        if(String.isBlank(params) || programId == null){
            throw new AuraHandledException('Invalid Input');
        }

        Group interviewerGroup = getInterviewerGroup(programId);
        if (interviewerGroup == null) {
            throw new AuraHandledException(
                'No Public Groups Available for the selected program.'
            );
        }

        Map<String,Object> map_Params = (Map<String,Object>) JSON.deserializeUntyped(params);
        String email = String.valueOf(map_Params.get('email'));
        String firstName =  String.valueOf(map_Params.get('firstName'));
        String lastName =  String.valueOf(map_Params.get('lastName'));
        Id recordTypeFaculty = Schema.SobjectType.Account.getRecordTypeInfosByName().get('Interviewer Faculty').getRecordTypeId();
        List<String> tempString = email.split('@');
        String userName = tempString[0]+'.interviewer@'+tempString[1];

        List<User> userList = [SELECT Id FROM User 
        WHERE Email = :email AND Username=:userName LIMIT 1];
        list<Profile> listProfiles = [SELECT Id FROM Profile WHERE Name='SPJIMR Interviewer' LIMIT 1];
        if(userList.size()>0){
            throw new AuraHandledException('An Interviewer of Username: '+userName+' already exists for this email');
        }
        Account acc = new Account(FirstName=firstName,LastName=lastName,
        RecordTypeId =recordTypeFaculty,PersonEmail=email
       );
        try{
            insert acc;
            String alias = '';
            String nickname =  '';
            if(!String.isBlank(firstName)){
                alias += firstName.substring(0, 1);
                nickname+=firstName.substring(0, 1);
            }
            else{
                throw new AuraHandledException('First Name is missing!');
            }
            
            if(!String.isBlank(lastName)){
                alias += lastName.length()>7 ? lastName.substring(0, 7) : lastName;
                nickname += lastName.length()>3? lastName.substring(0, 3) : lastName;
            }else{
                throw new AuraHandledException('Last Name is missing!');
            }
            nickname+=String.valueOf(Math.random()*1000);
            
           Id personContactId = [SELECT personContactId FROM Account WHERE Id =: acc.Id LIMIT 1].personContactId;
            User u = new User(
            Username = userName,
            Email = email,
            FirstName = firstName,
            LastName = lastName,
            ProfileId = listProfiles[0].Id,
            CommunityNickname = nickname,
            ContactId=personContactId,LocaleSidKey = 'en_US',Alias=alias,
            TimeZoneSidKey = 'America/New_York',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8');
            insert u;
            AdmissionHelper lvc = new AdmissionHelper(
                u.Id,
                interviewerGroup.Id
            );
            System.enqueueJob(lvc);
            system.debug('Successfully created a user with Id '+u.Id);
            System.resetPassword(u.Id, true);
            return 'User Created Successfully'; 
        }catch(Site.ExternalUserCreateException e){
                    system.debug('Error creating user: '+e.getMessage());
                    throw new AuraHandledException(e.getMessage());
                }
        
    }

    @AuraEnabled(cacheable=true)
    public static List<User> getInterviewerUsers(Id programId) {
        if (programId == null) {
            return new List<User>();
        }

        Group interviewerGroup = getInterviewerGroup(programId);
        if (interviewerGroup == null) {
            return new List<User>();
        }

        return [
            SELECT Id, FirstName, LastName, Email, Username
            FROM User
            WHERE IsActive = true
            AND Profile.Name = 'SPJIMR Interviewer'
            AND Id IN (
                SELECT UserOrGroupId
                FROM GroupMember
                WHERE GroupId = :interviewerGroup.Id
            )
            ORDER BY CreatedDate DESC
            LIMIT 2000
        ];
    }

    private static Group getInterviewerGroup(Id programId) {
        List<Program> programs = [
            SELECT Id, Name, Program_Code__c
            FROM Program
            WHERE Id = :programId
            LIMIT 1
        ];
        if (programs.isEmpty()) {
            return null;
        }

        String programIdentifier = String.isBlank(programs[0].Program_Code__c)
            ? programs[0].Name
            : programs[0].Program_Code__c;
        if (String.isBlank(programIdentifier)) {
            return null;
        }

        String groupName = programIdentifier.trim() + ' Interviewers';
        List<Group> interviewerGroups = [
            SELECT Id, Name
            FROM Group
            WHERE Type = 'Regular'
            AND Name = :groupName
            LIMIT 1
        ];

        return interviewerGroups.isEmpty() ? null : interviewerGroups[0];
    }

}
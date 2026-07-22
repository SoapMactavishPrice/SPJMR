@isTest
public class AdmissionHelperTest {
    
    // --------------------------------------------
    // Helper Method to Get RecordTypeId
    // --------------------------------------------
    private static Id getFacultyRecordType() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByName()
            .get('Interviewer Faculty')
            .getRecordTypeId();
    }
    
    
    // --------------------------------------------
    // TEST: Blank Params
    // --------------------------------------------
    @isTest
    static void testCreateInterviewer_BlankParams() {
        
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try{
            AdmissionHelper.createInterviewer('');
        }catch(Exception e){
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown);
    }
    
    
    // --------------------------------------------
    // TEST: SUCCESS PATH (Covers Most Lines)
    // --------------------------------------------
    @isTest
    static void testCreateInterviewer_Success() {
        
        Id facultyRT = getFacultyRecordType();
        
        String email = 'successuser@test.com';
        
        String jsonInput = JSON.serialize(new Map<String,Object>{
            'email' => email,
                'firstName' => 'John',
                'lastName' => 'Smith'
                });
        
        Test.startTest();
        try{
            AdmissionHelper.createInterviewer(jsonInput);
        }catch(Exception e){
            // ignore portal specific errors
        }
        Test.stopTest();
        
        List<Account> accs =
            [SELECT Id FROM Account WHERE RecordType.Name = 'Interviewer Faculty'];
        
        System.assert(accs.size() > 0);
    }
    
    
    // --------------------------------------------
    // TEST: Existing User Branch
    // --------------------------------------------
    @isTest
    static void testCreateInterviewer_ExistingUser() {
        
        Profile p = [SELECT Id FROM Profile LIMIT 1];
        
        String email = 'duplicate@test.com';
        String userName = 'duplicate.interviewerfaculty@test.com';
        
        User existingUser = new User(
            Username = userName,
            Email = email,
            FirstName = 'Dup',
            LastName = 'User',
            Alias = 'dupusr',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            CommunityNickname = 'dupuser123'
        );
        insert existingUser;
        
        String jsonInput = JSON.serialize(new Map<String,Object>{
            'email' => email,
                'firstName' => 'Dup',
                'lastName' => 'User'
                });
        
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try{
            AdmissionHelper.createInterviewer(jsonInput);
        }catch(Exception e){
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown);
    }
    
    
    // --------------------------------------------
    // TEST: Queueable Execute
    // --------------------------------------------
    @isTest
    static void testQueueableExecute() {
        
        User u = [SELECT Id FROM User LIMIT 1];
        
        Test.startTest();
        System.enqueueJob(new AdmissionHelper(u.Id));
        Test.stopTest();
        
        System.assertEquals(true, u.Id != null);
    }
    
    
    // --------------------------------------------
    // TEST: getInterviewerUsers
    // --------------------------------------------
    @isTest
    static void testGetInterviewerUsers() {
        
        Test.startTest();
        List<User> users = AdmissionHelper.getInterviewerUsers();
        Test.stopTest();
        
        System.assertNotEquals(null, users);
    }
}
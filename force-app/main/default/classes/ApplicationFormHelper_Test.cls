@IsTest
private class ApplicationFormHelper_Test {

    // -------------------------
    // STEP 1: Test Data Setup
    // -------------------------
    private static void createTestData() {
        // ✅ Create Program record (standard object)
       
        Program prog = new Program(
            Name = 'MBA Program',
            Program_Code__c = 'MBA2025' // 
        );
        insert prog;

        // ✅ Create Sequence_Master__c record
        Sequence_Master__c seq = new Sequence_Master__c(
    Name = 'MBA2025',
    Program_Code__c = 'MBA2025',
    Year__c = String.valueOf(Date.today().year()),
    Last_Used_Number__c = 1
);
        insert seq;

        // ✅ Create Application_Form__c record
        Application_Form__c form = new Application_Form__c(
            Name = 'MBA Form',
            Form_HTML__c = '<html>Sample</html>',
            Program__c = prog.Id  // Lookup to Program
            
        );
        insert form;
    }

    // -------------------------
    // Save and Get Active Form
    // -------------------------
      @IsTest 

    static void testSaveAndGetForm() { 

        createTestData(); 

        Program prog = [SELECT Id, Program_Code__c FROM Program LIMIT 1]; 

 

        Test.startTest(); 

        Boolean  result = ApplicationFormHelper.saveForm('MBA Form', '<html>Updated</html>', prog.Id); 

        Test.stopTest(); 

 

        System.assertEquals(true, result); 

 

        Application_Form__c html = ApplicationFormHelper.getActiveForm(prog.Program_Code__c); 

        System.assertNotEquals(null, html); 

    } 
    // -------------------------
    // Generate Application Number From Sequence
    @IsTest 

    static void testGenerateApplicationNumberFromSequence() { 

        createTestData(); 
// Call generator - it reads Sequence_Master__c for program code + current year. 
        String appNumber = ApplicationFormHelper.generateApplicationNumberFromSequence('MBA2025'); 
// Expect it to start with program code followed by current year 
       String expectedStart = 'MBA2025' + String.valueOf(Date.today().year()); 

        System.assertEquals(true, appNumber.startsWith(expectedStart),'Application number should start with programCode + year'); 

    } 
    // Left Pad Utility
    // -------------------------
    @IsTest
    static void testLeftPadNumber() {
        String result = ApplicationFormHelper.leftPadNumber(25, 5);
        System.assertEquals('00025', result, 'Number should be left-padded');
    }

    // -------------------------
    // TEST 4: Save & Get Application Script File
    // -------------------------
    @IsTest
    static void testSaveAndRetrieveScriptFile() {
        createTestData();
        String jsonScript = '{"test":"value"}';

        String fileId = ApplicationFormHelper.saveApplicationScriptToFile(jsonScript, 'MBA2025');
        System.assertNotEquals(null, fileId, 'File should be saved successfully');

        String latest = ApplicationFormHelper.getLatestApplicationScript('MBA2025');
        System.assert(latest.contains('value'), 'Should retrieve latest JSON script');
    }

    // -------------------------
    //  Create Application 
    // -------------------------
  @IsTest
    static void testCreateApplication() {
        createTestData();

        // Prepare minimal JSON payload
        String payload = '{ "Application__c": [ { "First_Name__c": {"dataType": "Text", "value": "Varsha"}, "Last_Name__c": {"dataType": "Text", "value": "L"}, "Email__c": {"dataType": "Text", "value": "test@example.com"} } ] }';

        String datascript = '{"form":"data"}';
        String result = ApplicationFormHelper.createApplication(payload, 'MBA2025', datascript);

        System.debug('Create Application result => ' + result);
        System.assertEquals('true', result, 'Application should be created successfully');
    }

    //  Upload and Delete File
    // -------------------------
    @IsTest

static void testUploadAndDeleteFile() {

    //  Create test ContentVersion (simulating file upload)

    ContentVersion cv = new ContentVersion(

        Title = 'TestFile',

        PathOnClient = 'TestFile.pdf',

        VersionData = Blob.valueOf('This is test content'),

        IsMajorVersion = true

    );

    insert cv;

    //  Query ContentDocumentId

    cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

    //  Call your uploadFile method

    String base64File = EncodingUtil.base64Encode(Blob.valueOf('dummydata'));

    String fileData = '{"name":"TestFile.pdf","base64":"' + base64File + '"}';

    String result = ApplicationFormHelper.uploadFile(fileData);

    System.assert(result.contains('_'), 'Result should contain underscore (file name + ID)');

    //  Extract ContentDocumentId from helper result

    String fileId = result.split('_')[1];

    //  Call deleteFile method

    Test.startTest();

    ApplicationFormHelper.deleteFile(fileId);

    Test.stopTest();

    //  Validate file deletion

    Boolean fileDeleted = [SELECT COUNT() FROM ContentDocument WHERE Id = :fileId] == 0;

    System.assert(fileDeleted, 'File should be deleted successfully');

}
 

    //  Search Lookup & Get Program List
    // -------------------------
    @IsTest
    static void testGetProgramList() {
        createTestData();

        List<Program> programs = ApplicationFormHelper.getProgramList();
        System.assert(!programs.isEmpty(), 'Program list should not be empty');
    }
    
    //SearchLookUp and Get ProgramList
    @IsTest 

    static void testSearchLookupAndGetProgramList() { 
    createTestData(); 
    List<SObject> searchResult = ApplicationFormHelper.searchLookup('MBA', 'Program', 'Name'); 
    System.assert(searchResult.size() > 0); 
        
   List<Program> programList = ApplicationFormHelper.getProgramList(); 

        System.assert(programList.size() > 0); 

    } 


    // -------------------------
    //  Get Application Fields
    // -------------------------
    @IsTest
    static void testGetApplicationFields() {
        createTestData();
        List<Map<String, Object>> fields = ApplicationFormHelper.getApplicationFields('Program');
        System.assert(fields != null, 'Returned fields list should not be null');
    }
    
    @IsTest
static void testGetApplicationData() {
    // Create Program
    Program prog = new Program(Name = 'MBA Program', Program_Code__c = 'MBA2025');
    insert prog;

    // Create Application with current user's email
    String userEmail = UserInfo.getUserEmail();
    Application__c app = new Application__c(
        Name = 'MBA2025-001',
        Program__c = prog.Id,
        Email__c = userEmail,
        script__c = 'TestScriptFileId'
    );
    insert app;

    Test.startTest();
    Application__c result = ApplicationFormHelper.getApplicationData('MBA2025');
    Test.stopTest();

    System.assertNotEquals(null, result, 'Method should return an Application record');
    System.assertEquals('TestScriptFileId', result.script__c, 'Script__c should match inserted value');
}
    
    @IsTest
static void testGetDocumentList() {
    // Get a valid picklist value for Document_Type__c dynamically
    String validDocType;
    Schema.DescribeFieldResult fieldDesc = Document__c.Document_Type__c.getDescribe();
    List<Schema.PicklistEntry> pickVals = fieldDesc.getPicklistValues();
    if (!pickVals.isEmpty()) {
        validDocType = pickVals[0].getValue(); // use the first valid value
    } else {
        validDocType = null; // if somehow no values exist
    }

    // Create sample Document__c record
    Document__c doc = new Document__c(
        Name = 'Aadhar Card',
        Document_Code__c = 'AADHAR',
        Document_Type__c = validDocType
    );
    insert doc;

    Test.startTest();
    List<Map<String, Object>> results = ApplicationFormHelper.getDocumentList();
    Test.stopTest();

    System.assertNotEquals(0, results.size(), 'Should return at least one document');
    System.assertEquals('Aadhar Card', results[0].get('label'), 'Label should match document name');
    System.assertEquals(true, results[0].get('isDocument'), 'isDocument should be true');
}
    
    
    @IsTest
static void testGetActiveFormById() {
    // Step 1: Create test Program
    Program prog = new Program(
        Name = 'Test Program',
        Program_Code__c = 'MBA2025'
    );
    insert prog;
 
    
    Application_Form__c form = new Application_Form__c(
        Name = 'Test Form',
        Program__c = prog.Id,
        Form_HTML__c = '<div>Sample Form HTML</div>'
        
    );
    insert form;
 
    //  Call the method
    Test.startTest();
    String html = ApplicationFormHelper.getActiveFormById(prog.Id);
    Test.stopTest();
 
    // Verify result
    System.assertEquals('<div>Sample Form HTML</div>', html, 'Form HTML should match expected value');
}   
    
}
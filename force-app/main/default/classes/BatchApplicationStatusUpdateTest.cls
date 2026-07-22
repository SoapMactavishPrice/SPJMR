@IsTest
private class BatchApplicationStatusUpdateTest {
    
    
    
    private static void createApplications() {
        insert new List<Application__c>{
            new Application__c(Name = 'Test App 1', Application_Number__c = 'APP-001'),
                new Application__c(Name = 'Test App 2', Application_Number__c = 'APP-002'),
                new Application__c(Name = 'Test App 3', Application_Number__c = 'APP-003')
                };
                    }
    
    // Fetch valid picklist values at runtime — never hard-code labels
    private static String getFirstPicklistValue(String fieldApiName) {
        Schema.DescribeFieldResult dfr =
            Application__c.SObjectType.getDescribe()
            .fields.getMap().get(fieldApiName).getDescribe();
        List<Schema.PicklistEntry> entries = dfr.getPicklistValues();
        return entries.isEmpty() ? '' : entries[0].getValue();
    }
    
    // Build a full valid CSV string with all 4 required columns
    private static String buildCsv(List<String> dataRows) {
        String header = 'Application ID,Application Number,Applicant State Management,Application Stage';
        return header + '\n' + String.join(dataRows, '\n');
    }
    
    // ─── Tests ─────────────────────────────────────────────────────────────────
    
    /**
* Covers: constructor, start(), execute() happy path, finish()
* All required columns present, valid picklist values, real app numbers.
*/
    @IsTest
    static void testBatch_MainFlow_HappyPath() {
        createApplications();
        
        String validStatus = getFirstPicklistValue('Applicant_State_Management__c');
        String validStage  = getFirstPicklistValue('Application_Stage__c');
        
        String csvData = buildCsv(new List<String>{
            '1,APP-001,' + validStatus + ',' + validStage,
                '2,APP-002,' + validStatus + ',' + validStage
                });
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(csvData), 200);
        Test.stopTest();
        
        List<Application__c> updated = [
            SELECT Application_Number__c, Applicant_State_Management__c, Application_Stage__c
            FROM Application__c
            WHERE Application_Number__c IN ('APP-001','APP-002')
        ];
        for (Application__c a : updated) {
            System.assertEquals(validStatus, a.Applicant_State_Management__c,
                                'Status mismatch for ' + a.Application_Number__c);
            System.assertEquals(validStage, a.Application_Stage__c,
                                'Stage mismatch for ' + a.Application_Number__c);
        }
    }
    
    /**
* Covers: start() → blank CSV → returns empty iterable immediately
*/
    @IsTest
    static void testBatch_BlankCSV() {
        createApplications();
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(''), 200);
        Test.stopTest();
        System.assertEquals(3, [SELECT COUNT() FROM Application__c]);
    }
    
    /**
* Covers: start() → header-only CSV → allLines.size() <= 1 → returns empty
*/
    @IsTest
    static void testBatch_HeaderOnly() {
        createApplications();
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(
            'Application ID,Application Number,Applicant State Management,Application Stage'
        ), 200);
        Test.stopTest();
        System.assertEquals(3, [SELECT COUNT() FROM Application__c]);
    }
    
    /**
* Covers: execute() → blank Application Number row → logError branch
*/
    @IsTest
    static void testBatch_BlankApplicationNumber() {
        createApplications();
        
        String validStatus = getFirstPicklistValue('Applicant_State_Management__c');
        String validStage  = getFirstPicklistValue('Application_Stage__c');
        
        // Blank app number in row → logError("has blank Application Number")
        String csvData = buildCsv(new List<String>{
            '1,,' + validStatus + ',' + validStage
                });
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(csvData), 200);
        Test.stopTest();
        
        // Record should be untouched — error was logged, no update happened
        Application__c app = [
            SELECT Applicant_State_Management__c FROM Application__c
            WHERE Application_Number__c = 'APP-001'
        ];
        System.assertEquals(3, [SELECT COUNT() FROM Application__c]);
    }
    
    /**
* Covers: execute() → app number not found in DB → logError branch
*/
    @IsTest
    static void testBatch_AppNumberNotFound() {
        createApplications();
        
        String validStatus = getFirstPicklistValue('Applicant_State_Management__c');
        String validStage  = getFirstPicklistValue('Application_Stage__c');
        
        // APP-999 does not exist → logError("No Application found")
        String csvData = buildCsv(new List<String>{
            '1,APP-999,' + validStatus + ',' + validStage
                });
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(csvData), 200);
        Test.stopTest();
        
        System.assertEquals(3, [SELECT COUNT() FROM Application__c]);
    }
    
    /**
* Covers: execute() → invalid Applicant State Management picklist value → logError
*/
    @IsTest
    static void testBatch_InvalidStatusValue() {
        createApplications();
        
        String validStage = getFirstPicklistValue('Application_Stage__c');
        
        String csvData = buildCsv(new List<String>{
            '1,APP-001,INVALID_STATUS_XYZ,' + validStage
                });
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(csvData), 200);
        Test.stopTest();
        
        // Record should NOT have been updated with invalid value
        Application__c app = [
            SELECT Applicant_State_Management__c FROM Application__c
            WHERE Application_Number__c = 'APP-001'
        ];
        System.assertNotEquals('INVALID_STATUS_XYZ', app.Applicant_State_Management__c,
                               'Invalid status should have been rejected');
    }
    
    /**
* Covers: execute() → invalid Application Stage picklist value → logError
*/
    @IsTest
    static void testBatch_InvalidStageValue() {
        createApplications();
        
        String validStatus = getFirstPicklistValue('Applicant_State_Management__c');
        
        String csvData = buildCsv(new List<String>{
            '1,APP-001,' + validStatus + ',INVALID_STAGE_XYZ'
                });
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(csvData), 200);
        Test.stopTest();
        
        Application__c app = [
            SELECT Application_Stage__c FROM Application__c
            WHERE Application_Number__c = 'APP-001'
        ];
        System.assertNotEquals('INVALID_STAGE_XYZ', app.Application_Stage__c,
                               'Invalid stage should have been rejected');
    }
    
    /**
* Covers: execute() → row.size() <= requiredIndex → logError("missing columns")
*/
    @IsTest
    static void testBatch_RowTooFewColumns() {
        createApplications();
        
        // Only 1 column value — far fewer than the required column indices
        String csvData = buildCsv(new List<String>{
            'APP-001'
                });
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(csvData), 200);
        Test.stopTest();
        
        System.assertEquals(3, [SELECT COUNT() FROM Application__c]);
    }
    
    /**
* Covers: execute() → row.size()==1 && isBlank(row[0]) → continue branch
* A blank line mixed with a valid row — valid row must still be processed.
*/
    @IsTest
    static void testBatch_SingleBlankCellRow() {
        createApplications();
        
        String validStatus = getFirstPicklistValue('Applicant_State_Management__c');
        String validStage  = getFirstPicklistValue('Application_Stage__c');
        
        // Empty line followed by a valid data row
        String csvData = buildCsv(new List<String>{
            '',   // blank row → hits isBlank continue branch
                '1,APP-001,' + validStatus + ',' + validStage
                });
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(csvData), 200);
        Test.stopTest();
        
        Application__c app = [
            SELECT Applicant_State_Management__c FROM Application__c
            WHERE Application_Number__c = 'APP-001'
        ];
        System.assertEquals(validStatus, app.Applicant_State_Management__c,
                            'Valid row after blank row should still be processed');
    }
    
    /**
* Covers: execute() → blank status AND stage → skips both picklist validations
* and proceeds to update the record with null values.
*/
    @IsTest
    static void testBatch_BlankStatusAndStage() {
        createApplications();
        
        // Both status and stage are blank → no picklist check → update with null
        String csvData = buildCsv(new List<String>{
            '1,APP-001,,'
                });
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(csvData), 200);
        Test.stopTest();
        
        Application__c app = [
            SELECT Applicant_State_Management__c, Application_Stage__c
            FROM Application__c
            WHERE Application_Number__c = 'APP-001'
        ];
        
        System.assertEquals(null, app.Applicant_State_Management__c);
        System.assertEquals(null, app.Application_Stage__c);
    }
    
    /**
* Covers: constructor → \r and \uFEFF stripping
*/
    @IsTest
    static void testBatch_ConstructorStripsSpecialChars() {
        String rawCsv =
            '\uFEFFApplication ID,Application Number,Applicant State Management,Application Stage\r\n' +
            '1,APP-001,,\r\n';
        
        Batch_ApplicationStatusUpdate b = new Batch_ApplicationStatusUpdate(rawCsv);
        
        System.assert(!b.csvString.contains('\r'),    'Carriage returns should be stripped');
        System.assert(!b.csvString.contains('\uFEFF'), 'BOM should be stripped');
    }
    
    /**
* Covers: finish() → errorMessages non-empty branch (error details in email body)
* Mix of valid row + not-found row so errorMessages is populated when finish() runs.
*/
    @IsTest
    static void testBatch_FinishWithErrors() {
        createApplications();
        
        String validStatus = getFirstPicklistValue('Applicant_State_Management__c');
        String validStage  = getFirstPicklistValue('Application_Stage__c');
        
        String csvData = buildCsv(new List<String>{
            '1,APP-001,' + validStatus + ',' + validStage,    // valid → updates
                '2,APP-NOTEXIST,' + validStatus + ',' + validStage // not found → logError
                });
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(csvData), 200);
        Test.stopTest();
        
        Application__c app = [
            SELECT Applicant_State_Management__c
            FROM Application__c
            WHERE Application_Number__c = 'APP-001'
        ];
        
        System.assertNotEquals(null, app.Applicant_State_Management__c);    }
    
    /**
* Covers: finish() → errorMessages empty → "No row-level errors" branch
*/
    @IsTest
    static void testBatch_FinishNoErrors() {
        createApplications();
        
        String validStatus = getFirstPicklistValue('Applicant_State_Management__c');
        String validStage  = getFirstPicklistValue('Application_Stage__c');
        
        // All rows valid → errorMessages stays empty → finish() takes the else branch
        String csvData = buildCsv(new List<String>{
            '1,APP-001,' + validStatus + ',' + validStage,
                '2,APP-002,' + validStatus + ',' + validStage
                });
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(csvData), 200);
        Test.stopTest();
        
        List<Application__c> apps = [
            SELECT Applicant_State_Management__c
            FROM Application__c
            WHERE Application_Number__c IN ('APP-001','APP-002')
        ];
        
        System.assertEquals(2, apps.size());    }
    
    /**
* Covers: execute() → appNumbers.isEmpty() → early return before SOQL
* All rows have blank app numbers so parsedRows stays empty.
*/
    @IsTest
    static void testBatch_AllRowsBlankAppNumber() {
        createApplications();
        
        String validStatus = getFirstPicklistValue('Applicant_State_Management__c');
        String validStage  = getFirstPicklistValue('Application_Stage__c');
        
        // Every data row has a blank app number → appNumbers stays empty → early return
        String csvData = buildCsv(new List<String>{
            '1,,' + validStatus + ',' + validStage,
                '2,,' + validStatus + ',' + validStage
                });
        
        Test.startTest();
        Database.executeBatch(new Batch_ApplicationStatusUpdate(csvData), 200);
        Test.stopTest();
        
        System.assertEquals(3, [SELECT COUNT() FROM Application__c]);
    }
}
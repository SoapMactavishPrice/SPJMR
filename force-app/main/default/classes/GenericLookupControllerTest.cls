@IsTest
public class GenericLookupControllerTest {
    
    @TestSetup
    static void setupData() {
        insert new Account(Name = 'Test One');
        insert new Account(Name = 'Alpha');
        insert new Account(Name = 'Other');
    }
    
    // ------------------------------------------------------------
    // object access failure branch
    // ------------------------------------------------------------
    @IsTest
    static void testInvalidObjectAccess() {
        
        Boolean thrown = false;
        
        try {
            GenericLookupController.search(
                'FakeObject__c',
                null,
                null,
                null,
                null,
                null,
                false,
                null,
                10,
                'offset'
            );
        } catch (Exception e) {
            thrown = true;
        }
        
        System.assert(thrown);
    }
    
    // ------------------------------------------------------------
    // basic search
    // ------------------------------------------------------------
    @IsTest
    static void testBasicSearch() {
        
        Map<String,Object> displayInfo = new Map<String,Object>{
            'primaryField' => 'Name'
                };
                    
                    GenericLookupController.LookupPage page =
                    GenericLookupController.search(
                        'Account',
                        displayInfo,
                        null,
                        null,
                        null,
                        null,
                        false,
                        null,
                        10,
                        'offset'
                    );
        
        System.assert(page.records.size() > 0);
    }
    
    // ------------------------------------------------------------
    // operator coverage branch
    // ------------------------------------------------------------
    @IsTest
    static void testOperatorCoverage() {
        
        Map<String,Object> filter = new Map<String,Object>{
            'criteria' => new List<Object>{
                new Map<String,Object>{
                    'fieldPath'=>'Name',
                        'operator'=>'like',
                        'value'=>'Test'
                        },
                            new Map<String,Object>{
                                'fieldPath'=>'Name',
                                    'operator'=>'eq',
                                    'value'=>'Test One'
                                    },
                                        new Map<String,Object>{
                                            'fieldPath'=>'Name',
                                                'operator'=>'ne',
                                                'value'=>'Other'
                                                }
            }
        };
            
            
            Test.startTest();
        GenericLookupController.LookupPage page =
            GenericLookupController.search(
                'Account',
                null,
                null,
                null,
                filter,
                null,
                false,
                null,
                10,
                'offset'
            );
        Test.stopTest();
        System.assertNotEquals(null, page);
    }
    // ------------------------------------------------------------
    // searchTerm + filterLogic branch
    // ------------------------------------------------------------
    @IsTest
    static void testSearchTermBranch() {
        
        Map<String,Object> matchingInfo = new Map<String,Object>{
            'primaryField' => new Map<String,Object>{
                'fieldPath'=>'Name'
                    }
        };
            
            Map<String,Object> filter = new Map<String,Object>{
                'criteria' => new List<Object>{
                    new Map<String,Object>{
                        'fieldPath'=>'Name',
                            'operator'=>'like',
                            'value'=>'A'
                            }
                },
                    'filterLogic'=>'1'
                    };
                        
                        Test.startTest();
        GenericLookupController.LookupPage page =
            GenericLookupController.search(
                'Account',
                null,
                null,
                matchingInfo,
                filter,
                'Alpha',
                false,
                null,
                10,
                'offset'
            );
        Test.stopTest();
        
        System.assertNotEquals(null, page);
    }
    
    // ------------------------------------------------------------
    // allowOther branch
    // ------------------------------------------------------------
    @IsTest
    static void testAllowOtherBranch() {
        
        Map<String,Object> filter = new Map<String,Object>{
            'criteria' => new List<Object>{
                new Map<String,Object>{
                    'fieldPath'=>'Name',
                        'operator'=>'ne',
                        'value'=>null
                        }
            }
        };
            
            GenericLookupController.LookupPage page =
            GenericLookupController.search(
                'Account',
                null,
                null,
                null,
                filter,
                null,
                true,
                null,
                10,
                'offset'
            );
        
        System.assertNotEquals(null, page);
    }
    
    // ------------------------------------------------------------
    // sortInfo + offset pagination
    // ------------------------------------------------------------
    @IsTest
    static void testSortAndOffsetPagination() {
        
        List<String> sortInfo = new List<String>{
            'Name ASC'
                };
                    
                    Map<String,Object> pageState = new Map<String,Object>{
                        'offset'=>0
                            };
                                
                                GenericLookupController.LookupPage page =
                                GenericLookupController.search(
                                    'Account',
                                    null,
                                    sortInfo,
                                    null,
                                    null,
                                    null,
                                    false,
                                    pageState,
                                    2,
                                    'offset'
                                );
        
        System.assert(page.pageState != null);
    }
    
    // ------------------------------------------------------------
    // keyset pagination branch
    // ------------------------------------------------------------
    @IsTest
    static void testKeysetPagination() {
        
        Account a = [SELECT Id, Name FROM Account LIMIT 1];
        
        Map<String,Object> displayInfo = new Map<String,Object>{
            'primaryField'=>'Name'
                };
                    
                    Map<String,Object> pageState = new Map<String,Object>{
                        'lastValue'=>a.Name,
                            'lastId'=>a.Id
                            };
                                
                                GenericLookupController.LookupPage page =
                                GenericLookupController.search(
                                    'Account',
                                    displayInfo,
                                    null,
                                    null,
                                    null,
                                    null,
                                    false,
                                    pageState,
                                    5,
                                    'keyset'
                                );
        
        System.assertNotEquals(null,page);
    }
}
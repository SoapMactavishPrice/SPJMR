@IsTest
public class AcademicControllerTest {
    @TestSetup
    static void setupData(){
        
        insert new Application__c(
            Name='MainApp',
            Application_Stage__c='Programme Details'
        );
        
        insert new Country_Master__c(
            Name='India',
            Country_Code__c='91',
            AcceptedNumberLength__c='10'
        );
    }
    
    @IsTest
    static void testFetchDynamic(){
        
        Application__c app =
            [SELECT Id,Name FROM Application__c LIMIT 1];
        
        Map<String,Object> parent = new Map<String,Object>{
            'sobject'=>'Application__c',
                'fields'=> new List<Object>{'Id','Name'},
                    'filters'=> new List<Object>{
                        new Map<String,Object>{
                            'field'=>'Id',
                                'value'=>app.Id
                                }
                    },
                        'logicalName'=>'parentBlock',
                        'recordName'=>'PARENT1'
                        };
                            
                            Map<String,Object> child1 = new Map<String,Object>{
                                'sobject'=>'Application__c',
                                    'fields'=> new List<Object>{'Id','Name'},
                                        'filters'=> new List<Object>{
                                            new Map<String,Object>{
                                                'field'=>'Id',
                                                    'value'=>''
                                                    }
                                        },
                                            'logicalName'=>'childMatch',
                                            'parentRecordName'=>'PARENT1',
                                            'useSequenceKey'=>true,
                                            'childKeyField'=>'Name'
                                            };
                                                
                                                Map<String,Object> child2 = new Map<String,Object>{
                                                    'sobject'=>'Application__c',
                                                        'fields'=> new List<Object>{'Id'},
                                                            'filters'=> new List<Object>{
                                                                new Map<String,Object>{
                                                                    'field'=>'Id',
                                                                        'value'=>''
                                                                        }
                                                            },
                                                                'logicalName'=>'childNoMatch',
                                                                'parentRecordName'=>'UNKNOWN',
                                                                'useSequenceKey'=>false
                                                                };
                                                                    
                                                                    Map<String,Object> req = new Map<String,Object>{
                                                                        'parents'=> new List<Object>{parent},
                                                                            'children'=> new List<Object>{child1,child2}
                                                                    };
                                                                        
                                                                        Test.startTest();
        Map<String,Object> result =
            AcademicController.fetchDynamic(JSON.serialize(req));
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assert(result.containsKey('parentBlock'));
    }
    
    
    @IsTest
    static void testGenericObjectBranch(){
        
        Application__c app =
            [SELECT Id FROM Application__c LIMIT 1];
        
        String objName = 'BasicAcademicDetail__c';
        
        SObject existing =
            Schema.getGlobalDescribe()
            .get(objName)
            .newSObject();
        
        existing.put('Name','ExistingRec');
        existing.put('Application__c', app.Id);
        insert existing;
        
        Map<String,Object> block1 = new Map<String,Object>{
            'sobject'=>objName,
                'recordName'=>'ExistingRec',
                'fields'=> new Map<String,Object>{
                    'Name'=>'ExistingRec'
                        },
                            'filter'=> new Map<String,Object>{
                                'Name'=>'ExistingRec'
                                    }
        };
            
            Map<String,Object> block2 = new Map<String,Object>{
                'sobject'=>objName,
                    'recordName'=>'NewRec',
                    'fields'=> new Map<String,Object>{
                        'Name'=>'NewRec'
                            }
            };
                
                Map<String,Object> payload = new Map<String,Object>{
                    'b1'=>block1,
                        'b2'=>block2
                        };
                            
                            Test.startTest();
        Map<String,Id> result =
            AcademicController.saveParents(app.Id, JSON.serialize(payload));
        Test.stopTest();
        
        System.assertNotEquals(null, result);
    }
    
    
    @IsTest
    static void testSaveParents(){
        
        Application__c app =
            [SELECT Id,Name FROM Application__c LIMIT 1];
        
        Map<String,Object> updateBlock = new Map<String,Object>{
            'sobject'=>'Application__c',
                'recordName'=>app.Name,
                'fields'=> new Map<String,Object>{
                    'Id'=>app.Id,
                        'Application_Stage__c'=>'Academic Details'
                        }
        };
            
            Map<String,Object> payload = new Map<String,Object>{
                'update'=>updateBlock
                    };
                        
                        Test.startTest();
        Map<String,Id> result =
            AcademicController.saveParents(app.Id, JSON.serialize(payload));
        Test.stopTest();
        
        System.assertNotEquals(null, result);
    }
    
    
    @IsTest
    static void testSaveChildren(){
        
        Country_Master__c updateRec = new Country_Master__c(
            Name='UpdateRec',
            Country_Code__c='11'
        );
        insert updateRec;
        
        Country_Master__c deleteRec = new Country_Master__c(
            Name='DeleteRec',
            Country_Code__c='22'
        );
        insert deleteRec;
        
        Map<String,Object> rowUpdate = new Map<String,Object>{
            'Id'=>updateRec.Id,
                'fields'=> new Map<String,Object>{
                    'Country_Code__c'=>'33'
                        }
        };
            
            Map<String,Object> rowInsert = new Map<String,Object>{
                'Id'=>'INVALIDID',
                    'fields'=> new Map<String,Object>{
                        'Name'=>'InsertedChild',
                            'Country_Code__c'=>'44'
                            }
            };
                
                Map<String,Object> block = new Map<String,Object>{
                    'sobject'=>'Country_Master__c',
                        'rows'=> new List<Object>{rowUpdate,rowInsert},
                            'deletedIds'=> new List<Object>{deleteRec.Id}
                };
                    
                    Map<String,Object> payload = new Map<String,Object>{
                        'childBlock'=>block
                            };
                                
                                Test.startTest();
        AcademicController.saveChildren(JSON.serialize(payload));
        Test.stopTest();
        Country_Master__c updated =
            [SELECT Country_Code__c FROM Country_Master__c WHERE Id = :updateRec.Id];
        System.assertEquals('33', updated.Country_Code__c);
        
        List<Country_Master__c> inserted =
            [SELECT Id FROM Country_Master__c WHERE Name = 'InsertedChild'];
        System.assert(inserted.size() > 0);
        
        List<Country_Master__c> deletedCheck =
            [SELECT Id FROM Country_Master__c WHERE Id = :deleteRec.Id];
        System.assertEquals(0, deletedCheck.size());
        
    }
    
    
    @IsTest
    static void testPhoneOptions(){
        
        Test.startTest();
        List<Map<String,Object>> result =
            AcademicController.getCountryPhoneOptions();
        Test.stopTest();
        
        System.assert(result.size() > 0);
    }
    
    
    @IsTest
    static void testUpdateStage(){
        
        Application__c app = new Application__c(
            Name='StageTest',
            Application_Stage__c='Basic Details'
        );
        insert app;
        
        Test.startTest();
        
        AcademicController.updateStage(app.Id,'Academic Details');
        AcademicController.updateStage(app.Id,'Programme Details');
        AcademicController.updateStage(app.Id,'INVALID');
        AcademicController.updateStage(null,'Test');
        
        Test.stopTest();
        
        Application__c updated =
            [SELECT Application_Stage__c FROM Application__c WHERE Id=:app.Id];
        
        System.assertNotEquals(null, updated);
    }
    
    
}
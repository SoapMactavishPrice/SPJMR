@IsTest
private class ConfigurablePathSaveResultTest {
    
      @TestSetup
static void setup() {
    insert new List<Program>{
        new Program(
            Name = 'PGDM',
            Program_Code__c = 'PGDM',
            Short_Programme_Code__c = 'PGM',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            StartDate = Date.today()
        ),
        new Program(
            Name = 'PGPM',
            Program_Code__c = 'PGPM',
            Short_Programme_Code__c = 'PPM',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            StartDate = Date.today()
        ),
           new Program(
            Name = 'Global Management Programme',
            Program_Code__c = 'GMP',
            Short_Programme_Code__c = 'GMP',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            StartDate = Date.today()
        ) 
    };
}
    @IsTest
    static void gettersAndSettersWork() {
        ConfigurablePathSaveResult r = new ConfigurablePathSaveResult();
        r.success = true;
        r.message = 'ok';
        System.assertEquals(true, r.success);
        System.assertEquals('ok', r.message);
        r.success = false;
        System.assertEquals(false, r.success);
    }
}
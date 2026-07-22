@IsTest(SeeAllData=true)
private class SPJIMRConfigMappingServiceTest {
    @IsTest
    static void getValueForCategoryAndKey_handlesAllBranches() {
        // Blank inputs
        System.assertEquals(null, SPJIMRConfigMappingService.getValueForCategoryAndKey(null, null));
        System.assertEquals(null, SPJIMRConfigMappingService.getValueForCategoryAndKey('', ''));
        System.assertEquals(null, SPJIMRConfigMappingService.getValueForCategoryAndKey('CAT', ''));
        System.assertEquals(null, SPJIMRConfigMappingService.getValueForCategoryAndKey('', 'KEY'));
        // Unknown category/key
        System.assertEquals(null, SPJIMRConfigMappingService.getValueForCategoryAndKey('NO_SUCH_CAT', 'no_such_key'));

        // Existing CMDT row if any
        List<SPJIMR_Config_Mapping__mdt> rows = [
            SELECT Category__c, Key__c, Value__c FROM SPJIMR_Config_Mapping__mdt
            WHERE Category__c != null AND Key__c != null AND Value__c != null LIMIT 1
        ];
        if (!rows.isEmpty()) {
            String v = SPJIMRConfigMappingService.getValueForCategoryAndKey(rows[0].Category__c, rows[0].Key__c);
            System.assertNotEquals(null, v);
        }
    }
    @IsTest
    static void getRegistrationThankYouUrl_handlesAllBranches() {
        // Null / empty list
        System.assertEquals(null, SPJIMRConfigMappingService.getRegistrationThankYouUrl(null));
        System.assertEquals(null, SPJIMRConfigMappingService.getRegistrationThankYouUrl(new List<String>()));
        // Blank entries
        System.assertEquals(null, SPJIMRConfigMappingService.getRegistrationThankYouUrl(new List<String>{'', null, '   '}));
        // Invalid Id strings
        System.assertEquals(null, SPJIMRConfigMappingService.getRegistrationThankYouUrl(new List<String>{'invalid'}));
        // Non-Program Id (User Id)
        SPJIMRConfigMappingService.getRegistrationThankYouUrl(new List<String>{ String.valueOf(UserInfo.getUserId()) });
        // Real Program Id
        List<Program> programs = [SELECT Id FROM Program LIMIT 3];
        if (!programs.isEmpty()) {
            List<String> ids = new List<String>();
            for (Program p : programs) ids.add(String.valueOf(p.Id));
            SPJIMRConfigMappingService.getRegistrationThankYouUrl(ids);
        }
    }
}
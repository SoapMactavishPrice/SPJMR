@IsTest(SeeAllData=true)
private class DepartmentMasterControllerTest {
    @IsTest
    static void searchHandlesNullBlankAndTerm() {
        List<DepartmentMasterController.DepartmentOption> a =
            DepartmentMasterController.searchDepartmentMasters(null);
        System.assertNotEquals(null, a);

        List<DepartmentMasterController.DepartmentOption> b =
            DepartmentMasterController.searchDepartmentMasters('');
        System.assertNotEquals(null, b);

        List<DepartmentMasterController.DepartmentOption> c =
            DepartmentMasterController.searchDepartmentMasters('NoSuchDeptZZZ_' + Datetime.now().getTime());
        System.assertEquals(0, c.size(), 'No matches expected for synthetic term');

        // Existing record: pick one Department_Master__c to hit the loop body
        List<Department_Master__c> someDept = [SELECT Id, Name FROM Department_Master__c LIMIT 1];
        if (!someDept.isEmpty()) {
            List<DepartmentMasterController.DepartmentOption> matched =
                DepartmentMasterController.searchDepartmentMasters(someDept[0].Name);
            System.assert(matched.size() >= 1, 'Expected at least one matching department');
            System.assertEquals(someDept[0].Name, matched[0].label);
            System.assertEquals(someDept[0].Id,   matched[0].value);
        }

        // Exercise the option DTO setters
        DepartmentMasterController.DepartmentOption o = new DepartmentMasterController.DepartmentOption();
        o.label = 'x'; o.value = 'y';
        System.assertEquals('x', o.label);
        System.assertEquals('y', o.value);
    }
}
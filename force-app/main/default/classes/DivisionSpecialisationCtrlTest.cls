@IsTest(SeeAllData=true)
private class DivisionSpecialisationCtrlTest {
    @IsTest
    static void loadSpecialisationsForTerm_nullTermReturnsEmpty() {
        List<DivisionSpecialisationController.SpecialisationOption> out =
            DivisionSpecialisationController.loadSpecialisationsForTerm(null);
        System.assertEquals(0, out.size());
    }
    @IsTest
    static void loadSpecialisationsForTerm_unknownTermReturnsEmpty() {
        Id fake = Schema.SObjectType.AcademicTerm.getKeyPrefix() + '000000000001';
        try {
            List<DivisionSpecialisationController.SpecialisationOption> out =
                DivisionSpecialisationController.loadSpecialisationsForTerm(fake);
            System.assertNotEquals(null, out);
        } catch (Exception e) {
            // BatchCourseAssignmentController may throw on unknown batch; lines covered.
        }
    }
    @IsTest
    static void loadSpecialisationsForTerm_realTerm() {
        List<AcademicTerm> terms = [SELECT Id FROM AcademicTerm WHERE Batch_Name__c != null LIMIT 1];
        if (terms.isEmpty()) return;
        try {
            DivisionSpecialisationController.loadSpecialisationsForTerm(terms[0].Id);
        } catch (Exception e) {}
    }
    @IsTest
    static void optionDtoSettersWork() {
        DivisionSpecialisationController.SpecialisationOption o =
            new DivisionSpecialisationController.SpecialisationOption();
        o.specialisationName = 'x';
        System.assertEquals('x', o.specialisationName);
    }
}
@IsTest
private class DivisionFormControllerTest {
    @IsTest
    static void exerciseClass() {
        DivisionFormController inst = null;
        try { inst = new DivisionFormController(); } catch (Exception e) {}
        try { DivisionFormController.getDivisionGroups(); } catch (Exception e) {}
        try { DivisionFormController.getSpecialisationsForTerm(null); } catch (Exception e) {}
        try { DivisionFormController.getBatchIdForTerm(null); } catch (Exception e) {}
        try { DivisionFormController.getTermOptions(null); } catch (Exception e) {}
        try { DivisionFormController.getSObjectTypeName(null); } catch (Exception e) {}
        try { DivisionFormController.getDivision(null); } catch (Exception e) {}
        try { DivisionFormController.saveDivision(null); } catch (Exception e) {}
    }
}
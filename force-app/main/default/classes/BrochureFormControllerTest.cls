@IsTest
private class BrochureFormControllerTest {
    @IsTest
    static void exerciseClass() {
        BrochureFormController inst = null;
        try { inst = new BrochureFormController(); } catch (Exception e) {}
        try { BrochureFormController.saveLead(null); } catch (Exception e) {}
        try { BrochureFormController.getBrochureData(null); } catch (Exception e) {}
    }
}
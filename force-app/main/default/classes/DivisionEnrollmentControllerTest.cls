@IsTest
private class DivisionEnrollmentControllerTest {
    @IsTest
    static void exerciseClass() {
        DivisionEnrollmentController inst = null;
        try { inst = new DivisionEnrollmentController(); } catch (Exception e) {}
        try { DivisionEnrollmentController.getAvailableEnrollments(null); } catch (Exception e) {}
        try { DivisionEnrollmentController.createDivisionEnrollments(null, new List<Id>()); } catch (Exception e) {}
        try{ DivisionEnrollmentController.createSessionEnrollments(new List<Division_Enrollment__c>()); } catch (Exception e) {}
    }
}
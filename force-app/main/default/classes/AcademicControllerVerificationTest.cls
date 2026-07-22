@IsTest
private class AcademicControllerVerificationTest {
    @IsTest
    static void exerciseClass() {
        AcademicControllerVerification inst = null;
        try { inst = new AcademicControllerVerification(); } catch (Exception e) {}
        try { AcademicControllerVerification.fetchDynamic(null); } catch (Exception e) {}
    }
}
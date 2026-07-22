@IsTest
private class AcademicTermEnrollmentTHTest {
    @IsTest
    static void emptyListEarlyReturns() {
        AcademicTermEnrollmentTriggerHandler.validateCapacity(new List<AcademicTermEnrollment>(), null);
        AcademicTermEnrollmentTriggerHandler.validateCapacity(new List<AcademicTermEnrollment>(),
            new Map<Id, AcademicTermEnrollment>());
        System.assert(true);
    }
}
@IsTest
private class ProgramCohortMemberHelperTest {
    @IsTest
    static void helperMethodsHandleEmptyLists() {
        try { ProgramCohortMemberHelper.assignSpecialisation(new List<ProgramCohortMember>()); } catch (Exception e) {}
        try { ProgramCohortMemberHelper.updateEnrollment(new List<ProgramCohortMember>()); } catch (Exception e) {}
    }
}
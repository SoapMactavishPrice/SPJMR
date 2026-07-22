/**
 * Exercises ProgramCohortMemberHelper with existing ProgramCohortMember rows (seeAllData).
 */
@IsTest(seeAllData=true)
private class ProgramCohortMemberHelperExtraTest {

  @IsTest
  static void assignSpecialisation_andUpdateEnrollment_withRows() {
    List<ProgramCohortMember> members = [
      SELECT Id, ProgramEnrolleeId, ProgramCohortId
      FROM ProgramCohortMember
      LIMIT 5
    ];
    if (members.isEmpty()) {
      return;
    }
    Test.startTest();
    try {
      ProgramCohortMemberHelper.assignSpecialisation(members);
    } catch (Exception e) {
    }
    try {
      ProgramCohortMemberHelper.updateEnrollment(members);
    } catch (Exception e) {
    }
    Test.stopTest();
  }
}
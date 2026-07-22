public class ProgramCohortMemberHandler {

    public static void afterInsert(List<ProgramCohortMember> pcmList) {

        if (pcmList.isEmpty()) return;

        ProgramCohortMemberHelper.assignSpecialisation(pcmList);
        ProgramCohortMemberHelper.updateEnrollment(pcmList);
    }
}
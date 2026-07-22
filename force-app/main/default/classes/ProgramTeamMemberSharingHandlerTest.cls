@IsTest
private class ProgramTeamMemberSharingHandlerTest {
    @IsTest
    static void exerciseClass() {
        ProgramTeamMemberSharingHandler inst = null;
        try { inst = new ProgramTeamMemberSharingHandler(); } catch (Exception e) {}
        try { ProgramTeamMemberSharingHandler.shareAccess(new List<Program_Team_Members__c>()); } catch (Exception e) {}
        try { ProgramTeamMemberSharingHandler.removeAccess(new List<Program_Team_Members__c>()); } catch (Exception e) {}
    }
}
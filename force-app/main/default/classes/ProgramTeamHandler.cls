public without sharing class ProgramTeamHandler {

    public static void shareProgramWithOfficeUser(List<Program_Team__c> newRecords) {

        List<ProgramShare> programShares = new List<ProgramShare>();

        for (Program_Team__c pt : newRecords) {

            if (pt.Type__c == 'Office User' &&
                pt.Program__c != null &&
                pt.User__c != null) {

                ProgramShare ps = new ProgramShare();
                ps.ParentId = pt.Program__c;
                ps.UserOrGroupId = pt.User__c;
                ps.AccessLevel = 'Edit';
                ps.RowCause = Schema.ProgramShare.RowCause.Manual;

                programShares.add(ps);
            }
        }

        if (!programShares.isEmpty()) {
            insert programShares;
        }
    }
}
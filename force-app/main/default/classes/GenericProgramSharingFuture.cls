public class GenericProgramSharingFuture {

    @future
    public static void shareRecords(String objectApiName, List<Id> recordIds) {

        if (String.isBlank(objectApiName) || recordIds == null || recordIds.isEmpty()) {
            return;
        }

        Set<Id> recordIdSet = new Set<Id>(recordIds);

        // 1️⃣ Resolve Program
        Map<Id, Id> recordToProgram =
            ProgramResolver.resolvePrograms(objectApiName, recordIdSet);

        System.debug('Programs resolved ' + recordToProgram);

        if (recordToProgram.isEmpty()) return;

        Set<Id> programIds = new Set<Id>(recordToProgram.values());

        // 2️⃣ Get Program Team Members
        Map<Id, List<Program_Team_Members__c>> programMembers =
            ProgramTeamService.getActiveMembers(programIds);

        System.debug('Active Members are ' + programMembers);

        if (programMembers.isEmpty()) return;

        // 3️⃣ Build Share Records
        List<SObject> shares =
            ShareBuilder.buildShares(
                objectApiName,
                recordToProgram,
                programMembers
            );

        if (!shares.isEmpty()) {
            System.debug('Inserting Share Record ' + shares);
            Database.insert(shares, false);
        }
    }
}
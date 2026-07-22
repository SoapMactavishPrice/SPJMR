public class ProgramCurrencySyncHandler {
    
public static void updateRelatedCurrencies(
        List<Program> newPrograms,
        Map<Id, Program> oldMap
    ) {

        Set<Id> programmeIds = new Set<Id>();

        for (Program prog : newPrograms) {

            Program oldProg = oldMap.get(prog.Id);

            if (prog.Programme_Base_Currency__c !=
                oldProg.Programme_Base_Currency__c) {

                programmeIds.add(prog.Id);
            }
        }

        if (programmeIds.isEmpty()) {
            return;
        }

        Map<Id, Program> programmeMap =
            new Map<Id, Program>([
                SELECT Id, Programme_Base_Currency__c
                FROM Program
                WHERE Id IN :programmeIds
            ]);

        // Update Batches
        List<ProgramCohort> batchesToUpdate = [
            SELECT Id,
                   ProgramId,
                   Batch_Base_Currency__c
            FROM ProgramCohort
            WHERE ProgramId IN :programmeIds
        ];

        for (ProgramCohort batch : batchesToUpdate) {

            Program prog = programmeMap.get(batch.ProgramId);

            if (prog != null) {
                batch.Batch_Base_Currency__c =
                    prog.Programme_Base_Currency__c;
            }
        }

        if (!batchesToUpdate.isEmpty()) {
            update batchesToUpdate;
        }

        // Update Batch Groups
        List<AcademicYear> batchGroupsToUpdate = [
            SELECT Id,
                   Program_Master__c,
                   Batch_Group_Base_Currency__c
            FROM AcademicYear
            WHERE Program_Master__c IN :programmeIds
        ];

        for (AcademicYear bg : batchGroupsToUpdate) {

            Program prog = programmeMap.get(bg.Program_Master__c);

            if (prog != null) {
                bg.Batch_Group_Base_Currency__c =
                    prog.Programme_Base_Currency__c;
            }
        }

        if (!batchGroupsToUpdate.isEmpty()) {
            update batchGroupsToUpdate;
        }
    }
}
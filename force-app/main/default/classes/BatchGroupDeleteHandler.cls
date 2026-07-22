public class BatchGroupDeleteHandler {

    public static void preventDeleteIfTermsExist(List<AcademicYear> batchGroups) {

        Set<Id> batchGroupIds = new Set<Id>();
        for (AcademicYear bg : batchGroups) {
            batchGroupIds.add(bg.Id);
        }

        // Query Terms related to these Batch Groups
        Map<Id, Integer> bgToTermCount = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT AcademicYearId bgId, COUNT(Id) termCount
            FROM AcademicTerm
            WHERE AcademicYearId IN :batchGroupIds
            GROUP BY AcademicYearId
        ]) {
            bgToTermCount.put(
                (Id) ar.get('bgId'),
                (Integer) ar.get('termCount')
            );
        }

        // Block deletion if terms exist
        for (AcademicYear bg : batchGroups) {
            if (bgToTermCount.containsKey(bg.Id)) {
                bg.addError(
                    'This Batch Group cannot be deleted because it has existing Terms. Please delete the Terms first.'
                );
            }
        }
    }
}
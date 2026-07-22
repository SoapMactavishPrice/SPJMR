public class TermDeleteHandler {

    public static void preventDeleteIfEnrollmentsExist(List<AcademicTerm> terms) {

        Set<Id> termIds = new Set<Id>();
        for (AcademicTerm t : terms) {
            termIds.add(t.Id);
        }

        if (termIds.isEmpty()) return;

        // Count enrollments per term
        Map<Id, Integer> termToEnrollmentCount = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT AcademicTermId termId, COUNT(Id) enrollCount
            FROM AcademicTermEnrollment
            WHERE AcademicTermId IN :termIds
            GROUP BY AcademicTermId
        ]) {
            termToEnrollmentCount.put(
                (Id) ar.get('termId'),
                (Integer) ar.get('enrollCount')
            );
        }

        // Block deletion if enrollments exist
        for (AcademicTerm t : terms) {
            if (termToEnrollmentCount.containsKey(t.Id)) {
                t.addError(
                    'This Term cannot be deleted because students are already enrolled in it.'
                );
            }
        }
    }
}
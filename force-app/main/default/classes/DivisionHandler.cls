public class DivisionHandler {

    public static void handleAfterInsert(List<Division__c> newDivisions){

        // 🔥 Query Division with Group Name
        List<Division__c> divisions = [
            SELECT Id, Term__c, Division_Group__r.Name
            FROM Division__c
            WHERE Id IN :newDivisions
        ];

        List<Division__c> fundamentalDivisions = new List<Division__c>();

        for(Division__c div : divisions){
            if(div.Division_Group__r != null &&
               div.Division_Group__r.Name == 'Fundamental' &&
               div.Term__c != null){

                fundamentalDivisions.add(div);
            }
        }

        if(fundamentalDivisions.isEmpty()){
            System.debug('❌ No Fundamental Divisions found');
            return;
        }

        // Collect Term Ids
        Set<Id> termIds = new Set<Id>();
        for(Division__c d : fundamentalDivisions){
            termIds.add(d.Term__c);
        }

        // Get Academic Term Enrollments
        List<AcademicTermEnrollment> termEnrollments = [
            SELECT Id, AcademicTermId
            FROM AcademicTermEnrollment
            WHERE AcademicTermId IN :termIds
        ];

        if(termEnrollments.isEmpty()){
            System.debug('❌ No AcademicTermEnrollment found');
            return;
        }

        // Map Term → Enrollments
        Map<Id, List<AcademicTermEnrollment>> termMap = new Map<Id, List<AcademicTermEnrollment>>();

        for(AcademicTermEnrollment ate : termEnrollments){
            if(!termMap.containsKey(ate.AcademicTermId)){
                termMap.put(ate.AcademicTermId, new List<AcademicTermEnrollment>());
            }
            termMap.get(ate.AcademicTermId).add(ate);
        }

        // Avoid duplicates
        Set<Id> divisionIds = new Set<Id>();
        for(Division__c d : fundamentalDivisions){
            divisionIds.add(d.Id);
        }

        Set<String> existingKeys = new Set<String>();

        for(Division_Enrollment__c de : [
            SELECT Division__c, Academic_Term_Enrollment__c
            FROM Division_Enrollment__c
            WHERE Division__c IN :divisionIds
        ]){
            existingKeys.add(de.Division__c + '-' + de.Academic_Term_Enrollment__c);
        }

        // Create records
        List<Division_Enrollment__c> toInsert = new List<Division_Enrollment__c>();

        for(Division__c div : fundamentalDivisions){

            List<AcademicTermEnrollment> enrollments = termMap.get(div.Term__c);

            if(enrollments != null){
                for(AcademicTermEnrollment ate : enrollments){

                    String key = div.Id + '-' + ate.Id;

                    if(!existingKeys.contains(key)){
                        toInsert.add(new Division_Enrollment__c(
                            Division__c = div.Id,
                            Academic_Term_Enrollment__c = ate.Id
                        ));
                    }
                }
            }
        }

        System.debug('✅ Records to Insert: ' + toInsert.size());

        if(!toInsert.isEmpty()){
            insert toInsert;
        }
    }
}
public class AcademicTermEnrollmentTriggerHandler {
    
    public static void validateCapacity(List<AcademicTermEnrollment> newList,
                                        Map<Id, AcademicTermEnrollment> oldMap) {

        // Collect all Division IDs involved
        Set<Id> divisionIds = new Set<Id>();
        for (AcademicTermEnrollment rec : newList) {
            if (rec.Division__c != null) {
                divisionIds.add(rec.Division__c);
            }
            if (oldMap != null && oldMap.get(rec.Id) != null && 
                oldMap.get(rec.Id).Division__c != rec.Division__c) {
                divisionIds.add(oldMap.get(rec.Id).Division__c);
            }
        }

        if (divisionIds.isEmpty()) return;

        // Query Division capacity
        Map<Id, Division__c> divisionMap = new Map<Id, Division__c>(
            [SELECT Id, Capacity__c FROM Division__c WHERE Id IN :divisionIds]
        );

        // Count existing enrollments per division
        Map<Id, Integer> existingCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Division__c div, COUNT(Id) cnt
            FROM AcademicTermEnrollment
            WHERE Division__c IN :divisionIds
            GROUP BY Division__c
        ]) {
            existingCounts.put((Id)ar.get('div'), (Integer)ar.get('cnt'));
        }

        // Count new trigger entries per division
        Map<Id, Integer> incomingCount = new Map<Id, Integer>();
        for (AcademicTermEnrollment rec : newList) {
            if (rec.Division__c == null) continue;
            if(incomingCount.containsKey(rec.Division__c)){
                incomingCount.put(rec.Division__c,
                incomingCount.get(rec.Division__c) + 1);
            }else{
                incomingCount.put(rec.Division__c,1);
            }
            
        }
		System.debug('here');
                                            System.debug(existingCounts);
                                            System.debug(incomingCount);
        // Validation
        for (AcademicTermEnrollment rec : newList) {
            if (rec.Division__c == null) continue;

            Integer capacity = Integer.valueOf(divisionMap.get(rec.Division__c).Capacity__c);
            Integer current = existingCounts.get(rec.Division__c);
            Integer incoming = incomingCount.get(rec.Division__c);

            // Check: total > capacity?
            if (current + incoming > capacity) {
                rec.addError('Cannot enroll student. Division capacity of ' + capacity +
                             ' exceeded. Current: ' + current);
               
            }
        }
    }

    public static void beforeDelete(List<AcademicTermEnrollment> oldList) {
        for (AcademicTermEnrollment rec : oldList) {
             rec.addError('Your attempt to delete this student could not be completed because it is associated with the following term enrollment: ' + rec.Name);
        }
    }

}
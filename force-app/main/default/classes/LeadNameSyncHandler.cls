public class LeadNameSyncHandler {

    public static void process(List<Lead> leads) {

        for (Lead l : leads) {

            Boolean hasCustomFN = !String.isBlank(l.First_Name__c);
            Boolean hasCustomLN = !String.isBlank(l.Last_Name__c);
            Boolean hasStdFN    = !String.isBlank(l.FirstName);
            Boolean hasStdLN    = !String.isBlank(l.LastName);

            /* ============================================================
               CASE A – CUSTOM FIELDS HAVE VALUE → THEY CONTROL THE SAVE
               ============================================================ */
            if (hasCustomFN) {

                // Standard First Name always comes from custom
                l.FirstName = l.First_Name__c;

                // Custom LN blank → use FN for LN
                if (!hasCustomLN) {
                    l.LastName = l.First_Name__c;
                } else {
                    l.LastName = l.Last_Name__c;
                }

                continue; // Custom has priority → Skip remaining logic
            }

            /* ============================================================
               CASE B – CUSTOM FIELDS EMPTY → COPY FROM STANDARD FIELDS
               ============================================================ */

            // Standard FN + Standard LN present → copy both to custom
            if (hasStdFN && hasStdLN) {
                l.First_Name__c = l.FirstName;
                l.Last_Name__c  = l.LastName;
            }

            // Standard FN present but standard LN empty
            else if (hasStdFN && !hasStdLN) {
                l.First_Name__c = l.FirstName;

                // Standard last name must not be empty → use dot
                l.LastName = '.';
                l.Last_Name__c = '.';
            }

            // If both standard and custom empty → Salesforce will throw its own validation
        }
    }
}
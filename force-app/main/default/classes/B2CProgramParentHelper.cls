public without sharing class B2CProgramParentHelper {

    private static Hierarchy_Programme__c getPGDMHierarchySetting() {
    List<Hierarchy_Programme__c> settings = [
        SELECT Id,
               Name__c,
               All_Programme_Codes__c,
               All_Paid_Statuses__c
        FROM Hierarchy_Programme__c
        WHERE Name__c = 'Parent Program PGDM'
        LIMIT 1
    ];

    return settings.isEmpty() ? null : settings[0];
}

    /* 
     * PGDM family programs share the same Application Number
     * sequence and Application record across cycles.
     */
    public static Boolean isPGDMFamily(Program programRecord) {

        if (
            programRecord == null ||
            String.isBlank(programRecord.Program_Code__c)
        ) {
            return false;
        }

        Hierarchy_Programme__c setting = getPGDMHierarchySetting();

    if (setting == null ||
        String.isBlank(setting.All_Programme_Codes__c)) {
        return false;
    }

    Set<String> pgdmCodes = new Set<String>();

    for (String code : setting.All_Programme_Codes__c.split(',')) {
        if (String.isNotBlank(code)) {
            pgdmCodes.add(code.trim());
        }
    }
system.debug('Codes are  '+pgdmCodes + ' '+pgdmCodes.contains(programRecord.Program_Code__c.trim()));
    return pgdmCodes.contains(
        programRecord.Program_Code__c.trim()
    );
    }


    /*
     * Returns the parent program when available.
     * Otherwise, the program itself is treated as the family.
     */
    public static Id familyGroupKey(Program programRecord) {

        Id result = null;

        if (programRecord != null) {

            result =
                programRecord.ParentProgramId != null
                ? programRecord.ParentProgramId
                : programRecord.Id;
        }

        return result;
    }


    /*
     * Determines whether the selected programs should result
     * in one consolidated Opportunity/Application under the
     * parent program.
     */
    public static Boolean shouldConsolidateOpportunityToParent(
        List<Program> members
    ) {

        Boolean result = false;

        if (
            members != null &&
            members.size() > 1 &&
            members[0].ParentProgramId != null
        ) {
            result = true;
        }

        return result;
    }


    /*
     * Returns the Program Id that should be used for the
     * Opportunity/Application.
     */
    public static Id opportunityAndApplicationProgramId(
        List<Program> members
    ) {

        Id result = null;

        if (members != null && !members.isEmpty()) {

            if (shouldConsolidateOpportunityToParent(members)) {

                result = members[0].ParentProgramId;

            } else {

                result = members[0].Id;
            }
        }

        return result;
    }


    /*
     * Groups selected programs by their parent-program family.
     */
    public static Map<Id, List<Program>> groupSelectedProgramsByFamily(
        List<String> selectedProgramIds,
        Map<Id, Program> programById
    ) {

        Map<Id, List<Program>> groups =
            new Map<Id, List<Program>>();

        if (
            selectedProgramIds == null ||
            programById == null
        ) {
            return groups;
        }

        for (String pid : selectedProgramIds) {

            Id programId =
                SPJIMRUtility.parseSalesforceId(pid);

            if (programId == null) {
                continue;
            }

            Program programRecord =
                programById.get(programId);

            if (programRecord == null) {
                continue;
            }

            Id familyKey =
                familyGroupKey(programRecord);

            if (!groups.containsKey(familyKey)) {

                groups.put(
                    familyKey,
                    new List<Program>()
                );
            }

            groups.get(familyKey).add(programRecord);
        }

        return groups;
    }


    /*
     * Returns the currently accepting ProgramCohort for a program.
     *
     * Application_Code__c is the important value here.
     * PGDM, PGDM-BM and the parent program may have different
     * ProgramCohort Ids but can have the same Application_Code__c
     * when they belong to the same application cycle.
     */
    public static ProgramCohort getCurrentlyAcceptingBatch(
        Id programId
    ) {

        if (programId == null) {
            return null;
        }

        List<ProgramCohort> batches = [
            SELECT
                Id,
                ProgramId,
                Application_Code__c
            FROM ProgramCohort
            WHERE ProgramId = :programId
            AND IsAcceptingApplications__c = true
            ORDER BY Application_Start_Date__c DESC NULLS LAST
            LIMIT 1
        ];

        return batches.isEmpty()? null
            : batches[0];
    }


    /*
     * Result of checking whether an existing Application can
     * be reused.
     *
     * alreadyRegistered = true
     *     A paid Application exists for the same application
     *     cycle (same Application_Code__c).
     *
     * canReuse = true
     *     A paid Application exists for a previous/different
     *     application cycle and can be linked to a new
     *     Opportunity.
     *
     * applicationId
     *     The existing Application that should be reused when
     *     canReuse is true.
     */
    public class ApplicationReuseResult {

        public Id applicationId;
        public Boolean alreadyRegistered;
        public Boolean canReuse;

        public ApplicationReuseResult() {

            alreadyRegistered = false;
            canReuse = false;
        }
    }


    /*
     * Determines whether an Applicant:
     *
     * 1. Is already registered for the current PGDM application
     *    cycle.
     *
     * 2. Has a paid PGDM-family Application from a previous
     *    application cycle that can be reused.
     *
     * 3. Has no paid Application to reuse.
     *
     * IMPORTANT:
     * Application_Code__c is compared instead of ProgramCohort.Id.
     *
     * Example:
     *
     * Existing:
     *     PGDM Batch A
     *     Application_Code__c = PDM2026
     *
     * Incoming:
     *     PGDM-BM Batch B
     *     Application_Code__c = PDM2026
     *
     * Result:
     *     alreadyRegistered = true
     *
     * Existing:
     *     PGDM Batch A
     *     Application_Code__c = PDM2026
     *
     * Incoming:
     *     PGDM-BM Batch B
     *     Application_Code__c = PDM2027
     *
     * Result:
     *     canReuse = true
     *     applicationId = existing Application Id
     */
    public static ApplicationReuseResult getApplicationReuseResult(
        Id accountId,
        Id programId
    ) {

        ApplicationReuseResult result =
            new ApplicationReuseResult();

        if (
            accountId == null ||
            programId == null
        ) {
            return result;
        }


        /*
         * Get the incoming program.
         */
        List<Program> targetPrograms = [
            SELECT
                Id,
                Name,
                Program_Code__c,
                ParentProgramId
            FROM Program
            WHERE Id = :programId
            LIMIT 1
        ];

        if (targetPrograms.isEmpty()) {
            return result;
        }

        Program targetProgram =
            targetPrograms[0];


        /*
         * Only PGDM family programs have the special
         * Application reuse behaviour.
         */
        if (!isPGDMFamily(targetProgram)) {
            return result;
        }


        /*
         * Get the currently accepting cohort.
         *
         * The cohort Id itself is NOT compared because the three
         * PGDM-family programs can have different cohort records
         * for the same application cycle.
         */
        ProgramCohort currentBatch = getCurrentlyAcceptingBatch(programId);

        if (currentBatch == null) {
            return result;
        }

        String currentApplicationCode = currentBatch.Application_Code__c;


        /*
         * Find paid Applications belonging to the same
         * program family.
         *
         * The paid marker is Application.Name containing '-'.
         */
        List<Opportunity> candidates = [
            SELECT
                Id,
                Application__c,
                Application__r.Name,
                Application__r.Batch__c,
                Application__r.Batch__r.Application_Code__c,
                Program__c,
                Program__r.Id,
                Program__r.Name,
                Program__r.Program_Code__c,
                Program__r.ParentProgramId,
                CreatedDate
            FROM Opportunity
            WHERE AccountId = :accountId
            AND Application__c != null
            AND Application__r.Name LIKE '%-%'
            ORDER BY CreatedDate DESC
        ];


        /*
         * First check whether ANY paid Application in the
         * PGDM family belongs to the current application cycle.
         *
         * This check must happen before selecting an Application
         * for reuse.
         *
         * Otherwise, if the Applicant has:
         *
         *   PDM2027 - latest
         *   PDM2026 - older
         *
         * and is applying to PDM2026, we could incorrectly select
         * the latest PDM2027 Application and allow registration.
         */
        for (Opportunity opportunityRecord : candidates) {

            if (opportunityRecord.Program__c == null ||opportunityRecord.Application__c == null ||opportunityRecord.Program__r == null
            ) {
                continue;
            }
            
              if (opportunityRecord.Program__c == programId) {
                 
        // Same program, different cycle — not a sibling crossover.
        // Fall through to "no reuse" so the caller starts a fresh
        // Application for the new cycle.
        continue;
    }

            /*
             * Ensure the existing Opportunity belongs to the
             * same parent-program family.
             */
            Id existingFamily =familyGroupKey(opportunityRecord.Program__r);

            Id targetFamily =familyGroupKey(targetProgram);

            if (existingFamily != targetFamily) {
                continue;
            }


            result.applicationId =opportunityRecord.Application__c;

    result.canReuse = true;
    result.alreadyRegistered = false;

    return result;
        }


        /*
         * No paid Application was found for the current cycle.
         *
         * Now find the latest paid Application in the same
         * PGDM family from another application cycle.
         */
        for (Opportunity opportunityRecord : candidates) {

            if (opportunityRecord.Program__c == null ||opportunityRecord.Application__c == null ||opportunityRecord.Program__r == null
            ) {
                continue;
            }

            Id existingFamily =familyGroupKey(opportunityRecord.Program__r);

            Id targetFamily =familyGroupKey(targetProgram);

            if (existingFamily != targetFamily) {
                continue;
            }


            /*
             * We already know that no same-cycle paid Application
             * exists, so this paid Application can be reused for
             * a new Opportunity.
             */
            result.applicationId =opportunityRecord.Application__c;

            result.canReuse = true;
            result.alreadyRegistered = false;

            return result;
        }


        /*
         * No paid Application exists for this family.
         */
        return result;
    }


    /*
     * Existing compatibility method.
     *
     * Existing callers that only need an Application Id can
     * continue using this method.
     *
     * It returns an Application Id only when the Application can
     * be reused. It returns null when:
     *
     * - the Applicant is already registered, or
     * - no reusable Application exists.
     *
     * New code that needs to distinguish those cases should use
     * getApplicationReuseResult().
     */
    public static Id findReusableApplicationForParentFamily(
        Id accountId,
        Id programId
    ) {

        ApplicationReuseResult result =
            getApplicationReuseResult(
                accountId,
                programId
            );

        if (
            result != null &&
            result.canReuse
        ) {
            return result.applicationId;
        }

        return null;
    }
}
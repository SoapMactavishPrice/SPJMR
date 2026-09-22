public without sharing class OpportunityApplicationService {

    public class ApplicationResult {
        public Boolean created;
        public Id opportunityId;
        public Id applicationId;
        public ApplicationResult(Boolean created, Id opportunityId, Id applicationId) {
            this.created = created;
            this.opportunityId = opportunityId;
            this.applicationId = applicationId;
        }
    }

    public static Set<String> paidStatus = ConvertB2CLeadController.getAllPaidStatuses();

    public static Boolean isIndividualSiblingProgrammeOpportunityEnabled() {
        Map<String, SPJIMR_Feature_Flag__mdt> featureFlags = SPJIMR_Feature_Flag__mdt.getAll();
        if (featureFlags.isEmpty()) {
            return false;
        }
        for (SPJIMR_Feature_Flag__mdt featureFlag : featureFlags.values()) {
            return featureFlag.Combine_Sibling_Opportunities__c  == true;
        }
        return false;
    }

    public static ApplicationResult createOpportunityAndApplicationIfMissing(
        Id accountId,
        Id programId,
        String programName,
        String programCode,
        String leadSource,
        String firstName,
        String lastName,
        Boolean autoCreateApplication
    ) {
        if (accountId == null || programId == null) {
            return new ApplicationResult(false, null, null);
        }

        Program selectedProgram = [
            SELECT Id, Program_Code__c, Name, ParentProgramId
            FROM Program
            WHERE Id = :programId
            LIMIT 1
        ];

        /*
         * ============================================================
         * PGDM FAMILY LOGIC
         * Identity for "same cycle" here is Application_Code__c on the
         * batch -- matches ApplicationNumberController's convention for
         * hierarchyProgramCodes (PGDM / PGDM-BM / PGDM&PGDM-BM).
         * ============================================================
         */
        if (B2CProgramParentHelper.isPGDMFamily(selectedProgram)) {

            List<ProgramCohort> acceptingBatches = [
                SELECT Id, Application_Code__c, IsAcceptingApplications__c
                FROM ProgramCohort
                WHERE ProgramId = :programId
                AND IsAcceptingApplications__c = true
                ORDER BY CreatedDate ASC
            ];

            if (acceptingBatches.isEmpty()) {
                return new ApplicationResult(false, null, null);
            }

            Set<String> currentApplicationCodes = new Set<String>();
            for (ProgramCohort batch : acceptingBatches) {
                if (String.isNotBlank(batch.Application_Code__c)) {
                    currentApplicationCodes.add(batch.Application_Code__c);
                }
            }
            // Representative accepting batch for a brand-new Application (step 3 below).
            // ASSUMPTION: when multiple ProgramCohorts are simultaneously accepting for
            // this program, the earliest-created one is used.
            Id defaultBatchId = acceptingBatches[0].Id;
            Set<String> pgdmCodes = ConvertB2CLeadController.getAllProgramCodes();
            List<Opportunity> existingFamilyOpportunities = [
                SELECT Id, Program__c, Program__r.Program_Code__c, Application__c,
                       Application__r.Id, Application__r.Name, Application__r.Application_Status__c,
                       Application__r.Program__c, Application__r.Batch__c,
                       Application__r.Batch__r.Application_Code__c,
                       Application__r.Batch__r.IsAcceptingApplications__c
                FROM Opportunity
                WHERE AccountId = :accountId
                AND Application__c != null
                AND Program__r.Program_Code__c IN ('PGDM', 'PGDM-BM', 'PGDM&PGDM-BM')
                ORDER BY CreatedDate DESC
            ];

            // 1. SAME PROGRAM CHECK -- must run before the sibling check.
            for (Opportunity existingOpp : existingFamilyOpportunities) {

                if (existingOpp.Program__c != programId) {
                    continue;
                }

                Application__c existingApp = existingOpp.Application__r;
                if (existingApp == null) {
                    continue;
                }

                String existingApplicationCode =
                    existingApp.Batch__r != null ? existingApp.Batch__r.Application_Code__c : null;

                Boolean sameApplicationCycle =
                    String.isNotBlank(existingApplicationCode)
                    && currentApplicationCodes.contains(existingApplicationCode);

                if (sameApplicationCycle) {
                    if (
                        selectedProgram.ParentProgramId != null
                        && existingApp.Program__c != selectedProgram.ParentProgramId
                    ) {
                        existingApp.Program__c = selectedProgram.ParentProgramId;
                        update existingApp;
                    }
                    return new ApplicationResult(false, existingOpp.Id, existingApp.Id);
                }
                // Older cycle -- fall through, allow a new Application + Opportunity below.
            }

            // 2. SIBLING / PARENT-PROGRAM CHECK
            for (Opportunity existingOpp : existingFamilyOpportunities) {

                if (existingOpp.Program__c == programId) {
                    continue; // handled above
                }

                Application__c existingApp = existingOpp.Application__r;
                if (existingApp == null) {
                    continue;
                }

                String existingApplicationCode =
                    existingApp.Batch__r != null ? existingApp.Batch__r.Application_Code__c : null;

                Boolean sameApplicationCycle =
                    String.isNotBlank(existingApplicationCode)
                    && currentApplicationCodes.contains(existingApplicationCode);

                /*
                 * The existing Opportunity is against the Parent Program itself
                 * (not a PGDM/PGDM-BM sibling) -- gates PGDM/PGDM-BM creation
                 * directly, with its own paid/cycle rules.
                 */
                Boolean existingIsParentProgram =
                    selectedProgram.ParentProgramId != null
                    && existingOpp.Program__c == selectedProgram.ParentProgramId;

                if (existingIsParentProgram) {

                    Boolean isParentPaid = paidStatus.contains(existingApp.Application_Status__c);

                    if (!isParentPaid) {
                        // Parent Program application is unpaid -- never allow PGDM/PGDM-BM.
                        return new ApplicationResult(false, existingOpp.Id, existingApp.Id);
                    }

                    if (sameApplicationCycle) {
                        // Paid, but same cycle the Parent Program application already covers.
                        return new ApplicationResult(false, existingOpp.Id, existingApp.Id);
                    }

                    // Paid + different cycle -- allow. Do not reuse the Parent-level
                    // Application; keep scanning, then fall through to create fresh below.
                    continue;
                }

                /*
                 * Ordinary PGDM <-> PGDM-BM sibling handling.
                 */
                if (sameApplicationCycle) {

                    Boolean isPaid = paidStatus.contains(existingApp.Application_Status__c);

                    if (
                        selectedProgram.ParentProgramId != null
                        && existingApp.Program__c != selectedProgram.ParentProgramId
                    ) {
                        existingApp.Program__c = selectedProgram.ParentProgramId;
                        update existingApp;
                    }

                    if (isIndividualSiblingProgrammeOpportunityEnabled()) {

                        Program parentProgram = selectedProgram.ParentProgramId != null
                            ? getParentProgramRow(selectedProgram)
                            : null;

                        if (selectedProgram.ParentProgramId != null) {
                            existingOpp.Program__c = selectedProgram.ParentProgramId;
                        }
                        String fn = String.isNotBlank(firstName) ? firstName.trim() : 'Applicant';
                        String ln = String.isNotBlank(lastName) ? lastName.trim() : '';
                        String displayName = (parentProgram != null && String.isNotBlank(parentProgram.Name))
                            ? parentProgram.Name
                            : (String.isNotBlank(selectedProgram.Name) ? selectedProgram.Name : 'Program');
                        existingOpp.Name = (fn + ' ' + ln).trim() + ' - ' + displayName;
                        existingOpp.StageName = isPaid ? 'Payment' : 'Email Verified';
                        existingOpp.B2C_Program_Code__c = (parentProgram != null && String.isNotBlank(parentProgram.Program_Code__c))
                            ? parentProgram.Program_Code__c
                            : selectedProgram.Program_Code__c;
                        update existingOpp;
                        UpdateUserRecord(accountId);
                        return new ApplicationResult(true, existingOpp.Id, existingApp.Id);
                    }

                    return createOpportunityForExistingApplication(
                        accountId, programId, programName, selectedProgram.Program_Code__c, leadSource, firstName, lastName, existingApp.Id
                    );
                }

                Boolean isPaidOld = paidStatus.contains(existingApp.Application_Status__c);
                if (!isPaidOld) {
                    return createOpportunityForExistingApplication(
                        accountId, programId, programName, selectedProgram.Program_Code__c, leadSource, firstName, lastName, existingApp.Id
                    );
                }
                // Paid sibling + old cycle -- do not reuse, fall through.
            }

            // 3. CREATE NEW PGDM-FAMILY APPLICATION
            return createNewOpportunityAndApplication(
                accountId, programId, programName, programCode, leadSource, firstName, lastName,
                autoCreateApplication, defaultBatchId
            );
        }

        /*
         * ============================================================
         * NON-PGDM PROGRAMS (GMP etc.)
         * Identity for "same cycle" here is Short_Batch_Code__c on the
         * batch -- matches ApplicationNumberController's convention for
         * non-hierarchy programs. A batch code edited in place on the
         * same ProgramCohort record still counts as a new cycle.
         * ============================================================
         */
        List<ProgramCohort> acceptingBatches2 = [
            SELECT Id, Short_Batch_Code__c, IsAcceptingApplications__c
            FROM ProgramCohort
            WHERE ProgramId = :programId
            AND IsAcceptingApplications__c = true
            ORDER BY CreatedDate ASC
        ];

        if (acceptingBatches2.isEmpty()) {
            return new ApplicationResult(false, null, null);
        }

        Id defaultBatchId2 = acceptingBatches2[0].Id;

        Set<String> acceptingBatchCodes = new Set<String>();
        for (ProgramCohort b : acceptingBatches2) {
            if (String.isNotBlank(b.Short_Batch_Code__c)) {
                acceptingBatchCodes.add(b.Short_Batch_Code__c);
            }
        }

        List<Application__c> existingApps = [
            SELECT Id, Name, Batch__c, Batch__r.Short_Batch_Code__c, Application_Status__c
            FROM Application__c
            WHERE Applicant__c = :accountId
            AND Program__c = :programId
            ORDER BY CreatedDate DESC
        ];

        Boolean existingApplicationsInProgress = false;
        Set<String> paidApplicationBatchCodes = new Set<String>();

        for (Application__c app : existingApps) {
            if (paidStatus.contains(app.Application_Status__c)) {
                String existingCode = app.Batch__r != null ? app.Batch__r.Short_Batch_Code__c : null;
                if (String.isNotBlank(existingCode) && acceptingBatchCodes.contains(existingCode)) {
                    paidApplicationBatchCodes.add(existingCode);
                }
            } else {
                existingApplicationsInProgress = true;
            }
        }

        Boolean restrictCreate =
            !acceptingBatchCodes.isEmpty()
            && paidApplicationBatchCodes.containsAll(acceptingBatchCodes);

        if (existingApplicationsInProgress || restrictCreate) {
            return new ApplicationResult(false, null, null);
        }

        return createNewOpportunityAndApplication(
            accountId, programId, programName, programCode, leadSource, firstName, lastName,
            autoCreateApplication, defaultBatchId2
        );
    }

    @TestVisible
    private static ApplicationResult createOpportunityForExistingApplication(
        Id accountId, Id programId, String programName, String programCode, String leadSource,
        String firstName, String lastName, Id reusableApplicationId
    ) {
        String fn = String.isNotBlank(firstName) ? firstName.trim() : 'Applicant';
        String ln = String.isNotBlank(lastName) ? lastName.trim() : '';
        String pName = String.isNotBlank(programName) ? programName.trim() : 'Program';

        Opportunity newOpp = new Opportunity();
        newOpp.AccountId = accountId;
        newOpp.Program__c = programId;
        newOpp.B2C_Program_Code__c = programCode;
        newOpp.Name = (fn + ' ' + ln).trim() + ' - ' + pName;
        newOpp.StageName = 'Email Verified';
        newOpp.CloseDate = Date.today().addDays(90);
        newOpp.Application__c = reusableApplicationId;
        if (String.isNotBlank(leadSource)) {
            newOpp.LeadSource = leadSource.trim();
        }
        Schema.RecordTypeInfo b2cOppRti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('B2C_Opportunity');
        if (b2cOppRti != null) {
            newOpp.RecordTypeId = b2cOppRti.getRecordTypeId();
        }
        insert newOpp;
        UpdateUserRecord(accountId);
        return new ApplicationResult(true, newOpp.Id, reusableApplicationId);
    }

    @TestVisible
    private static ApplicationResult createNewOpportunityAndApplication(
        Id accountId, Id programId, String programName, String programCode,
        String leadSource, String firstName, String lastName, Boolean autoCreateApplication, Id batchId
    ) {
        String fn = String.isNotBlank(firstName) ? firstName.trim() : 'Applicant';
        String ln = String.isNotBlank(lastName) ? lastName.trim() : '';
        String pName = String.isNotBlank(programName) ? programName.trim() : 'Program';

        Opportunity opp = new Opportunity();
        opp.AccountId = accountId;
        opp.Program__c = programId;
        opp.B2C_Program_Code__c = programCode;
        opp.Name = (fn + ' ' + ln).trim() + ' - ' + pName;
        opp.StageName = 'Email Verified';
        opp.CloseDate = Date.today().addDays(90);
        if (String.isNotBlank(leadSource)) {
            opp.LeadSource = leadSource.trim();
        }
        Schema.RecordTypeInfo b2cOppRti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('B2C_Opportunity');
        if (b2cOppRti != null) {
            opp.RecordTypeId = b2cOppRti.getRecordTypeId();
        }
        insert opp;
        UpdateUserRecord(accountId);

        if (autoCreateApplication != true) {
            return new ApplicationResult(true, opp.Id, null);
        }

        List<User> applicantUserList = [
            SELECT Id, Programs_Applied__c
            FROM User
            WHERE ContactId IN (SELECT PersonContactId FROM Account WHERE Id = :accountId)
        ];
        String userId = applicantUserList.isEmpty() ? null : applicantUserList[0].Id;

        Application__c app = new Application__c();
        app.Applicant__c = accountId;
        app.Program__c = programId;
        app.Batch__c = batchId;
        app.OwnerId = userId;
        app.LeadSource__c = leadSource;

        if (String.isNotBlank(programCode)) {
            List<String> applicationNumbers = ConvertB2CLeadController.generateApplicationNumbersInBulk(
                new List<String>{ programCode }
            );
            if (!applicationNumbers.isEmpty() && String.isNotBlank(applicationNumbers[0])) {
                app.Name = applicationNumbers[0];
            }
        }

        insert app;
        insertApplicationRelatedRecordsFromAccount(new List<Application__c>{ app }, accountId, userId);
        update new Opportunity(Id = opp.Id, Application__c = app.Id);

        return new ApplicationResult(true, opp.Id, app.Id);
    }

    /**
     * When an Opportunity is being consolidated onto the Parent Program, both its
     * display name and its B2C_Program_Code__c (used by sharing rules) must reflect
     * the PARENT -- not the specific child program (PGDM / PGDM-BM) that triggered
     * the consolidation.
     */
    @TestVisible
    private static Program getParentProgramRow(Program selectedProgram) {
        if (selectedProgram.ParentProgramId == null) {
            return null;
        }
        List<Program> parentRows = [
            SELECT Id, Name, Program_Code__c
            FROM Program
            WHERE Id = :selectedProgram.ParentProgramId
            LIMIT 1
        ];
        return parentRows.isEmpty() ? null : parentRows[0];
    }

    @TestVisible
    private static void UpdateUserRecord(Id accountId) {
        List<User> applicantUserList = [
            SELECT Id, Programs_Applied__c
            FROM User
            WHERE ContactId IN (SELECT PersonContactId FROM Account WHERE Id = :accountId)
        ];
        String userId = applicantUserList.isEmpty() ? null : applicantUserList[0].Id;
        if (userId != null) {
            List<Opportunity> oppList = [SELECT Id, Program__r.Name FROM Opportunity WHERE AccountId = :accountId];
            Set<String> programNames = new Set<String>();
            for (Opportunity opp : oppList) {
                if (String.isNotBlank(opp.Program__r.Name)) {
                    programNames.add(opp.Program__r.Name);
                }
            }
            String formattedProgrammeNames = ApplicantWelcomeEmailQueue.formatProgrammeList(new List<String>(programNames));
            update new User(Programs_Applied__c = formattedProgrammeNames, Id = userId);
        }
    }

    private static void insertApplicationRelatedRecordsFromAccount(
        List<Application__c> applications, Id accountRecordId, String userId
    ) {
        List<Account> accList = [
            SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone, Phone
            FROM Account WHERE Id = :accountRecordId LIMIT 1 
        ];
        Account accountRecord = accList[0];
        List<Personal_Detail__c> personalDetails = new List<Personal_Detail__c>();
        for (Application__c app : applications) {
            Personal_Detail__c pd = new Personal_Detail__c();
            pd.Application__c = app.Id;
            pd.First_Name__c = accountRecord.FirstName;
            pd.Last_Name__c = accountRecord.LastName;
            pd.Primary_E_mail__c = accountRecord.PersonEmail;
            pd.Mobile_Number__c = String.isNotBlank(accountRecord.PersonMobilePhone) ? accountRecord.PersonMobilePhone : accountRecord.Phone;
            pd.OwnerId = userId;
            personalDetails.add(pd);
        }
        if (!personalDetails.isEmpty()) {
            insert personalDetails;
        }
    }
}
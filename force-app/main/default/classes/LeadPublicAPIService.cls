public without sharing class LeadPublicAPIService {
    @TestVisible 
    public class ReferenceData {
        Map<Id, Program> parentProgramById = new Map<Id, Program>();
        Map<String, Program> programByCode = new Map<String, Program>();
        Map<Id, Campaign> campaignById = new Map<Id, Campaign>();
        Id indiaCountryId;
        Set<Integer> indiaAcceptedPhoneLengths = new Set<Integer>();
        String indiaCountryCode;
        Map<String, Id> stateNameToId = new Map<String, Id>();
        Map<String, Id> cityNameToId = new Map<String, Id>();
        Id b2cLeadRecordTypeId;
        Id applicantAccountRecordTypeId;
        Map<String, Lead> emailToLead = new Map<String, Lead>();
        Map<String, Lead> phoneToLead = new Map<String, Lead>();
        Map<Id, Set<Id>> leadIdToProgramIds = new Map<Id, Set<Id>>();
        Map<String, Account> emailToAccount = new Map<String, Account>();
        Map<String, Account> phoneToAccount = new Map<String, Account>();
        Map<Id, Set<Id>> accountIdToProgramIds = new Map<Id, Set<Id>>(); // kept for backward compat; no longer used for dedup

        // Batch-cycle / PGDM-sibling context, bulk-loaded once for the whole payload.
        Map<Id, Set<String>> acceptingApplicationCodesByProgramId = new Map<Id, Set<String>>();
        Map<Id, Set<Id>> acceptingBatchIdsByProgramId = new Map<Id, Set<Id>>();
        // Non-PGDM cycle identity -- Short_Batch_Code__c, not ProgramCohort Id.
        Map<Id, Set<String>> acceptingShortBatchCodesByProgramId = new Map<Id, Set<String>>();
        Map<String, List<Application__c>> applicationsByAccountProgramKey = new Map<String, List<Application__c>>();
        Map<Id, List<Opportunity>> pgdmFamilyOpportunitiesByAccountId = new Map<Id, List<Opportunity>>();
    }

    public class ProcessOutcome {
        public String responseJson;
        public Integer statusCode;
    }

    public static ProcessOutcome execute(String requestBody) {
        ProcessOutcome outcome = new ProcessOutcome();
        outcome.statusCode = 200;

        List<LeadPublicAPI.LeadWrapper> leadWrappers = parseLeadWrappers(requestBody);

        Integer rowCount = leadWrappers.size();
        List<String> rowErrors = new List<String>();
        Map<Integer, LeadPublicAPI.LeadWrapper> validByIndex = new Map<Integer, LeadPublicAPI.LeadWrapper>();

        for (Integer i = 0; i < rowCount; i++) {
            rowErrors.add(null);
            LeadPublicAPI.LeadWrapper lw = leadWrappers[i];
            if (
                String.isBlank(lw.LastName) ||
                String.isBlank(lw.Email) ||
                String.isBlank(lw.Phone) ||
                String.isBlank(lw.Programme)
            ) {
                rowErrors.set(i, LeadPublicAPIMessages.MISSING_REQUIRED_FIELDS);
            } else if(!isValidPhone(lw.Phone)){
                rowErrors.set(i, 'Phone number must include the country code 91 and start with +.');
            }
            else {
                validByIndex.put(i, lw);
            }
        }

        Set<String> programCodes = new Set<String>();
        Set<Id> campaignIds = new Set<Id>();
        Set<String> emails = new Set<String>();
        Set<String> phones = new Set<String>();
        Set<String> stateNames = new Set<String>();
        Set<String> cityNames = new Set<String>();

        for (Integer i : validByIndex.keySet()) {
            LeadPublicAPI.LeadWrapper lw = validByIndex.get(i);
            if (String.isNotBlank(lw.Programme)) {
                programCodes.add(lw.Programme.trim());
            }
            if (String.isNotBlank(lw.CampaignId)) {
                try {
                    campaignIds.add((Id) lw.CampaignId);
                } catch (Exception e) {
                    // Malformed Id — leave out; campaign lookup will just miss for this row.
                }
            }
            if (String.isNotBlank(lw.Email)) {
                emails.add(lw.Email.trim());
            }
            if (String.isNotBlank(lw.Phone)) {
                phones.add(lw.Phone.trim());
            }
            if (String.isNotBlank(lw.State)) {
                stateNames.add(lw.State.trim());
            }
            if (String.isNotBlank(lw.City)) {
                cityNames.add(lw.City.trim());
            }
        }

        ReferenceData ref = loadReferenceData(
            programCodes, campaignIds, stateNames, cityNames, emails, phones
            );
        for (Integer i : new List<Integer>(validByIndex.keySet())) {
            LeadPublicAPI.LeadWrapper lw = validByIndex.get(i);

            try {
                validatePhone(lw.Phone,ref.indiaCountryCode,ref.indiaAcceptedPhoneLengths);
            } catch (Exception e) {
                rowErrors.set(i, e.getMessage());
                validByIndex.remove(i);
            }
        }

        Boolean hasValidationErrors = false;

        for (String error : rowErrors) {
            if (String.isNotBlank(error)) {
                hasValidationErrors = true;
                break;
            }
        }

        if (hasValidationErrors) {
            outcome.statusCode = 400;
        }

        Map<Integer, Map<String, Object>> indexToUtm = new Map<Integer, Map<String, Object>>();
        Map<Id, Account> accountsToUpdate = new Map<Id, Account>();
        Map<Id, Application__c> applicationsToUpdate = new Map<Id, Application__c>();
        List<Opportunity> existingOppsToUpdate = new List<Opportunity>();
        Map<Integer, Id> indexToReusedApplicationId = new Map<Integer, Id>();

        List<Lead> leadsToUpsert = new List<Lead>();
        Map<Integer, LeadPublicAPIHelper.ResultWrapper> indexToResult = new Map<Integer, LeadPublicAPIHelper.ResultWrapper>();
        Map<Integer, LeadPublicAPIHelper.ResultWrapper> indexToWrapperForLp = new Map<Integer, LeadPublicAPIHelper.ResultWrapper>();

        List<Opportunity> oppsToInsert = new List<Opportunity>();
        Map<Integer, Opportunity> indexToOpp = new Map<Integer, Opportunity>();
        Map<Integer, Account> indexToAcc = new Map<Integer, Account>();
        Map<Integer, Id> campaignIndexMap = new Map<Integer, Id>();

        Map<Integer, String> processingErrors = new Map<Integer, String>();

        for (Integer i : validByIndex.keySet()) {
            LeadPublicAPI.LeadWrapper lw = validByIndex.get(i);

            try {
                Map<String, Object> utmFormValues = LeadMappingAndTouchService.buildUtmFormValues(lw);
                indexToUtm.put(i, utmFormValues);

                Account acc = resolveApplicantAccount(lw, ref);

                if (acc != null) {
                    indexToResult.put(i, processApplicantPath(
                        lw, i, acc, ref, oppsToInsert, indexToOpp, indexToAcc, campaignIndexMap,
                        accountsToUpdate, applicationsToUpdate, existingOppsToUpdate, indexToReusedApplicationId
                    ));
                    continue;
                }

                LeadPublicAPIHelper.ResultWrapper rw = LeadPublicAPIHelper.processLead(
                    lw,
                ref.programByCode,
                ref.stateNameToId,
                ref.cityNameToId,
                ref.indiaCountryId,
                ref.b2cLeadRecordTypeId,
                ref.emailToLead,
                ref.phoneToLead,
                ref.leadIdToProgramIds,
                utmFormValues
                    );

                if (rw.leadRecord != null) {
                    leadsToUpsert.add(rw.leadRecord);
                }
                indexToResult.put(i, rw);

                if (rw.leadProgram != null) {
                    indexToWrapperForLp.put(i, rw);
                }

                if (String.isNotBlank(lw.CampaignId) && ref.campaignById.containsKey((Id) lw.CampaignId)) {
                    campaignIndexMap.put(i, (Id) lw.CampaignId);
                }
            } catch (Exception ex) {
                processingErrors.put(i, ex.getMessage());
            }
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate.values();
        }
        if (!applicationsToUpdate.isEmpty()) {
            update applicationsToUpdate.values();
        }
        if (!existingOppsToUpdate.isEmpty()) {
            update existingOppsToUpdate;
        }
        if (!leadsToUpsert.isEmpty()) {
            upsert leadsToUpsert;
        }

        for (LeadPublicAPIHelper.ResultWrapper rw : indexToResult.values()) {
            if (rw.leadRecord != null && rw.leadRecord.Id != null) {
                rw.leadId = rw.leadRecord.Id;
            }
        }

        for (Integer i : indexToResult.keySet()) {
            LeadPublicAPIHelper.ResultWrapper rw = indexToResult.get(i);
            LeadPublicAPI.LeadWrapper lw = validByIndex.get(i);
            Map<String, Object> utmFormValues = indexToUtm.get(i);
            Program prog = ref.programByCode.get(lw.Programme);

            if (prog == null || rw.leadId == null) {
                continue;
            }

            Boolean applicantPath =
                rw.scenario == LeadPublicAPIHelper.Scenario.APPLICANT_NEW_OPPORTUNITY ||
                rw.scenario == LeadPublicAPIHelper.Scenario.APPLICANT_OPPORTUNITY_ALREADY_EXISTS ||
                rw.scenario == LeadPublicAPIHelper.Scenario.APPLICANT_ALTERNATE_PHONE_UPDATED ||
                rw.scenario == LeadPublicAPIHelper.Scenario.APPLICANT_NOT_ACCEPTING;

            if (applicantPath) {
                LeadMappingAndTouchService.insertApplicantTouch(rw.leadId, prog.Id, utmFormValues);
            } else {
                LeadMappingAndTouchService.insertLeadTouch(rw.leadId, prog.Id, utmFormValues);
            }
        }

        List<Lead_Program__c> lpList = new List<Lead_Program__c>();
        for (Integer i : indexToWrapperForLp.keySet()) {
            LeadPublicAPIHelper.ResultWrapper rw = indexToWrapperForLp.get(i);
            rw.leadProgram.Lead__c = rw.leadRecord.Id;

            Id campaignId = campaignIndexMap.get(i);
            if (campaignId != null && ref.campaignById.containsKey(campaignId)) {
                rw.leadProgram.Lead_Source__c = ref.campaignById.get(campaignId).CampaignSource__c;
            }
            lpList.add(rw.leadProgram);
        }

        if (!lpList.isEmpty()) {
            insert lpList;
        }

        if (!oppsToInsert.isEmpty()) {
            insert oppsToInsert;
        }

        // Only create Applications for Opportunities that don't already carry a reused one,
        // and only when the org's auto-create-application flag is on.
        if (ConvertB2CLeadController.isAutoApplicationCreationEnabled() && !indexToOpp.isEmpty()) {
            Map<Integer, Opportunity> indexToOppNeedingApp = new Map<Integer, Opportunity>();
            for (Integer i : indexToOpp.keySet()) {
                if (indexToOpp.get(i).Application__c == null) {
                    indexToOppNeedingApp.put(i, indexToOpp.get(i));
                }
            }
            if (!indexToOppNeedingApp.isEmpty()) {
                attachApplicationsInOrder(indexToOppNeedingApp, indexToAcc, validByIndex);
            }
        }

        insertCampaignMembers(validByIndex, indexToResult, ref, campaignIndexMap);

        List<Object> responses = buildResponseList(
            rowCount, leadWrappers, validByIndex, rowErrors, processingErrors, indexToResult
            );

        outcome.responseJson = JSON.serialize(responses);
        return outcome;
    }

    private static List<LeadPublicAPI.LeadWrapper> parseLeadWrappers(String reqBody) {
        if (String.isBlank(reqBody)) {
            throw new LeadPublicAPIException('Request body is required.');
        }
        try {
            LeadPublicAPI.LeadWrapper single = (LeadPublicAPI.LeadWrapper) JSON.deserialize(
                reqBody,
            LeadPublicAPI.LeadWrapper.class
                );
            return new List<LeadPublicAPI.LeadWrapper>{ single };
        } catch (Exception e) {
            return (List<LeadPublicAPI.LeadWrapper>) JSON.deserialize(
                reqBody,
            List<LeadPublicAPI.LeadWrapper>.class
                );
        }
    }

    private static ReferenceData loadReferenceData(
        Set<String> programCodes,
    Set<Id> campaignIds,
    Set<String> stateNames,
    Set<String> cityNames,
    Set<String> emails,
    Set<String> phones
    ) {
        ReferenceData ref = new ReferenceData();

        if (!programCodes.isEmpty()) {
            for (Program p : [
                SELECT Id, Name, Program_Code__c, ParentProgramId
                FROM Program
                WHERE Program_Code__c IN :programCodes
            ]) {
                ref.programByCode.put(p.Program_Code__c, p);
            }
        }

        if (!campaignIds.isEmpty()) {
            for (Campaign c : [SELECT Id, CampaignSource__c FROM Campaign WHERE Id IN :campaignIds]) {
                ref.campaignById.put(c.Id, c);
            }
        }

        List<Country_Master__c> india = [
            SELECT Id,AcceptedNumberLength__c,Country_Code__c
            FROM Country_Master__c
            WHERE Name = 'India'
            LIMIT 1
        ];
        if (india.isEmpty()) {
            throw new LeadPublicAPIException('Country master India not found.');
        }
        ref.indiaCountryId = india[0].Id;
        ref.indiaCountryCode = india[0].Country_Code__c;
        if (String.isNotBlank(india[0].AcceptedNumberLength__c)) {
            for (String lengthValue : india[0].AcceptedNumberLength__c.split(';')) {
                if (String.isNotBlank(lengthValue)) {
                    try {
                        ref.indiaAcceptedPhoneLengths.add(
                            Integer.valueOf(lengthValue.trim())
                            );
                    } catch (Exception e) {
                        // Ignore invalid configuration values
                    }
                }
            }
        }
        if (!stateNames.isEmpty()) {
            for (State__c st : [
                SELECT Id, Name
                FROM State__c
                WHERE Name IN :stateNames AND Country_Master__c = :ref.indiaCountryId
            ]) {
                ref.stateNameToId.put(st.Name, st.Id);
            }
        }

        if (!cityNames.isEmpty()) {
            for (City__c ct : [SELECT Id, Name FROM City__c WHERE Name IN :cityNames]) {
                ref.cityNameToId.put(ct.Name, ct.Id);
            }
        }

        ref.b2cLeadRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
            .get('B2C')
            .getRecordTypeId();
        ref.applicantAccountRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Applicant')
            .getRecordTypeId();

        if (!emails.isEmpty() || !phones.isEmpty()) {
            for (Lead l : [
                SELECT Id, Email, Phone,AlternateContactNumber__c
                FROM Lead
                WHERE Email IN :emails OR Phone IN :phones
            ]) {
                if (l.Email != null) {
                    ref.emailToLead.put(l.Email, l);
                }
                if (l.Phone != null) {
                    ref.phoneToLead.put(l.Phone, l);
                }
            }
        }

        Set<Id> leadIds = new Set<Id>();
        for (Lead l : ref.emailToLead.values()) {
            leadIds.add(l.Id);
        }
        for (Lead l : ref.phoneToLead.values()) {
            leadIds.add(l.Id);
        }

        if (!leadIds.isEmpty()) {
            for (Lead_Program__c lp : [
                SELECT Lead__c, Program__c
                FROM Lead_Program__c
                WHERE Lead__c IN :leadIds
            ]) {
                if (!ref.leadIdToProgramIds.containsKey(lp.Lead__c)) {
                    ref.leadIdToProgramIds.put(lp.Lead__c, new Set<Id>());
                }
                ref.leadIdToProgramIds.get(lp.Lead__c).add(lp.Program__c);
            }
        }

        if (!emails.isEmpty() || !phones.isEmpty()) {
            for (Account acc : [
                SELECT Id, PersonEmail, PersonMobilePhone, PersonOtherPhone,
                Phone, PersonContactId,FirstName,LastName
                FROM Account
                WHERE
                    RecordTypeId = :ref.applicantAccountRecordTypeId AND
                    (PersonEmail IN :emails OR PersonMobilePhone IN :phones OR Phone IN :phones)
            ]) {
                if (acc.PersonEmail != null) {ref.emailToAccount.put(acc.PersonEmail, acc);}
                if (acc.PersonMobilePhone != null) {ref.phoneToAccount.put(acc.PersonMobilePhone, acc);}
                if (acc.Phone != null) {ref.phoneToAccount.put(acc.Phone, acc);}
            }
        }

        Set<Id> accountIds = new Set<Id>();
        for (Account a : ref.emailToAccount.values()) {
            accountIds.add(a.Id);
        }
        for (Account a : ref.phoneToAccount.values()) {
            accountIds.add(a.Id);
        }

        if (!accountIds.isEmpty()) {
            for (Opportunity o : [SELECT AccountId, Program__c FROM Opportunity WHERE AccountId IN :accountIds]) {
                if (!ref.accountIdToProgramIds.containsKey(o.AccountId)) {
                    ref.accountIdToProgramIds.put(o.AccountId, new Set<Id>());
                }
                ref.accountIdToProgramIds.get(o.AccountId).add(o.Program__c);
            }
        }

        // ---- Batch-cycle / PGDM-sibling context, prefetched in bulk ----

        Set<Id> programIdsInBatch = new Set<Id>();
        for (Program p : ref.programByCode.values()) {
            programIdsInBatch.add(p.Id);
        }
        Set<Id> parentProgramIds= new Set<Id>();
            for (Program p : ref.programByCode.values()) {
                if (p.ParentProgramId!=null) {
                    parentProgramIds.add(p.ParentProgramId);
                }
            }
            if (!parentProgramIds.isEmpty()) {
            for (Program parentProg : [SELECT Id, Name, Program_Code__c FROM Program 
            WHERE Id IN :parentProgramIds
            ]) {
                ref.parentProgramById.put(parentProg.Id, parentProg);
            }
        }

        if (!programIdsInBatch.isEmpty()) {
            for (ProgramCohort pc : [
                SELECT Id, ProgramId, Application_Code__c, Short_Batch_Code__c
                FROM ProgramCohort
                WHERE ProgramId IN :programIdsInBatch
                AND IsAcceptingApplications__c = true
            ]) {
                if (!ref.acceptingApplicationCodesByProgramId.containsKey(pc.ProgramId)) {
                    ref.acceptingApplicationCodesByProgramId.put(pc.ProgramId, new Set<String>());
                }
                if (String.isNotBlank(pc.Application_Code__c)) {
                    ref.acceptingApplicationCodesByProgramId.get(pc.ProgramId).add(pc.Application_Code__c);
                }

                if (!ref.acceptingShortBatchCodesByProgramId.containsKey(pc.ProgramId)) {
                    ref.acceptingShortBatchCodesByProgramId.put(pc.ProgramId, new Set<String>());
                }
                if (String.isNotBlank(pc.Short_Batch_Code__c)) {
                    ref.acceptingShortBatchCodesByProgramId.get(pc.ProgramId).add(pc.Short_Batch_Code__c);
                }

                if (!ref.acceptingBatchIdsByProgramId.containsKey(pc.ProgramId)) {
                    ref.acceptingBatchIdsByProgramId.put(pc.ProgramId, new Set<Id>());
                }
                ref.acceptingBatchIdsByProgramId.get(pc.ProgramId).add(pc.Id);
            }
        }

        if (!accountIds.isEmpty() && !programIdsInBatch.isEmpty()) {
            for (Application__c app : [
                SELECT Id, Name, Batch__c, Batch__r.Short_Batch_Code__c, Program__c, Applicant__c, Application_Status__c
                FROM Application__c
                WHERE Applicant__c IN :accountIds
                AND Program__c IN :programIdsInBatch
            ]) {
                String key = app.Applicant__c + '|' + app.Program__c;
                if (!ref.applicationsByAccountProgramKey.containsKey(key)) {
                    ref.applicationsByAccountProgramKey.put(key, new List<Application__c>());
                }
                ref.applicationsByAccountProgramKey.get(key).add(app);
            }
            Set<String> pgdmCodes = ConvertB2CLeadController.getAllProgramCodes();
            for (Opportunity o : [
                SELECT Id, AccountId, Program__c, Program__r.Program_Code__c, Program__r.ParentProgramId,
                       Application__c, Application__r.Id, Application__r.Application_Status__c,
                       Application__r.Program__c, Application__r.Batch__c,
                       Application__r.Batch__r.Application_Code__c
                FROM Opportunity
                WHERE AccountId IN :accountIds
                AND Application__c != null
                AND Program__r.Program_Code__c IN :pgdmCodes
                ORDER BY CreatedDate DESC
            ]) {
                if (!ref.pgdmFamilyOpportunitiesByAccountId.containsKey(o.AccountId)) {
                    ref.pgdmFamilyOpportunitiesByAccountId.put(o.AccountId, new List<Opportunity>());
                }
                ref.pgdmFamilyOpportunitiesByAccountId.get(o.AccountId).add(o);
            }
        }

        return ref;
    }

    private static Account resolveApplicantAccount(LeadPublicAPI.LeadWrapper lw, ReferenceData ref) {
        Account acc = ref.emailToAccount.get(lw.Email);
        if (acc == null) {
            acc = ref.phoneToAccount.get(lw.Phone);
        }
        return acc;
    }
    @TestVisible
    private static ReferenceData buildTestReferenceData(
        Program prog,
    Id accountId
    ) {
        ReferenceData ref = new ReferenceData();

        ref.programByCode.put(
            prog.Program_Code__c,
        prog
            );

        ref.accountIdToProgramIds.put(
            accountId,
        new Set<Id>()
            );

        return ref;
    }

    /*
     * Same decision rules as OpportunityApplicationService, read entirely from
     * ref (no per-row SOQL) so this stays bulk-safe. Non-PGDM identity is
     * Short_Batch_Code__c, matching ApplicationNumberController's own
     * convention -- a batch code edited in place on the same ProgramCohort
     * record still counts as a new cycle.
     */
    @TestVisible
    private static LeadPublicAPIHelper.ResultWrapper processApplicantPath(
        LeadPublicAPI.LeadWrapper lw,
    Integer rowIndex,
    Account acc,
    ReferenceData ref,
    List<Opportunity> oppsToInsert,
    Map<Integer, Opportunity> indexToOpp,
    Map<Integer, Account> indexToAcc,
    Map<Integer, Id> campaignIndexMap,
    Map<Id, Account> accountsToUpdate,
    Map<Id, Application__c> applicationsToUpdate,
    List<Opportunity> existingOppsToUpdate,
    Map<Integer, Id> indexToReusedApplicationId
    ) {
        Program prog = ref.programByCode.get(lw.Programme);
        if (prog == null) {
            throw new LeadPublicAPIException(LeadPublicAPIMessages.INVALID_PROGRAMME);
        }
	system.debug('Prog is '+prog);
        LeadPublicAPIHelper.ResultWrapper rw = new LeadPublicAPIHelper.ResultWrapper();
        rw.leadId = acc.Id;

        if (B2CProgramParentHelper.isPGDMFamily(prog)) {

            Set<String> currentCodes = ref.acceptingApplicationCodesByProgramId.get(prog.Id);
            if (currentCodes == null || currentCodes.isEmpty()) {
                rw.scenario = LeadPublicAPIHelper.Scenario.APPLICANT_NOT_ACCEPTING;
                return rw;
            }

            List<Opportunity> familyOpps = ref.pgdmFamilyOpportunitiesByAccountId.get(acc.Id);
            if (familyOpps == null) {
                familyOpps = new List<Opportunity>();
            }

            // 1. Same-program check
            for (Opportunity existingOpp : familyOpps) {
                if (existingOpp.Program__c != prog.Id || existingOpp.Application__c == null) {
                    continue;
                }
                String existingCode = existingOpp.Application__r.Batch__r != null
                    ? existingOpp.Application__r.Batch__r.Application_Code__c
                    : null;
                if (String.isNotBlank(existingCode) && currentCodes.contains(existingCode)) {
                    if (prog.ParentProgramId != null && existingOpp.Application__r.Program__c != prog.ParentProgramId) {
                        applicationsToUpdate.put(
                            existingOpp.Application__c,
                            new Application__c(Id = existingOpp.Application__c, Program__c = prog.ParentProgramId)
                        );
                    }
                    rw.scenario = LeadPublicAPIHelper.Scenario.APPLICANT_OPPORTUNITY_ALREADY_EXISTS;
                    return rw;
                }
                // older cycle -- fall through
            }

            // 2. Sibling-program check
            for (Opportunity existingOpp : familyOpps) {
                if (existingOpp.Program__c == prog.Id || existingOpp.Application__c == null) {
                    continue;
                }
                String existingCode = existingOpp.Application__r.Batch__r != null
                    ? existingOpp.Application__r.Batch__r.Application_Code__c
                    : null;
                Boolean sameCycle = String.isNotBlank(existingCode) && currentCodes.contains(existingCode);
                Boolean isPaid = ApplicationNumberController.paidStatuses.contains(existingOpp.Application__r.Application_Status__c);

                if (sameCycle) {
                    if (prog.ParentProgramId != null && existingOpp.Application__r.Program__c != prog.ParentProgramId) {
                        applicationsToUpdate.put(
                            existingOpp.Application__c,
                            new Application__c(Id = existingOpp.Application__c, Program__c = prog.ParentProgramId)
                        );
                    }
                                        if (OpportunityApplicationService.isIndividualSiblingProgrammeOpportunityEnabled()) {
                        Program parentProgram = prog.ParentProgramId != null
                            ? ref.parentProgramById.get(prog.ParentProgramId)
                            : null;

                        Opportunity oppUpdate = new Opportunity(Id = existingOpp.Id);
                        if (prog.ParentProgramId != null) {
                            oppUpdate.Program__c = prog.ParentProgramId;
                        }
                        String fn = String.isNotBlank(lw.FirstName) ? lw.FirstName.trim() : 'Applicant';
                        String displayName = (parentProgram != null && String.isNotBlank(parentProgram.Name))
                            ? parentProgram.Name
                            : prog.Name;
                        oppUpdate.Name = (fn + ' ' + lw.LastName).trim() + ' - ' + displayName;
                        oppUpdate.StageName = isPaid ? 'Payment' : 'Email Verified';
                        oppUpdate.B2C_Program_Code__c = (parentProgram != null && String.isNotBlank(parentProgram.Program_Code__c))
                            ? parentProgram.Program_Code__c
                            : prog.Program_Code__c;
                        existingOppsToUpdate.add(oppUpdate);
                        rw.scenario = LeadPublicAPIHelper.Scenario.APPLICANT_OPPORTUNITY_ALREADY_EXISTS;
                        return rw;
                    }
                    indexToReusedApplicationId.put(rowIndex, existingOpp.Application__c);
                    break;
                }
                if (!isPaid) {
                    indexToReusedApplicationId.put(rowIndex, existingOpp.Application__c);
                    break;
                }
                // paid + old cycle -- do not reuse, keep scanning
            }

        } else {
            // Non-PGDM -- identity is Short_Batch_Code__c, not the ProgramCohort Id.
            Set<Id> acceptingBatchIds = ref.acceptingBatchIdsByProgramId.get(prog.Id);
            if (acceptingBatchIds == null || acceptingBatchIds.isEmpty()) {
                rw.scenario = LeadPublicAPIHelper.Scenario.APPLICANT_NOT_ACCEPTING;
                return rw;
            }
            Set<String> acceptingBatchCodes = ref.acceptingShortBatchCodesByProgramId.get(prog.Id);
            if (acceptingBatchCodes == null) {
                acceptingBatchCodes = new Set<String>();
            }

            String key = acc.Id + '|' + prog.Id;
            List<Application__c> existingApps = ref.applicationsByAccountProgramKey.get(key);

            Boolean inProgress = false;
            Set<String> paidBatchCodes = new Set<String>();
            if (existingApps != null) {
                for (Application__c app : existingApps) {
                    if (ApplicationNumberController.paidStatuses.contains(app.Application_Status__c)) {
                        String existingCode = app.Batch__r != null ? app.Batch__r.Short_Batch_Code__c : null;
                        if (String.isNotBlank(existingCode) && acceptingBatchCodes.contains(existingCode)) {
                            paidBatchCodes.add(existingCode);
                        }
                    } else {
                        inProgress = true;
                    }
                }
            }

            Boolean restrict = !acceptingBatchCodes.isEmpty() && paidBatchCodes.containsAll(acceptingBatchCodes);
            if (inProgress || restrict) {
                rw.scenario = LeadPublicAPIHelper.Scenario.APPLICANT_OPPORTUNITY_ALREADY_EXISTS;
                return rw;
            }
        }

        // Build the new Opportunity (possibly carrying a reused Application Id already).
        Boolean phoneUpdated = false;
        String incomingDigits = normalizePhone(lw.Phone);
        Boolean phoneAlreadyOnFile = incomingDigits != null && (
            incomingDigits == normalizePhone(acc.Phone) ||
            incomingDigits == normalizePhone(acc.PersonMobilePhone) ||
            incomingDigits == normalizePhone(acc.PersonOtherPhone)
        );
        if (String.isNotBlank(incomingDigits) && !phoneAlreadyOnFile && String.isBlank(acc.PersonOtherPhone)) {
            String altPhone = LeadPublicAPIHelper.formatAlternatePhone(ref.indiaCountryId, lw.Phone);
            if (String.isNotBlank(altPhone)) {
                accountsToUpdate.put(acc.Id, new Account(Id = acc.Id, PersonOtherPhone = altPhone));
                phoneUpdated = true;
            }
        }

        Id b2cOppRt = null;
        Schema.RecordTypeInfo b2cOppRti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('B2C_Opportunity');
        if (b2cOppRti != null) {
            b2cOppRt = b2cOppRti.getRecordTypeId();
        }
        Opportunity opp = new Opportunity(
            AccountId = acc.Id,
            Program__c = prog.Id,
            B2C_Program_Code__c = prog.Program_Code__c,
            Name = buildOpportunityName(lw, prog.Name),
            StageName = 'Email Verified',
            CloseDate = Date.today().addDays(90),
            LeadSource = ref.campaignById.containsKey((Id) lw.CampaignId) ? ref.campaignById.get((Id) lw.CampaignId).CampaignSource__c : null
        );
        if (b2cOppRt != null) {
            opp.RecordTypeId = b2cOppRt;
        }
        Id reusedAppId = indexToReusedApplicationId.get(rowIndex);
        if (reusedAppId != null) {
            opp.Application__c = reusedAppId;
        }
        oppsToInsert.add(opp);
        indexToOpp.put(rowIndex, opp);
        indexToAcc.put(rowIndex, acc);

        rw.scenario = phoneUpdated? LeadPublicAPIHelper.Scenario.APPLICANT_ALTERNATE_PHONE_UPDATED
            : LeadPublicAPIHelper.Scenario.APPLICANT_NEW_OPPORTUNITY;

        if (String.isNotBlank(lw.CampaignId) && ref.campaignById.containsKey((Id) lw.CampaignId)) {
            campaignIndexMap.put(rowIndex, (Id) lw.CampaignId);
        }
        return rw;
    }

    private static String buildOpportunityName(LeadPublicAPI.LeadWrapper lw, String programName) {
        String fn = String.isNotBlank(lw.FirstName) ? lw.FirstName : '';
        return fn + ' ' + lw.LastName + ' - ' + programName;
    }

    /*
     * Creates Applications (and Personal_Detail__c) for every Opportunity that
     * still needs one, in one bulk pass. Also bulk-fetches each involved
     * program's currently-accepting ProgramCohort so the new Application's
     * Batch__c is populated (ASSUMPTION: earliest-created accepting batch is
     * used as the default when a program has more than one simultaneously
     * accepting batch -- same tie-break convention as OpportunityApplicationService).
     */
       @TestVisible
    private static void attachApplicationsInOrder(
        Map<Integer, Opportunity> indexToOpp,
    Map<Integer, Account> indexToAcc,
    Map<Integer, LeadPublicAPI.LeadWrapper> validByIndex
    ) {
        List<Integer> ordered = new List<Integer>(indexToOpp.keySet());
        ordered.sort();
        Set<Id> accountIds = new Set<Id>();

        for (Account acc : indexToAcc.values()) {
            accountIds.add(acc.Id);
        }

        Map<Id, User> accountToUser = new Map<Id, User>();

        for (User u : [SELECT Id, Contact.AccountId FROM User WHERE Contact.AccountId IN :accountIds]) {
            accountToUser.put(u.Contact.AccountId, u);
        }
        Set<Id> programIds = new Set<Id>();

        for (Opportunity opp : indexToOpp.values()) {
            programIds.add(opp.Program__c);
        }

        Map<Id, Program> programMap = new Map<Id, Program>(
            [SELECT Id, Program_Code__c FROM Program WHERE Id IN :programIds]
            );

        List<String> programCodes = new List<String>();

        for (Integer i : ordered) {
            programCodes.add(programMap.get(indexToOpp.get(i).Program__c).Program_Code__c);
        }

        List<String> applicationNumbers =
            ConvertB2CLeadController.generateApplicationNumbersInBulk(programCodes);

        List<Application__c> apps = new List<Application__c>();
        Integer appNumIdx = 0;
        for (Integer i : ordered) {
            Opportunity opp = indexToOpp.get(i);
            Account acc = indexToAcc.get(i);
            LeadPublicAPI.LeadWrapper lw = validByIndex.get(i);
            User applicantUser = accountToUser.get(acc.Id);

            apps.add(new Application__c(
                Applicant__c = acc.Id,
                Program__c = opp.Program__c,
                OwnerId = applicantUser != null ? applicantUser.Id : null,
                Name = applicationNumbers[appNumIdx++],
                LeadSource__c = opp.LeadSource
            ));
        }
        insert apps;
        List<Personal_Detail__c> personalDetails = new List<Personal_Detail__c>();

        for (Integer i = 0; i < ordered.size(); i++) {

            Account acc = indexToAcc.get(ordered[i]);
            User applicantUser = accountToUser.get(acc.Id);

            Personal_Detail__c pd = new Personal_Detail__c();
            pd.Application__c = apps[i].Id;
            pd.First_Name__c = acc.FirstName;
            pd.Last_Name__c = acc.LastName;
            pd.Primary_E_mail__c = acc.PersonEmail;
            pd.Mobile_Number__c =String.isNotBlank(acc.PersonMobilePhone)? acc.PersonMobilePhone: acc.Phone;
            pd.OwnerId = applicantUser != null ? applicantUser.Id : null;

            personalDetails.add(pd);
        }

        if (!personalDetails.isEmpty()) {
            insert personalDetails;
        }

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        Integer appIdx = 0;
        for (Integer i : ordered) {
            Opportunity opp = indexToOpp.get(i);
            opp.Application__c = apps[appIdx++].Id;
            oppsToUpdate.add(opp);
        }
        update oppsToUpdate;
    }
    
    @TestVisible
    private static void insertCampaignMembers(
        Map<Integer, LeadPublicAPI.LeadWrapper> validByIndex,
    Map<Integer, LeadPublicAPIHelper.ResultWrapper> indexToResult,
    ReferenceData ref,
    Map<Integer, Id> campaignIndexMap
    ) {
        if (campaignIndexMap.isEmpty()) {
            return;
        }

        Set<Id> leadIdsForCm = new Set<Id>();
        Set<Id> contactIdsForCm = new Set<Id>();

        for (Integer i : campaignIndexMap.keySet()) {
            LeadPublicAPI.LeadWrapper lw = validByIndex.get(i);
            Account acc = resolveApplicantAccount(lw, ref);
            if (acc != null && acc.PersonContactId != null) {
                contactIdsForCm.add(acc.PersonContactId);
            } else if (acc == null) {
                LeadPublicAPIHelper.ResultWrapper rw = indexToResult.get(i);
                if (rw != null && rw.leadId != null) {
                    leadIdsForCm.add(rw.leadId);
                }
            }
        }

        Set<Id> campaignIdSet = new Set<Id>(campaignIndexMap.values());

        Map<String, CampaignMember> existingCm = new Map<String, CampaignMember>();
        if (!leadIdsForCm.isEmpty()) {
            for (CampaignMember cm : [
                SELECT CampaignId, LeadId
                FROM CampaignMember
                WHERE CampaignId IN :campaignIdSet AND LeadId IN :leadIdsForCm
            ]) {
                existingCm.put(String.valueOf(cm.CampaignId) + '-' + String.valueOf(cm.LeadId), cm);
            }
        }
        if (!contactIdsForCm.isEmpty()) {
            for (CampaignMember cm : [SELECT CampaignId, ContactId FROM CampaignMember WHERE CampaignId IN :campaignIdSet AND ContactId IN :contactIdsForCm
            ]) {
                existingCm.put(String.valueOf(cm.CampaignId) + '-' + String.valueOf(cm.ContactId), cm);
            }
        }

        Set<String> processedKeys = new Set<String>();
        List<CampaignMember> cmList = new List<CampaignMember>();

        for (Integer i : campaignIndexMap.keySet()) {
            Id campaignId = campaignIndexMap.get(i);
            LeadPublicAPI.LeadWrapper lw = validByIndex.get(i);
            Account acc = resolveApplicantAccount(lw, ref);

            if (acc != null && acc.PersonContactId != null) {
                String key = String.valueOf(campaignId) + '-' + String.valueOf(acc.PersonContactId);
                if (!existingCm.containsKey(key) && !processedKeys.contains(key)) {
                    cmList.add(new CampaignMember(CampaignId = campaignId,ContactId = acc.PersonContactId,Status = 'Sent'));
                    processedKeys.add(key);
                }
            } else if (acc == null) {
                LeadPublicAPIHelper.ResultWrapper rw = indexToResult.get(i);
                if (rw != null && rw.leadId != null) {
                    String key = String.valueOf(campaignId) + '-' + String.valueOf(rw.leadId);
                    if (!existingCm.containsKey(key) && !processedKeys.contains(key)) {
                        cmList.add(
                            new CampaignMember(CampaignId = campaignId, LeadId = rw.leadId, Status = 'Sent')
                            );
                        processedKeys.add(key);
                    }
                }
            }
        }

        if (!cmList.isEmpty()) {
            insert cmList;
        }
    }

    private static Boolean isSuccessfulScenario(LeadPublicAPIHelper.Scenario scenario) {
        return scenario == LeadPublicAPIHelper.Scenario.LEAD_CREATED || scenario == LeadPublicAPIHelper.Scenario.LEAD_EXISTING_NEW_PROGRAM || scenario == LeadPublicAPIHelper.Scenario.LEAD_EXISTING_ALTERNATE_PHONE_UPDATED || scenario == LeadPublicAPIHelper.Scenario.APPLICANT_NEW_OPPORTUNITY || scenario == LeadPublicAPIHelper.Scenario.APPLICANT_ALTERNATE_PHONE_UPDATED;
    }

    private static List<Object> buildResponseList(
        Integer rowCount,
    List<LeadPublicAPI.LeadWrapper> leadWrappers,
    Map<Integer, LeadPublicAPI.LeadWrapper> validByIndex,
    List<String> rowErrors,
    Map<Integer, String> processingErrors,
    Map<Integer, LeadPublicAPIHelper.ResultWrapper> indexToResult
    ) {
        List<Object> responses = new List<Object>();
        for (Integer i = 0; i < rowCount; i++) {
            LeadPublicAPI.LeadWrapper lw = leadWrappers[i];
            String name = (String.isNotBlank(lw.FirstName) ? lw.FirstName + ' ' : '') + lw.LastName;

            if (String.isNotBlank(rowErrors[i])) {
                responses.add(
                new Map<String, Object>{
                    'index' => i,
                    'success' => false,
                    'message' => rowErrors[i],
                    'scenario' => null,
                    'recordType' => null,
                    'name' => name
                }
                );
                continue;
            }

            if (processingErrors.containsKey(i)) {
                responses.add(
                new Map<String, Object>{
                    'index' => i,
                    'success' => false,
                    'message' => processingErrors.get(i),
                    'scenario' => null,
                    'recordType' => null,
                    'lead' => name
                }

                );
                continue;
            }

            LeadPublicAPIHelper.ResultWrapper rw = indexToResult.get(i);
            Boolean applicantPath =
                rw.scenario == LeadPublicAPIHelper.Scenario.APPLICANT_NEW_OPPORTUNITY ||
                rw.scenario == LeadPublicAPIHelper.Scenario.APPLICANT_OPPORTUNITY_ALREADY_EXISTS ||
                rw.scenario == LeadPublicAPIHelper.Scenario.APPLICANT_ALTERNATE_PHONE_UPDATED ||
                rw.scenario == LeadPublicAPIHelper.Scenario.APPLICANT_NOT_ACCEPTING;
            Boolean success = isSuccessfulScenario(rw.scenario);
            responses.add(
            new Map<String, Object>{
                'index' => i,
                'success' => success,
                'message' => LeadPublicAPIHelper.messageForScenario(rw.scenario),
                'scenario' => LeadPublicAPIHelper.scenarioApiName(rw.scenario),
                'recordType' => applicantPath ? 'Account' : 'Lead',
                'lead' =>  name

            }
            );
        }
        return responses;
    }
    /*Replaced by a map */
    //     private static Program getParentProgramRow(Id parentProgramId) {
    //     List<Program> rows = [
    //         SELECT Id, Name, Program_Code__c
    //         FROM Program
    //         WHERE Id = :parentProgramId
    //         LIMIT 1
    //     ];
    //     return rows.isEmpty() ? null : rows[0];
    // }
    private static Boolean isValidPhone(String phone) {
        if (String.isBlank(phone)) {
            return false;
        }

        String value = phone.trim();

        return Pattern.matches(
            '^\\+[0-9][0-9\\s\\-\\(\\)]*$',
        value
            );
    }
    public static String normalizePhone(String phone) {
        return String.isBlank(phone) ? null : phone.replaceAll('[^0-9]', '');
    }

    private static void validatePhone(
        String phone,
    String countryCode,
    Set<Integer> acceptedLengths
    ) {
        if (String.isBlank(phone)) {
            throw new LeadPublicAPIException('Phone number is required.');
        }

        String value = phone.trim();

        if (!value.startsWith('+')) {
            throw new LeadPublicAPIException('Phone number must include the country code and start with +.');
        }

        if (String.isBlank(countryCode)) {
            throw new LeadPublicAPIException('Country code is missing.');
        }

        if (acceptedLengths == null || acceptedLengths.isEmpty()) {
            throw new LeadPublicAPIException('Phone number length cannot be validated because the accepted length is not configured. ');
        }

        String phoneDigits = value.replaceAll('[^0-9]', '');
        String configuredCountryCode = countryCode.replaceAll('[^0-9]', '');

        if (String.isBlank(phoneDigits) || String.isBlank(configuredCountryCode)) {
            throw new LeadPublicAPIException('Invalid phone number format.');
        }

        if (!phoneDigits.startsWith(configuredCountryCode)) {
            throw new LeadPublicAPIException('Phone number does not match the configured country code.');
        }

        String localNumber =
            phoneDigits.substring(configuredCountryCode.length());

        if (!acceptedLengths.contains(localNumber.length())) {
            throw new LeadPublicAPIException(
                'Invalid phone number length.'
                );
        }
    }
}
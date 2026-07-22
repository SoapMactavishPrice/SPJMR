/**
 * Lead_Import__c sync: Pending rows become B2C Leads + Lead_Program__c, convert to Applicant,
 * one B2C Opportunity and one Application per Lead_Program__c row, Opportunity Contact Roles,
 * Experience Cloud user, then status Synced/Failed.
 *
 * BULKIFIED: All SOQL queries are pre-loaded into BulkContext. DML is performed in bulk phases.
 * Use LeadImportSyncBatch for large volumes (100K+):
 *   Database.executeBatch(new LeadImportSyncBatch(), 10);
 */
public without sharing class LeadImportSyncService {
    
    public static final String STATUS_PENDING = 'Pending';
    public static final String STATUS_SYNCED  = 'Complete';
    public static final String STATUS_FAILED  = 'Pending';
    
    private static final Integer MAX_IMPORTS_PER_RUN = 50;
    private static final String  B2C_RT              = 'B2C';
    private static final String  APPLICANT_RT        = 'Applicant';
    private static final String  ROUTING_MDT         = 'Default';
    private static final String  APPLICANT_PROFILE   = 'SPJIMR Applicant';
    private static final Set<String> APPLICANT_PERMSET = new Set<String>{
        'ApplicantB2cLogin',
        'ApplicantB2CEducation',
        'EducationCloudExprcCloudAccess'
    };
    private static final String  B2C_OPPORTUNITY_RT  = 'B2C_Opportunity';
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PUBLIC INNER CLASSES
     * ═══════════════════════════════════════════════════════════════════════ */
    
    public class SyncBatchResult {
        public Integer totalProcessed;
        public Integer synced;
        public Integer failed;
    }
    
    public class InvocableOutput {
        @InvocableVariable(label='Total processed') public Integer totalProcessed;
        @InvocableVariable(label='Synced')          public Integer synced;
        @InvocableVariable(label='Failed')          public Integer failed;
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PRIVATE INNER CLASSES
     * ═══════════════════════════════════════════════════════════════════════ */
    
    /** Holds all pre-queried/cached data for a batch of imports. */
    private class BulkContext {
        Id b2cRtId;
        Id applicantRtId;
        Id b2cOppRtId;
        Id profileId;
        Id ownerUserId;
        String convertedStatusLabel;
        Map<String, Id> programMap;
        Map<String, Id> acctByEmail;
        Map<String, Id> acctByPhone;
        Map<String, Lead> leadByEmail;
        Map<String, Lead> leadByPhone;
        Map<String, Id> convAcctByEmail;
        Map<String, Id> convAcctByPhone;
        Set<String> activeUserEmails;
        Map<String, Sequence_Master__c> sequenceMap;
        String intakeYear;
        Map<String, Id> userByEmail;
        Map<Id, Account> personAccountCache;
        Map<Id, Program> programDetailCache;
    }
    
    /** Tracks one Lead_Import__c through the bulk pipeline. */
    private class ImportTracker {
        Lead_Import__c rec;
        String email;
        String phone;
        Id programId;
        Integer path;           // 1=existing acct, 2=existing lead, 3=converted acct, 4=new
        Lead leadData;          // existing or newly built lead record
        Id leadId;
        Id accountId;
        Id contactId;
        Boolean failed  = false;
        Boolean skipOpp = false;
        String errMsg;
        Opportunity opp;
        Application__c app;
        Id userId;
        ImportTracker(Lead_Import__c li) {
            this.rec   = li;
            this.email = norm(li.Email__c);
            this.phone = norm(li.Phone__c);
        }
    }
    
    private class NameParts {
        String firstName;
        String lastName;
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PUBLIC ENTRY POINTS
     * ═══════════════════════════════════════════════════════════════════════ */
    
    /** Synchronous entry: queries Pending rows and processes in bulk. */
    public static SyncBatchResult processPendingImports() {
        List<Lead_Import__c> pending = queryPendingImports();
        return pending.isEmpty() ? emptyResult() : processBulk(pending);
    }
    
    /** Main bulk entry: called by LeadImportSyncBatch.execute or directly. */
    public static SyncBatchResult processBulk(List<Lead_Import__c> scope) {
        SyncBatchResult agg = emptyResult();
        if (scope == null || scope.isEmpty()) return agg;
        agg.totalProcessed = scope.size();
        
        List<ImportTracker> trackers = new List<ImportTracker>();
        for (Lead_Import__c li : scope) trackers.add(new ImportTracker(li));
        
        BulkContext ctx = buildBulkContext(trackers);
        validateAndClassify(trackers, ctx);
        insertNewLeads(trackers, ctx);           // Path 4
        ensureLeadPrograms(trackers, ctx);        // Path 2+4
        convertLeadsBulk(trackers, ctx);          // Path 2+4
        patchConvertedAccounts(trackers, ctx);    // Path 2+4
        filterExistingApplications(trackers, ctx);// Path 1+3
        createCommunityUsersBulk(trackers, ctx);  // All
        loadAccountAndProgramDetails(trackers, ctx);
        createOpportunitiesBulk(trackers, ctx);
        createApplicationsBulk(trackers, ctx);
        createChildRecordsBulk(trackers, ctx);
        linkOppsAndOcrsBulk(trackers);
        updateImportStatuses(trackers, agg);
        
        logSummary(agg);
        return agg;
    }
    
    @InvocableMethod(
    label='Process Pending Lead Imports'
        description='Syncs Pending Lead_Import__c via bulk pipeline.'
        )
    public static List<InvocableOutput> processPendingImportsInvocable() {
        return wrapInvocable(processPendingImports());
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 1 — BUILD BULK CONTEXT  (≈10 SOQL, run once per batch)
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static BulkContext buildBulkContext(List<ImportTracker> trackers) {
        BulkContext ctx = new BulkContext();
        
        // RecordType IDs — Schema describe, 0 SOQL
        ctx.b2cRtId      = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get(B2C_RT).getRecordTypeId();
        ctx.applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(APPLICANT_RT).getRecordTypeId();
        ctx.b2cOppRtId   = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(B2C_OPPORTUNITY_RT).getRecordTypeId();
        
        ctx.userByEmail = new Map<String, Id>();
        
        // Collect keys
        Set<String> emails = new Set<String>();
        Set<String> phones = new Set<String>();
        Set<String> progCodes = new Set<String>();
        for (ImportTracker t : trackers) {
            if (t.email != null) emails.add(t.email);
            if (t.phone != null) phones.add(t.phone);
            if (String.isNotBlank(t.rec.Programme__c)) progCodes.add(t.rec.Programme__c.trim());
        }
        ctx.userByEmail = new Map<String, Id>();
        for (User u : [SELECT Id, Email FROM User WHERE Email IN :emails AND IsActive = TRUE]) {
            if (u.Email != null) {
                ctx.userByEmail.put(u.Email.toLowerCase(), u.Id);
            }
        }
        
        
        // SOQL 1 — Programs
        ctx.programMap = loadProgramMap(progCodes);
        
        // SOQL 2 — Converted LeadStatus
        ctx.convertedStatusLabel = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = TRUE LIMIT 1].MasterLabel;
        
        // SOQL 3 — Profile
        List<Profile> profs = [SELECT Id FROM Profile WHERE Name = :APPLICANT_PROFILE LIMIT 1];
        ctx.profileId = profs.isEmpty() ? null : profs[0].Id;
        
        // SOQL 4 — Default owner
        ctx.ownerUserId = resolveOwnerUserId();
        
        // SOQL 5 — Existing Applicant Accounts
        ctx.acctByEmail = new Map<String, Id>();
        ctx.acctByPhone = new Map<String, Id>();
        if (!emails.isEmpty() || !phones.isEmpty()) {
            for (Account a : [
                SELECT Id, PersonEmail, PersonMobilePhone FROM Account
                WHERE RecordTypeId = :ctx.applicantRtId
                  AND (PersonEmail IN :emails OR PersonMobilePhone IN :phones)
            ]) {
                if (a.PersonEmail != null && !ctx.acctByEmail.containsKey(a.PersonEmail.toLowerCase()))
                    ctx.acctByEmail.put(a.PersonEmail.toLowerCase(), a.Id);
                if (a.PersonMobilePhone != null && !ctx.acctByPhone.containsKey(a.PersonMobilePhone))
                    ctx.acctByPhone.put(a.PersonMobilePhone, a.Id);
            }
        }
        
        // SOQL 6 — Unconverted B2C Leads
        ctx.leadByEmail = new Map<String, Lead>();
        ctx.leadByPhone = new Map<String, Lead>();
        if (!emails.isEmpty() || !phones.isEmpty()) {
            for (Lead l : [
                SELECT Id, Phone, Email, FirstName, LastName, Status, IsConverted, Company, LeadSource,
                       Date_Of_Birth__c, XS_Age__c, XS_YearsOfWorkExperience__c, XS_EntranceExamName__c,
                       XS_DoYouHaveEntranceExamScore__c, Publisher_Name__c, XS_HowDidYouFindOutAboutUs__c,
                       Street, City, State, PostalCode, Country,
                       Country_Master_backend__c, Country_Master_backend__r.Name,
                       State_Master__c, State_Master__r.Name,
                       District_City__c, District_City__r.Name
                FROM Lead
                WHERE RecordTypeId = :ctx.b2cRtId AND IsConverted = FALSE
                  AND (Email IN :emails OR Phone IN :phones)
                ORDER BY CreatedDate DESC
            ]) {
                if (l.Email != null && !ctx.leadByEmail.containsKey(l.Email.toLowerCase()))
                    ctx.leadByEmail.put(l.Email.toLowerCase(), l);
                if (l.Phone != null && !ctx.leadByPhone.containsKey(l.Phone))
                    ctx.leadByPhone.put(l.Phone, l);
            }
        }
        
        // SOQL 7 — Converted Lead → Accounts
        ctx.convAcctByEmail = new Map<String, Id>();
        ctx.convAcctByPhone = new Map<String, Id>();
        if (!emails.isEmpty() || !phones.isEmpty()) {
            for (Lead l : [
                SELECT Id, Email, Phone, ConvertedAccountId FROM Lead
                WHERE RecordTypeId = :ctx.b2cRtId AND IsConverted = TRUE
                  AND (Email IN :emails OR Phone IN :phones) AND ConvertedAccountId != null
                ORDER BY CreatedDate DESC
            ]) {
                if (l.Email != null && !ctx.convAcctByEmail.containsKey(l.Email.toLowerCase()))
                    ctx.convAcctByEmail.put(l.Email.toLowerCase(), l.ConvertedAccountId);
                if (l.Phone != null && !ctx.convAcctByPhone.containsKey(l.Phone))
                    ctx.convAcctByPhone.put(l.Phone, l.ConvertedAccountId);
            }
        }
        
        // SOQL 8 — Active community users
        ctx.activeUserEmails = new Set<String>();
        if (!emails.isEmpty()) {
            for (User u : [SELECT Email FROM User WHERE Email IN :emails AND IsActive = TRUE])
                if (u.Email != null) ctx.activeUserEmails.add(u.Email.toLowerCase());
        }
        
        // SOQL 9 — Sequence Masters
        ctx.intakeYear = String.valueOf(Date.today().year());
        ctx.sequenceMap = loadSequenceMap(progCodes, ctx.intakeYear);
        
        // Will be filled later
        ctx.personAccountCache = new Map<Id, Account>();
        ctx.programDetailCache = new Map<Id, Program>();
        
        return ctx;
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 2 — VALIDATE & CLASSIFY
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void validateAndClassify(List<ImportTracker> trackers, BulkContext ctx) {
        for (ImportTracker t : trackers) {
            if (t.failed) continue;
            if (String.isBlank(t.email) || String.isBlank(t.phone)) {
                fail(t, 'Email and Phone are required.'); continue;
            }
            t.programId = resolveProgramId(t.rec.Programme__c, ctx.programMap);
            if (t.programId == null) {
                fail(t, 'No Program found for code: ' + t.rec.Programme__c); continue;
            }
            String eLow = t.email.toLowerCase();
            
            // Path 1 — existing Applicant Account
            Id aId = ctx.acctByEmail.get(eLow);
            if (aId == null) aId = ctx.acctByPhone.get(t.phone);
            if (aId != null) { t.path = 1; t.accountId = aId; continue; }
            
            // Path 2 — unconverted B2C Lead
            Lead el = ctx.leadByEmail.get(eLow);
            if (el == null) el = ctx.leadByPhone.get(t.phone);
            if (el != null) { t.path = 2; t.leadData = el; t.leadId = el.Id; continue; }
            
            // Path 3 — converted Lead's Account
            Id cId = ctx.convAcctByEmail.get(eLow);
            if (cId == null) cId = ctx.convAcctByPhone.get(t.phone);
            if (cId != null) { t.path = 3; t.accountId = cId; continue; }
            
            // Path 4 — brand new
            t.path = 4;
        }
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 3 — INSERT NEW LEADS (Path 4)                    1 DML
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void insertNewLeads(List<ImportTracker> trackers, BulkContext ctx) {
        List<Lead> rows = new List<Lead>();
        List<ImportTracker> active = new List<ImportTracker>();
        for (ImportTracker t : trackers) {
            if (t.failed || t.path != 4) continue;
            Lead nl = buildLeadFromImport(t.rec, ctx.b2cRtId, t.email, t.phone);
            if (ctx.ownerUserId != null) nl.OwnerId = ctx.ownerUserId;
            t.leadData = nl;
            rows.add(nl);
            active.add(t);
        }
        if (rows.isEmpty()) return;
        Database.SaveResult[] srs = Database.insert(rows, false);
        for (Integer i = 0; i < srs.size(); i++) {
            if (srs[i].isSuccess()) active[i].leadId = srs[i].getId();
            else fail(active[i], 'Lead insert: ' + fmtErrors(srs[i].getErrors()));
        }
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 4 — ENSURE LEAD_PROGRAMS (Path 2 + 4)     1 SOQL + 1 DML
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void ensureLeadPrograms(List<ImportTracker> trackers, BulkContext ctx) {
        List<ImportTracker> need = new List<ImportTracker>();
        Set<Id> leadIds = new Set<Id>();
        for (ImportTracker t : trackers) {
            if (t.failed || (t.path != 2 && t.path != 4) || t.leadId == null) continue;
            need.add(t); leadIds.add(t.leadId);
        }
        if (need.isEmpty()) return;
        
        Set<String> existing = new Set<String>();
        for (Lead_Program__c lp : [SELECT Lead__c, Program__c FROM Lead_Program__c WHERE Lead__c IN :leadIds])
            existing.add(lp.Lead__c + '-' + lp.Program__c);
        
        List<Lead_Program__c> toIns = new List<Lead_Program__c>();
        for (ImportTracker t : need) {
            if (!existing.contains(t.leadId + '-' + t.programId))
                toIns.add(buildLeadProgramJunction(t.leadId, t.programId, t.rec.LeadSource__c, t.email, t.phone));
        }
        if (!toIns.isEmpty()) Database.insert(toIns, false);
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 5 — CONVERT LEADS BULK (Path 2 + 4)              1 DML
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void convertLeadsBulk(List<ImportTracker> trackers, BulkContext ctx) {
        List<Database.LeadConvert> converts = new List<Database.LeadConvert>();
        List<ImportTracker> active = new List<ImportTracker>();
        for (ImportTracker t : trackers) {
            if (t.failed || (t.path != 2 && t.path != 4) || t.leadId == null) continue;
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(t.leadId);
            lc.setConvertedStatus(ctx.convertedStatusLabel);
            lc.setDoNotCreateOpportunity(true);
            converts.add(lc);
            active.add(t);
        }
        if (converts.isEmpty()) return;
        
        Database.LeadConvertResult[] results = Database.convertLead(converts, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                active[i].accountId = results[i].getAccountId();
                active[i].contactId = results[i].getContactId();
            } else {
                fail(active[i], 'Conversion: ' + fmtConvertErrors(results[i]));
            }
        }
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 6 — PATCH CONVERTED ACCOUNTS (Path 2 + 4)        2 DML
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void patchConvertedAccounts(List<ImportTracker> trackers, BulkContext ctx) {
        List<Account> rtUpd = new List<Account>();
        List<Account> patches = new List<Account>();
        for (ImportTracker t : trackers) {
            if (t.failed || (t.path != 2 && t.path != 4) || t.accountId == null) continue;
            rtUpd.add(new Account(Id = t.accountId, RecordTypeId = ctx.applicantRtId));
            if (t.leadData != null)
                patches.add(buildAccountPatch(t.accountId, t.leadData, t.email));
        }
        if (!rtUpd.isEmpty())   Database.update(rtUpd, false);
        if (!patches.isEmpty()) Database.update(patches, false);
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 7 — FILTER EXISTING APPLICATIONS (Path 1 + 3)    1 SOQL
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void filterExistingApplications(List<ImportTracker> trackers, BulkContext ctx) {
        Set<Id> aIds = new Set<Id>();
        Set<Id> pIds = new Set<Id>();
        for (ImportTracker t : trackers) {
            if (t.failed || (t.path != 1 && t.path != 3)) continue;
            if (t.accountId != null) aIds.add(t.accountId);
            if (t.programId != null) pIds.add(t.programId);
        }
        if (aIds.isEmpty()) return;
        
        Set<String> keys = new Set<String>();
        for (Application__c a : [
            SELECT Applicant__c, Program__c FROM Application__c
            WHERE Applicant__c IN :aIds AND Program__c IN :pIds
        ]) keys.add(a.Applicant__c + '-' + a.Program__c);
        
        for (ImportTracker t : trackers) {
            if (t.failed || (t.path != 1 && t.path != 3)) continue;
            if (keys.contains(t.accountId + '-' + t.programId)) t.skipOpp = true;
        }
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 8 — COMMUNITY USERS BULK                  1 SOQL + 1 DML
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void createCommunityUsersBulk(List<ImportTracker> trackers, BulkContext ctx) {
        if (ctx.profileId == null) {
            for (ImportTracker t : trackers)
                if (!t.failed && !t.skipOpp) fail(t, 'SPJIMR Applicant Profile not found');
            return;
        }
        Set<Id> aIds = new Set<Id>();
        for (ImportTracker t : trackers) {
            if (!t.failed && t.accountId != null) aIds.add(t.accountId);
        }
        if (aIds.isEmpty()) return;
        
        Map<Id, Account> paMap = new Map<Id, Account>([
            SELECT Id, FirstName, LastName, PersonEmail, PersonContactId
            FROM Account WHERE Id IN :aIds
        ]);
        
        // Fill contactId for Path 1+3
        for (ImportTracker t : trackers) {
            if (t.failed || t.accountId == null) continue;
            Account pa = paMap.get(t.accountId);
            if (pa != null && t.contactId == null) t.contactId = pa.PersonContactId;
        }
        
        List<User> users = new List<User>();
        List<ImportTracker> uTrackers = new List<ImportTracker>();
        Set<String> done = new Set<String>();
        for (ImportTracker t : trackers) {
            if (t.failed || t.accountId == null) continue;
            Account pa = paMap.get(t.accountId);
            if (pa == null || String.isBlank(pa.PersonContactId) || String.isBlank(pa.PersonEmail)) continue;
            String eLow = pa.PersonEmail.toLowerCase();
            if (ctx.activeUserEmails.contains(eLow) || done.contains(eLow)){
                Id existingUserId = ctx.userByEmail.get(eLow);
                if (existingUserId != null) {
                    t.userId = existingUserId;
                    }   
                // t.userId = ctx.userByEmail.get(eLow); 
                    continue;
            } 
            done.add(eLow);
            users.add(buildCommunityUser(pa, ctx.profileId));
            uTrackers.add(t);
        }
        if (users.isEmpty()) return;
        
        Database.SaveResult[] srs = Database.insert(users, false);
        List<Id> okIds = new List<Id>();
        for (Integer i = 0; i < srs.size(); i++) {
            if (srs[i].isSuccess()) {
                Id newUserId = srs[i].getId();
                okIds.add(newUserId);
                uTrackers[i].userId = newUserId;
            }
            else fail(uTrackers[i], 'User create: ' + fmtErrors(srs[i].getErrors()));
        }
        if (!okIds.isEmpty()) System.enqueueJob(new BulkPermSetAssigner(okIds));
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 8b — LOAD ACCOUNT & PROGRAM DETAILS       2 SOQL (cached)
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void loadAccountAndProgramDetails(List<ImportTracker> trackers, BulkContext ctx) {
        Set<Id> aIds = new Set<Id>();
        Set<Id> pIds = new Set<Id>();
        for (ImportTracker t : trackers) {
            if (t.failed || t.skipOpp || t.accountId == null) continue;
            aIds.add(t.accountId);
            if (t.programId != null) pIds.add(t.programId);
        }
        if (!aIds.isEmpty())
            ctx.personAccountCache = new Map<Id, Account>([
                SELECT Id, FirstName, LastName, PersonContactId, PersonEmail FROM Account WHERE Id IN :aIds
            ]);
        if (!pIds.isEmpty())
            ctx.programDetailCache = new Map<Id, Program>([
                SELECT Id, Name, Program_Code__c FROM Program WHERE Id IN :pIds
            ]);
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 9 — OPPORTUNITIES BULK                            1 DML
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void createOpportunitiesBulk(List<ImportTracker> trackers, BulkContext ctx) {
        List<Opportunity> opps = new List<Opportunity>();
        List<ImportTracker> active = new List<ImportTracker>();
        for (ImportTracker t : trackers) {
            if (t.failed || t.skipOpp || t.accountId == null) continue;
            Account acc = ctx.personAccountCache.get(t.accountId);
            Program prog = ctx.programDetailCache.get(t.programId);
            if (acc == null || prog == null) { fail(t, 'Account or Program not found.'); continue; }
            String n = ((acc.FirstName != null ? acc.FirstName : '') + ' ' +
                (acc.LastName  != null ? acc.LastName  : '')).trim();
            Opportunity o = new Opportunity();
            o.AccountId   = acc.Id;
            o.Name        = n + ' - ' + (String.isNotBlank(prog.Name) ? prog.Name : 'Program');
            o.StageName   = 'Email Verified';
            o.CloseDate   = Date.today().addDays(90);
            o.Program__c  = prog.Id;
            o.LeadSource  = t.rec.LeadSource__c;
            o.RecordTypeId = ctx.b2cOppRtId;
            t.opp = o;
            opps.add(o);
            active.add(t);
        }
        if (opps.isEmpty()) return;
        Database.SaveResult[] srs = Database.insert(opps, false);
        for (Integer i = 0; i < srs.size(); i++)
            if (!srs[i].isSuccess()) fail(active[i], 'Opp insert: ' + fmtErrors(srs[i].getErrors()));
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 10 — APPLICATIONS BULK                            1 DML
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void createApplicationsBulk(List<ImportTracker> trackers, BulkContext ctx) {
        // Generate application numbers
        List<ImportTracker> active = new List<ImportTracker>();
        List<String> codes = new List<String>();
        for (ImportTracker t : trackers) {
            if (t.failed || t.skipOpp || t.accountId == null || t.opp == null || t.opp.Id == null) continue;
            Program prog = ctx.programDetailCache.get(t.programId);
            codes.add(prog != null ? prog.Program_Code__c : null);
            active.add(t);
        }
        if (active.isEmpty()) return;
        
        List<String> appNums = generateAppNumbers(codes, ctx);
        
        List<Application__c> apps = new List<Application__c>();
        for (Integer i = 0; i < active.size(); i++) {
            ImportTracker t = active[i];
            Account acc  = ctx.personAccountCache.get(t.accountId);
            Program prog = ctx.programDetailCache.get(t.programId);
            NameParts np = splitImportName(t.rec.Name__c);
            
            Application__c a = new Application__c();
            a.Applicant__c = t.accountId;
            a.Program__c   = t.programId;
            a.First_Name__c = acc != null && String.isNotBlank(acc.FirstName) ? acc.FirstName : np.firstName;
            a.Last_Name__c  = acc != null && String.isNotBlank(acc.LastName)  ? acc.LastName  : np.lastName;
            a.Email__c      = t.email;
            a.Phone__c      = t.phone;
            a.LeadSource__c = t.rec.LeadSource__c;
            a.Application_Stage__c = 'Untouched';
            a.OwnerId = t.userId;
            String num = i < appNums.size() ? appNums[i] : null;
            if (num != null) { a.Application_Number__c = num; a.Name = num; }
            t.app = a;
            apps.add(a);
        }
        Database.SaveResult[] srs = Database.insert(apps, false);
        for (Integer i = 0; i < srs.size(); i++)
            if (!srs[i].isSuccess()) fail(active[i], 'App insert: ' + fmtErrors(srs[i].getErrors()));
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 11 — CHILD RECORDS BULK                           3 DML
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void createChildRecordsBulk(List<ImportTracker> trackers, BulkContext ctx) {
        List<Personal_Detail__c> pds = new List<Personal_Detail__c>();
        List<Work_Experience__c> wes = new List<Work_Experience__c>();
        List<Information_Source__c> iss = new List<Information_Source__c>();
        
        for (ImportTracker t : trackers) {
            if (t.failed || t.skipOpp || t.app == null || t.app.Id == null) continue;
            Account acc = ctx.personAccountCache.get(t.accountId);
            NameParts np = splitImportName(t.rec.Name__c);
            
            Personal_Detail__c pd = new Personal_Detail__c();
            pd.Application__c    = t.app.Id;
            pd.First_Name__c     = acc != null && String.isNotBlank(acc.FirstName) ? acc.FirstName : np.firstName;
            pd.Last_Name__c      = acc != null && String.isNotBlank(acc.LastName)  ? acc.LastName  : np.lastName;
            pd.Primary_E_mail__c = t.email;
            pd.Mobile_Number__c  = t.phone;
            pd.Age_as_on_Customisable_Date__c = t.rec.Age__c;
            pd.OwnerId = t.userId;
            pds.add(pd);
            
            Work_Experience__c we = new Work_Experience__c();
            we.Application__c = t.app.Id;
            we.Do_You_Have_Any_Work_Experience__c = String.isNotBlank(t.rec.Years_of_Work_Experience__c) ? 'Yes' : 'No';
            we.OwnerId = t.userId;
            wes.add(we);
            
            Information_Source__c is2 = new Information_Source__c();
            is2.Application__c = t.app.Id;
            is2.How_Did_you_get_to_know_about_SPJIMR__c = String.isNotBlank(t.rec.LeadSource__c)
                ? t.rec.LeadSource__c : t.rec.How_did_you_find_out_about_us__c;
            is2.OwnerId = t.userId;
            iss.add(is2);
        }
        if (!pds.isEmpty()) Database.insert(pds, false);
        if (!wes.isEmpty()) Database.insert(wes, false);
        if (!iss.isEmpty()) Database.insert(iss, false);
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 12 — LINK OPPS → APPS + OCRs                     2 DML
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void linkOppsAndOcrsBulk(List<ImportTracker> trackers) {
        List<Opportunity> oppUpd = new List<Opportunity>();
        List<OpportunityContactRole> ocrs = new List<OpportunityContactRole>();
        for (ImportTracker t : trackers) {
            if (t.failed || t.skipOpp) continue;
            if (t.opp != null && t.opp.Id != null && t.app != null && t.app.Id != null) {
                t.opp.Application__c = t.app.Id;
                oppUpd.add(t.opp);
            }
            if (t.contactId != null && t.opp != null && t.opp.Id != null) {
                ocrs.add(new OpportunityContactRole(
                    OpportunityId = t.opp.Id, ContactId = t.contactId,
                IsPrimary = true, Role = 'Decision Maker'
                    ));
            }
        }
        if (!oppUpd.isEmpty()) Database.update(oppUpd, false);
        if (!ocrs.isEmpty())   Database.insert(ocrs, false);
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  PHASE 13 — UPDATE IMPORT STATUSES                       1 DML
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static void updateImportStatuses(List<ImportTracker> trackers, SyncBatchResult agg) {
        List<Lead_Import__c> upd = new List<Lead_Import__c>();
        for (ImportTracker t : trackers) {
            if (t.failed) {
                upd.add(new Lead_Import__c(Id = t.rec.Id, Status__c = STATUS_FAILED));
                agg.failed++;
                logErr(t.rec.Id, t.errMsg);
            } else {
                upd.add(new Lead_Import__c(Id = t.rec.Id, Status__c = STATUS_SYNCED));
                agg.synced++;
            }
        }
        if (!upd.isEmpty()) Database.update(upd, false);
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  APP NUMBER GENERATION  (bulk, same logic as before)
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static List<String> generateAppNumbers(List<String> codes, BulkContext ctx) {
        List<Sequence_Master__c> toIns = new List<Sequence_Master__c>();
        Set<String> newKeys = new Set<String>();
        List<String> numbers = new List<String>();
        for (String code : codes) {
            numbers.add(nextAppNumber(code, ctx.intakeYear, ctx.sequenceMap, toIns, newKeys));
        }
        if (!toIns.isEmpty()) Database.insert(toIns, false);
        List<Sequence_Master__c> toUpd = new List<Sequence_Master__c>();
        for (Sequence_Master__c s : ctx.sequenceMap.values())
            if (s.Id != null) toUpd.add(s);
        if (!toUpd.isEmpty()) Database.update(toUpd, false);
        return numbers;
    }
    
    private static String nextAppNumber(String code, String yr,
    Map<String, Sequence_Master__c> seqMap, List<Sequence_Master__c> toIns, Set<String> newKeys) {
        if (String.isBlank(code)) return null;
        Sequence_Master__c seq;
        if (seqMap.containsKey(code)) {
            seq = seqMap.get(code);
            seq.Last_Used_Number__c = seq.Last_Used_Number__c + 1;
        } else if (!newKeys.contains(code)) {
            seq = new Sequence_Master__c(Name = code + '-' + yr, Program_Code__c = code,
            Year__c = yr, Last_Used_Number__c = 1);
            toIns.add(seq);
            seqMap.put(code, seq);
            newKeys.add(code);
        } else {
            seq = seqMap.get(code);
            seq.Last_Used_Number__c = seq.Last_Used_Number__c + 1;
        }
        return code + yr + leftPad(seq.Last_Used_Number__c, 5);
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  BULK QUERY HELPERS
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static Map<String, Id> loadProgramMap(Set<String> codes) {
        Map<String, Id> result = new Map<String, Id>();
        Set<String> variants = new Set<String>();
        for (String c : codes) {
            if (String.isBlank(c)) continue;
            String t = c.trim();
            variants.add(t); variants.add(t.toUpperCase()); variants.add(t.toLowerCase());
        }
        if (variants.isEmpty()) return result;
        for (Program p : [SELECT Id, Program_Code__c FROM Program WHERE Program_Code__c IN :variants]) {
            if (String.isNotBlank(p.Program_Code__c)) {
                String key = p.Program_Code__c.trim().toUpperCase();
                if (!result.containsKey(key)) result.put(key, p.Id);
            }
        }
        return result;
    }
    
    private static Map<String, Sequence_Master__c> loadSequenceMap(Set<String> codes, String yr) {
        Map<String, Sequence_Master__c> m = new Map<String, Sequence_Master__c>();
        if (codes.isEmpty()) return m;
        for (Sequence_Master__c s : [
            SELECT Id, Last_Used_Number__c, Program_Code__c, Year__c
            FROM Sequence_Master__c WHERE Program_Code__c IN :codes AND Year__c = :yr
        ]) m.put(s.Program_Code__c, s);
        return m;
    }
    
    private static Id resolveOwnerUserId() {
        if (Test.isRunningTest()) return null;
        Lead_Routing_Defaults__mdt row = Lead_Routing_Defaults__mdt.getInstance(ROUTING_MDT);
        if (row == null || String.isBlank(row.B2C_Lead_Owner_User_Id__c)) return null;
        Id candidate;
        try { candidate = Id.valueOf(row.B2C_Lead_Owner_User_Id__c.trim()); } catch (Exception e) { return null; }
        if (candidate.getSObjectType() != User.SObjectType) return null;
        List<User> users = [SELECT Id, IsActive FROM User WHERE Id = :candidate LIMIT 1];
        return users.isEmpty() ? null : (users[0].IsActive ? users[0].Id : null);
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  BUILDERS
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static Lead buildLeadFromImport(Lead_Import__c imp, Id rtId, String email, String phone) {
        Lead l = new Lead();
        l.RecordTypeId = rtId;
        l.Status = 'Untouched';
        l.Email  = email;
        l.Phone  = phone;
        NameParts p = splitImportName(imp.Name__c);
        l.FirstName = p.firstName;
        l.LastName  = p.lastName;
        l.Company   = String.isNotBlank(imp.Organization__c) ? imp.Organization__c.trim()
            : (String.isNotBlank(p.lastName) && p.lastName != '.' ? p.firstName+' '+p.lastName+' (Individual)' : p.firstName+' (Individual)');
        if (String.isNotBlank(imp.Country__c))  l.Country = imp.Country__c.trim();
        if (String.isNotBlank(imp.State__c))    l.State   = imp.State__c.trim();
        if (String.isNotBlank(imp.City__c))     l.City    = imp.City__c.trim();
        if (String.isNotBlank(imp.LeadSource__c)) l.LeadSource = imp.LeadSource__c.trim();
        if (String.isNotBlank(imp.How_did_you_find_out_about_us__c)) {
            String h = imp.How_did_you_find_out_about_us__c.trim();
            l.XS_HowDidYouFindOutAboutUs__c = h.length() > 255 ? h.substring(0,255) : h;
        }
        if (imp.Age__c != null) l.XS_Age__c = String.valueOf(imp.Age__c.intValue());
        if (String.isNotBlank(imp.Years_of_Work_Experience__c))
            l.XS_YearsOfWorkExperience__c = imp.Years_of_Work_Experience__c.trim();
        if (String.isNotBlank(imp.Entrance_Exam_Name__c))
            l.XS_EntranceExamName__c = imp.Entrance_Exam_Name__c.trim();
        if (String.isNotBlank(imp.Do_you_have_Entrance_Exam_Scores__c))
            l.XS_DoYouHaveEntranceExamScore__c = imp.Do_you_have_Entrance_Exam_Scores__c.trim();
        if (String.isNotBlank(imp.College__c))
            l.XS_College__c = imp.College__c.trim();
        if (String.isNotBlank(imp.Graduation_Year__c))
            l.XS_Year__c = imp.Graduation_Year__c.trim();
        if (String.isNotBlank(imp.Current_Designation__c) && imp.Current_Designation__c.length() <= 255)
            l.Description = 'Current Designation: ' + imp.Current_Designation__c.trim();
        return l;
    }
    
    private static Lead_Program__c buildLeadProgramJunction(Id leadId, Id progId, String src, String email, String phone) {
        return new Lead_Program__c(Lead__c = leadId, Program__c = progId,
        Lead_Source__c = trim255(src), Email__c = email, Phone__c = phone);
    }
    
    private static Account buildAccountPatch(Id accountId, Lead l, String email) {
        Account a = new Account(Id = accountId);
        a.Phone = l.Phone;
        a.PersonMobilePhone = l.Phone;
        a.PersonEmail = String.isNotBlank(email) ? email : l.Email;
        a.PersonBirthdate = l.Date_Of_Birth__c;
        a.Date_Of_Birth__c = l.Date_Of_Birth__c;
        a.BillingStreet  = l.Street;
        a.BillingCity    = l.District_City__r != null ? l.District_City__r.Name : l.City;
        a.BillingState   = l.State_Master__r  != null ? l.State_Master__r.Name  : l.State;
        a.BillingPostalCode = l.PostalCode;
        a.BillingCountry = l.Country_Master_backend__r != null ? l.Country_Master_backend__r.Name : l.Country;
        a.PersonMailingStreet     = l.Street;
        a.PersonMailingCity       = a.BillingCity;
        a.PersonMailingState      = a.BillingState;
        a.PersonMailingPostalCode = l.PostalCode;
        a.PersonMailingCountry    = a.BillingCountry;
        a.Country_Master__c       = l.Country_Master_backend__c;
        a.State_Master__c         = l.State_Master__c;
        a.District_City__c        = l.District_City__c;
        a.Entrance_Exam_Name__c   = l.XS_EntranceExamName__c;
        a.Has_Entrance_Exam_Score__c = l.XS_DoYouHaveEntranceExamScore__c;
        a.Publisher_Name__c       = l.Publisher_Name__c;
        return a;
    }
    
    private static User buildCommunityUser(Account pa, Id profileId) {
        String nick = String.join(pa.PersonEmail.split('@'), '') + String.valueOf((Integer)(Math.random() * 10000));
        String a1 = (pa.FirstName != null && pa.FirstName.length() > 0) ? pa.FirstName.substring(0,1) : 'U';
        String a2 = (pa.LastName  != null && pa.LastName.length()  > 0) ? pa.LastName.substring(0,1)  : 'U';
        return new User(
            LastName = pa.LastName, FirstName = pa.FirstName, Email = pa.PersonEmail,
        CommunityNickname = nick, Username = pa.PersonEmail, ProfileId = profileId,
        ContactId = pa.PersonContactId, Alias = a1 + a2,
        TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            );
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  UTILITIES
     * ═══════════════════════════════════════════════════════════════════════ */
    
    private static List<Lead_Import__c> queryPendingImports() {
        return [
            SELECT Id, Name__c, Email__c, Phone__c, Programme__c, LeadSource__c,
                   Organization__c, Country__c, State__c, City__c, Age__c,
                   Years_of_Work_Experience__c, How_did_you_find_out_about_us__c,
                   Entrance_Exam_Name__c, Do_you_have_Entrance_Exam_Scores__c,
                   College__c, Graduation_Year__c, Current_Designation__c, Status__c
            FROM Lead_Import__c WHERE Status__c = :STATUS_PENDING
            ORDER BY CreatedDate ASC LIMIT :MAX_IMPORTS_PER_RUN
        ];
    }
    
    private static SyncBatchResult emptyResult() {
        SyncBatchResult r = new SyncBatchResult();
        r.totalProcessed = 0; r.synced = 0; r.failed = 0;
        return r;
    }
    
    private static List<InvocableOutput> wrapInvocable(SyncBatchResult r) {
        InvocableOutput o = new InvocableOutput();
        o.totalProcessed = r.totalProcessed; o.synced = r.synced; o.failed = r.failed;
        return new List<InvocableOutput>{ o };
    }
    
    private static Id resolveProgramId(String code, Map<String, Id> m) {
        return String.isBlank(code) ? null : m.get(code.trim().toUpperCase());
    }
    
    private static NameParts splitImportName(String nameField) {
        NameParts p = new NameParts();
        p.firstName = 'Unknown'; p.lastName = '.';
        String raw = String.isNotBlank(nameField) ? nameField.trim().replaceAll('\\s+', ' ') : '';
        if (String.isBlank(raw)) return p;
        Integer idx = raw.indexOf(' ');
        if (idx > 0) {
            p.firstName = raw.substring(0, idx);
            p.lastName  = raw.substring(idx + 1).trim();
            if (String.isBlank(p.lastName)) p.lastName = '.';
        } else { p.firstName = raw; }
        return p;
    }
    
    private static String norm(String s) {
        if (String.isBlank(s)) return null;
        String t = s.trim();
        return t.length() == 0 ? null : t;
    }
    
    private static String trim255(String s) {
        if (String.isBlank(s)) return null;
        String t = s.trim();
        return t.length() > 255 ? t.substring(0, 255) : t;
    }
    
    private static String leftPad(Decimal num, Integer len) {
        String s = String.valueOf(Integer.valueOf(num == null ? 0 : num));
        while (s.length() < len) s = '0' + s;
        return s;
    }
    
    private static void fail(ImportTracker t, String msg) {
        t.failed = true;
        t.errMsg = msg;
    }
    
    private static String fmtErrors(List<Database.Error> errs) {
        String s = '';
        for (Database.Error e : errs) s += e.getMessage() + ' ';
        return s.trim();
    }
    
    private static String fmtConvertErrors(Database.LeadConvertResult lcr) {
        String s = '';
        for (Database.Error e : lcr.getErrors()) s += e.getMessage() + ' ';
        return s.trim();
    }
    
    private static void logErr(Id importId, String msg) {
        System.debug(LoggingLevel.ERROR, 'LeadImportSyncService import=' + importId + ' ' + msg);
    }
    
    private static void logSummary(SyncBatchResult agg) {
        System.debug('Processed: ' + agg.totalProcessed + ' | Synced: ' + agg.synced + ' | Failed: ' + agg.failed);
    }
    
    /* ═══════════════════════════════════════════════════════════════════════
     *  QUEUEABLE — BULK PERMISSION SET ASSIGNMENT
     * ═══════════════════════════════════════════════════════════════════════ */
    
    public class BulkPermSetAssigner implements Queueable {
        private List<String> userIds;
        public BulkPermSetAssigner(List<Id> ids) {
            this.userIds = new List<String>();
            for (Id i : ids) this.userIds.add(String.valueOf(i));
        }
        public void execute(QueueableContext qc) {
            List<PermissionSet> psList = [SELECT Id FROM PermissionSet WHERE Name IN:APPLICANT_PERMSET LIMIT 3];
            
            if (psList.isEmpty()) return;
            Set<Id> psIds = new Set<Id>();
            for (PermissionSet ps : psList) {
                psIds.add(ps.Id);
            }
            Set<String> existingAssignments = new Set<String>();
            for (PermissionSetAssignment psa : [
        SELECT AssigneeId, PermissionSetId
        FROM PermissionSetAssignment
        WHERE AssigneeId IN :userIds
        AND PermissionSetId IN :psIds
    ]) {
                existingAssignments.add(psa.AssigneeId + '-' + psa.PermissionSetId);
            }
            
            List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
            
            for (Id uid : userIds) {
                for (Id psId : psIds) {
                    
                    String key = uid + '-' + psId;
                    
                    if (!existingAssignments.contains(key)) {
                        toInsert.add(new PermissionSetAssignment(
                            AssigneeId = uid,
                        PermissionSetId = psId
                            ));
                    }
                }
            }
            
            if (!toInsert.isEmpty()) {
                Database.insert(toInsert, false);
            }
            
        }
    }
        
        // Keep old Queueable for backward compatibility
        public class PermissionSetAssigner implements Queueable {
            private String assigneeId;
            public PermissionSetAssigner(Id assigneeId) {
                this.assigneeId = assigneeId != null ? String.valueOf(assigneeId) : null;
            }
            public void execute(QueueableContext context) {
                if (String.isBlank(assigneeId)) return;
                List<PermissionSet> ps = [SELECT Id FROM PermissionSet WHERE Name = :APPLICANT_PERMSET LIMIT 1];
                if (!ps.isEmpty())
                    insert new PermissionSetAssignment(AssigneeId = assigneeId, PermissionSetId = ps[0].Id);
            }
        }
    }
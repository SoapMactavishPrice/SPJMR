/**
 * @description : Application Allocation - simplified for Application Verification first,
 *               with support for Document Verification UI listing only (no auto DV logic).
 */
public with sharing class ApplicationAllocationLwcController {

    public class ApplicationDTO {
        @AuraEnabled public Id appId;
        @AuraEnabled public String appName;
        @AuraEnabled public String applicantName;
        @AuraEnabled public String status;
        @AuraEnabled public Id currentVerificationId;
        @AuraEnabled public Id avId; 
    }

    public class VerifierDTO {
        @AuraEnabled public Id ptmId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
    }

    public class InitData {
        @AuraEnabled public List<ApplicationDTO> applications;
        @AuraEnabled public List<VerifierDTO> verifiers;
    }

    private static Integer normalizePageNumber(Integer pageNumber){
        return (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
    }

    private static Integer normalizePageSize(Integer pageSize){
        if(pageSize == null || pageSize <= 0) return 10;
        if(pageSize > 2000) return 2000;
        return pageSize;
    }

    private static void updateAssignmentStatus(Set<Id> appIds, String status){
        if(appIds == null || appIds.isEmpty()) return;
        List<Application__c> recs = [ SELECT Id, Assignment_Status__c FROM Application__c WHERE Id IN :appIds ];
        for(Application__c a : recs){
            a.Assignment_Status__c = status;
        }
        if(!recs.isEmpty()) update recs;
    }
    
    
    

    // ==========================================================
    // ✅ NEW LOGIC (ONLY ADDITION)
    // If verifier's team IsDocumentVerifier__c = true,
    // after AV insert update Document_Detail__c.Document_Verification__c = AV.Id
    // ==========================================================
    // 
    private static void linkDocumentsToVerification(List<Application_Verification__c> avInserted){
        if(avInserted == null || avInserted.isEmpty()) return;

        // Re-query to safely access relationship fields
        List<Application_Verification__c> avs = [
            SELECT Id,
                   Application__c,
                   Program_Team_Members__r.Program_Team__r.IsDocumentVerifier__c
            FROM Application_Verification__c
            WHERE Id IN :avInserted
        ];

        Set<Id> appIds = new Set<Id>();
        Map<Id, Id> appToAv = new Map<Id, Id>();

        for(Application_Verification__c av : avs){
            if(av.Program_Team_Members__r.Program_Team__r.IsDocumentVerifier__c == true){
                appIds.add(av.Application__c);
                appToAv.put(av.Application__c, av.Id);
            }
        }

        if(appIds.isEmpty()) return;

        List<Document_Details__c> docs = [
            SELECT Id, Application_No__c, Application_Verification__c
            FROM Document_Details__c
            WHERE Application_No__c IN :appIds
        ];

        for(Document_Details__c d : docs){
            d.Application_Verification__c = appToAv.get(d.Application_No__c);
        }

        if(!docs.isEmpty()){
            update docs;
        }
    }
    

    // Fetch verifiers for program filtered by application/document flag
    // Fetch verifiers for program based on stage rules
    private static List<Program_Team_Members__c> fetchVerifiers(
        Id programId,
        Boolean applicationStage,
        Boolean documentStage
    ) {

        // ===============================
        // APPLICATION VERIFICATION STAGE
        // ===============================
        if (applicationStage) {
            return [
                SELECT Id, User__c, User__r.Name
                FROM Program_Team_Members__c
                WHERE Program_Team__r.Program__c = :programId
                  AND Program_Team__r.Type__c = 'Verifier'
                  AND Program_Team__r.IsApplicationVerifier__c = true
                  AND User__c != null
                ORDER BY User__r.Name
            ];
        }

        // ===============================
        // DOCUMENT VERIFICATION STAGE
        // ===============================
        if (documentStage) {
            return [
                SELECT Id, User__c, User__r.Name
                FROM Program_Team_Members__c
                WHERE Program_Team__r.Program__c = :programId
                  AND Program_Team__r.Type__c = 'Verifier'
                  AND Program_Team__r.IsDocumentVerifier__c = true
                  
                  
                  AND User__c != null
                ORDER BY User__r.Name
            ];
        }

        return new List<Program_Team_Members__c>();
    }
    
    
    


    // INIT: returns applications & verifiers depending on 'stage' = 'Application'|'Document'
    @AuraEnabled(cacheable=true)
    public static InitData loadInit(Id programId, String stage){
        InitData resp = new InitData();
        resp.applications = new List<ApplicationDTO>();
        resp.verifiers = new List<VerifierDTO>();

        if(programId == null) return resp;

        String filterStatus =
            (stage == 'Document') ? 'Application Verified' : 'Not Assigned';

        // ===============================
        // APPLICATION LIST
        // ===============================
        List<Application__c> apps = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Assignment_Status__c
            FROM Application__c
            WHERE Program__c = :programId
              AND Assignment_Status__c = :filterStatus
            ORDER BY Name
        ];

        for(Application__c a : apps){
            ApplicationDTO dto = new ApplicationDTO();
            dto.appId = a.Id;
            dto.appName = a.Name;
            dto.applicantName =
                (a.First_Name__c != null ? a.First_Name__c : '') + ' ' +
                (a.Last_Name__c != null ? a.Last_Name__c : '');
            dto.status = a.Assignment_Status__c;
            resp.applications.add(dto);
        }

        // ===============================
        // VERIFIER SELECTION LOGIC
        // ===============================
        Boolean isApplicationStage = (stage == 'Application');
        Boolean isDocumentStage    = (stage == 'Document');

        List<Program_Team_Members__c> ptms =
            fetchVerifiers(programId, isApplicationStage, isDocumentStage);

        for(Program_Team_Members__c ptm : ptms){
            VerifierDTO v = new VerifierDTO();
            v.ptmId = ptm.Id;
            v.userId = ptm.User__c;
            v.name = ptm.User__r.Name;
            resp.verifiers.add(v);
        }

        return resp;
    }

    // PAGINATION helper for Applications page
    @AuraEnabled
    public static List<ApplicationDTO> getApplicationsPage(
        Id programId,
        String stage,
        Integer pageNumber,
        Integer pageSize
    ){
        List<ApplicationDTO> out = new List<ApplicationDTO>();
        if (programId == null) return out;

        Integer pNum  = normalizePageNumber(pageNumber);
        Integer pSize = normalizePageSize(pageSize);
        Integer offsetVal = (pNum - 1) * pSize;

        // ===============================
        // DOCUMENT VERIFICATION LOGIC
        // ===============================
        if (stage == 'Document') {

            // 🔹 Find applications handled by DUAL verifiers
            Set<Id> excludeAppIds = new Set<Id>();

            for (Application_Verification__c av : [
                SELECT Application__c
                FROM Application_Verification__c
                WHERE Application__r.Program__c = :programId
                  AND Program_Team_Members__r.Program_Team__r.IsApplicationVerifier__c = true
                  AND Program_Team_Members__r.Program_Team__r.IsDocumentVerifier__c = true
            ]) {
                excludeAppIds.add(av.Application__c);
            }

            // 🔹 Fetch only remaining applications
            List<Application__c> apps = [
                SELECT Id, Name, First_Name__c, Last_Name__c, Assignment_Status__c
                FROM Application__c
                WHERE Program__c = :programId
                  AND Assignment_Status__c = 'Application Verified'
                  AND Id NOT IN :excludeAppIds
                ORDER BY Name
                LIMIT :pSize OFFSET :offsetVal
            ];

            for (Application__c a : apps) {
                ApplicationDTO dto = new ApplicationDTO();
                dto.appId = a.Id;
                dto.appName = a.Name;
                dto.applicantName =
                    (a.First_Name__c != null ? a.First_Name__c : '') + ' ' +
                    (a.Last_Name__c != null ? a.Last_Name__c : '');
                dto.status = a.Assignment_Status__c;
                out.add(dto);
            }

            return out;
        }

        // ===============================
        // APPLICATION VERIFICATION (UNCHANGED)
        // ===============================
        List<Application__c> apps = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Assignment_Status__c
            FROM Application__c
            WHERE Program__c = :programId
              AND Assignment_Status__c = 'Not Assigned'
            ORDER BY Name
            LIMIT :pSize OFFSET :offsetVal
        ];

        for (Application__c a : apps) {
            ApplicationDTO dto = new ApplicationDTO();
            dto.appId = a.Id;
            dto.appName = a.Name;
            dto.applicantName =
                (a.First_Name__c != null ? a.First_Name__c : '') + ' ' +
                (a.Last_Name__c != null ? a.Last_Name__c : '');
            dto.status = a.Assignment_Status__c;
            out.add(dto);
        }

        return out;
    }


    @AuraEnabled
    public static Integer getApplicationsCount(Id programId, String stage){
        if (programId == null) return 0;

        // ===============================
        // DOCUMENT VERIFICATION
        // ===============================
        if (stage == 'Document') {

            Set<Id> excludeAppIds = new Set<Id>();

            for (Application_Verification__c av : [
                SELECT Application__c
                FROM Application_Verification__c
                WHERE Application__r.Program__c = :programId
                  AND Program_Team_Members__r.Program_Team__r.IsApplicationVerifier__c = true
                  AND Program_Team_Members__r.Program_Team__r.IsDocumentVerifier__c = true
            ]) {
                excludeAppIds.add(av.Application__c);
            }

            return [
                SELECT COUNT()
                FROM Application__c
                WHERE Program__c = :programId
                  AND Assignment_Status__c = 'Application Verified'
                  AND Id NOT IN :excludeAppIds
            ];
        }

        // ===============================
        // APPLICATION VERIFICATION
        // ===============================
        return [
            SELECT COUNT()
            FROM Application__c
            WHERE Program__c = :programId
              AND Assignment_Status__c = 'Not Assigned'
        ];
    }


    // AUTO ALLOCATE (round-robin). verificationType is 'Application' or 'Document'
    @AuraEnabled
    public static void autoAllocate(Id programId, List<Id> applicationIds, List<Id> verifierPtmIds, String verificationType){
        if(applicationIds == null || applicationIds.isEmpty()) return;

        List<Program_Team_Members__c> team;

        if(verifierPtmIds != null && !verifierPtmIds.isEmpty()){
            team = [ SELECT Id, User__c FROM Program_Team_Members__c WHERE Id IN :verifierPtmIds ORDER BY CreatedDate ];
        } else {
            Boolean isDoc = (verificationType == 'Document');
            team = fetchVerifiers(programId, !isDoc, isDoc);
        }

        if(team.isEmpty()) throw new AuraHandledException('No verifiers found.');

        Integer idx = 0;
        Integer total = team.size();
        List<Application_Verification__c> inserts = new List<Application_Verification__c>();
        Set<Id> markAssigned = new Set<Id>();

        for(Id appId : applicationIds){
            Program_Team_Members__c pick = team[idx];

            inserts.add(new Application_Verification__c(
                Application__c = appId,
                Program_Team_Members__c = pick.Id,
                Verifier__c = pick.User__c,
                OwnerId = pick.User__c,
                Application_Verification_Status__c = 'Assigned'
            ));

            markAssigned.add(appId);

            idx++;
            if(idx >= total) idx = 0;
        }

        if(!inserts.isEmpty()) insert inserts;

        // ✅ NEW: Link docs when Document Verifier
        linkDocumentsToVerification(inserts);

        // update Application status to Assigned
        updateAssignmentStatus(markAssigned, 'Assigned');
    }

    // MANUAL ALLOCATE (round-robin across selected verifiers)
    @AuraEnabled
    public static void manualAllocate(Id programId, List<Id> applicationIds, List<Id> verifierPtmIds){
        if(applicationIds == null || applicationIds.isEmpty())
            throw new AuraHandledException('Select Applications.');
        if(verifierPtmIds == null || verifierPtmIds.isEmpty())
            throw new AuraHandledException('Select Verifiers.');

        // 1️⃣ Check if application already completed earlier
        Map<Id, Boolean> hasCompletedMap = new Map<Id, Boolean>();

        for (AggregateResult ar : [
            SELECT Application__c appId, COUNT(Id) cnt
            FROM Application_Verification__c
            WHERE Application__c IN :applicationIds
            AND Application_Verification_Status__c = 'Completed'
            GROUP BY Application__c
        ]) {
            hasCompletedMap.put((Id) ar.get('appId'), true);
        }

        // 2️⃣ Verifier list
        List<Program_Team_Members__c> team = [
            SELECT Id, User__c
            FROM Program_Team_Members__c
            WHERE Id IN :verifierPtmIds
            ORDER BY CreatedDate
        ];

        Integer idx = 0;
        Integer size = team.size();

        // 3️⃣ Prepare new verification records
        List<Application_Verification__c> inserts = new List<Application_Verification__c>();
        Set<Id> appsToMark = new Set<Id>();

        for (Id appId : applicationIds) {

            Program_Team_Members__c pick = team[idx];

            // 4️⃣ If previously completed → keep completed
            String statusToSet = hasCompletedMap.containsKey(appId)
                                    ? 'Completed'
                                    : 'Assigned';

            inserts.add(new Application_Verification__c(
                Application__c = appId,
                Program_Team_Members__c = pick.Id,
                Verifier__c = pick.User__c,
                OwnerId = pick.User__c,
                Application_Verification_Status__c = statusToSet
            ));

            appsToMark.add(appId);

            idx++;
            if (idx >= size) idx = 0;
        }

        // 5️⃣ Insert new records
        if (!inserts.isEmpty()) insert inserts;

        // ✅ NEW: Link docs when Document Verifier
        linkDocumentsToVerification(inserts);

        // 6️⃣ Update parent Application object status
        // If completed earlier → keep "Application Verified"
        // Else new assignment → "Assigned"

        for (Id appId : appsToMark) {
            if (hasCompletedMap.containsKey(appId)) {
                updateAssignmentStatus(new Set<Id>{appId}, 'Application Verified');
            } else {
                updateAssignmentStatus(new Set<Id>{appId}, 'Assigned');
            }
        }
    }

    // ==========================================================
    // REASSIGN APPLICATION_VERIFICATION__c records (bulk-safe)
    // If applicationVerificationIds empty => reassign all AV records for fromPtm where status in ('Assigned','In Progress')
    // ==========================================================
    @AuraEnabled
    public static void reassignApplications(Id programId, Id fromPtmId, Id toPtmId, List<Id> applicationVerificationIds){
        if(programId == null) throw new AuraHandledException('Program Id required.');
        if(fromPtmId == null) throw new AuraHandledException('From Verifier (PTM) required.');
        if(toPtmId == null) throw new AuraHandledException('To Verifier (PTM) required.');

        // lookup target PTM to get User__c
        Program_Team_Members__c toPtm = [
            SELECT Id, User__c
            FROM Program_Team_Members__c
            WHERE Id = :toPtmId
            LIMIT 1
        ];

        if(toPtm == null || toPtm.User__c == null) {
            throw new AuraHandledException('Target verifier has no user linked.');
        }

        List<Application_Verification__c> avToUpdate;

        if(applicationVerificationIds == null || applicationVerificationIds.isEmpty()){
            // reassign all AVs for fromPtmId for that program with status Assigned/In Progress
            avToUpdate = [
                SELECT Id, Program_Team_Members__c, Verifier__c, OwnerId, Application__c, Application_Verification_Status__c
                FROM Application_Verification__c
                WHERE Program_Team_Members__c = :fromPtmId
                  AND Application__r.Program__c = :programId
                  AND Application_Verification_Status__c IN ('Assigned','In Progress')
            ];
        } else {
            avToUpdate = [
                SELECT Id, Program_Team_Members__c, Verifier__c, OwnerId, Application__c, Application_Verification_Status__c
                FROM Application_Verification__c
                WHERE Id IN :applicationVerificationIds
                  AND Application__r.Program__c = :programId
            ];
        }

        if(avToUpdate.isEmpty()) return;

        for(Application_Verification__c av : avToUpdate){
            av.Program_Team_Members__c = toPtm.Id;
            av.Verifier__c = toPtm.User__c;
            av.OwnerId = toPtm.User__c;
            // keep status assigned to indicate newly assigned to new user
            av.Application_Verification_Status__c = 'Assigned';
        }

        update avToUpdate;
    }


    @AuraEnabled
    public static Integer getReassignListCount(Id programId, Id currentPtmId) {
        if (programId == null || currentPtmId == null) return 0;

        List<AggregateResult> ar = [
            SELECT COUNT(Id) c
            FROM Application_Verification__c
            WHERE Program_Team_Members__c = :currentPtmId
              AND Application__r.Program__c = :programId
              AND Application_Verification_Status__c IN ('Assigned','In Progress')
        ];
        return (ar.isEmpty()) ? 0 : Integer.valueOf(String.valueOf(ar[0].get('c')));
    }

    @AuraEnabled
    public static List<ApplicationDTO> getReassignListPage(
        Id programId,
        Id currentPtmId,
        Integer pageNumber,
        Integer pageSize
    ) {
        List<ApplicationDTO> out = new List<ApplicationDTO>();
        if (programId == null || currentPtmId == null) return out;

        Integer pNum  = normalizePageNumber(pageNumber);
        Integer pSize = normalizePageSize(pageSize);
        Integer offsetVal = (pNum - 1) * pSize;

        List<Application_Verification__c> rows = [
            SELECT Id,
                   Application__c,
                   Application__r.Name,
                   Application__r.First_Name__c,
                   Application__r.Last_Name__c,
                   Application_Verification_Status__c
            FROM Application_Verification__c
            WHERE Program_Team_Members__c = :currentPtmId
              AND Application__r.Program__c = :programId
              AND Application_Verification_Status__c IN ('Assigned','In Progress')
            ORDER BY Application__r.Name
            LIMIT :pSize OFFSET :offsetVal
        ];

        for (Application_Verification__c av : rows) {
            ApplicationDTO dto = new ApplicationDTO();
            dto.appId = av.Application__c;
            dto.avId  = av.Id; // IMPORTANT for reassign
            dto.appName = av.Application__r.Name;
            dto.applicantName =
                (av.Application__r.First_Name__c != null ? av.Application__r.First_Name__c : '') +
                ' ' +
                (av.Application__r.Last_Name__c != null ? av.Application__r.Last_Name__c : '');
            dto.status = av.Application_Verification_Status__c;
            out.add(dto);
        }
        return out;
    }



    // Add these methods into your existing ApplicationAllocationLwcController class
    // — reassign for stage-aware (Application / Document)
    @AuraEnabled
    public static void reassignApplicationsByStage(Id programId, String verificationType, Id fromPtmId, Id toPtmId, List<Id> applicationVerificationIds){
        if(programId == null) throw new AuraHandledException('Program Id required.');
        if(fromPtmId == null) throw new AuraHandledException('From Verifier (PTM) required.');
        if(toPtmId == null) throw new AuraHandledException('To Verifier (PTM) required.');

        // lookup target PTM to get User__c
        Program_Team_Members__c toPtm = [
            SELECT Id, User__c
            FROM Program_Team_Members__c
            WHERE Id = :toPtmId
            LIMIT 1
        ];

        if(toPtm == null || toPtm.User__c == null) {
            throw new AuraHandledException('Target verifier has no user linked.');
        }

        List<Application_Verification__c> avToUpdate = new List<Application_Verification__c>();

        // Decide which status field to filter by depending on stage
        if(applicationVerificationIds == null || applicationVerificationIds.isEmpty()){
            if(verificationType == 'Document'){
                // Document: Status__c IN ('Assigned','In Progress')
                avToUpdate = [
                    SELECT Id, Program_Team_Members__c, Verifier__c, OwnerId, Application__c, Status__c
                    FROM Application_Verification__c
                    WHERE Program_Team_Members__c = :fromPtmId
                      AND Application__r.Program__c = :programId
                      AND Status__c IN ('Assigned','In Progress')
                ];
            } else {
                // Application: Application_Verification_Status__c IN ('Assigned','In Progress')
                avToUpdate = [
                    SELECT Id, Program_Team_Members__c, Verifier__c, OwnerId, Application__c, Application_Verification_Status__c
                    FROM Application_Verification__c
                    WHERE Program_Team_Members__c = :fromPtmId
                      AND Application__r.Program__c = :programId
                      AND Application_Verification_Status__c IN ('Assigned','In Progress')
                ];
            }
        } else {
            // Specific AV records selected — no additional status filter (but restricted to program)
            avToUpdate = [
                SELECT Id, Program_Team_Members__c, Verifier__c, OwnerId, Application__c,
                       Status__c, Application_Verification_Status__c
                FROM Application_Verification__c
                WHERE Id IN :applicationVerificationIds
                  AND Application__r.Program__c = :programId
            ];
        }

        if(avToUpdate.isEmpty()) return;

        for(Application_Verification__c av : avToUpdate){
            av.Program_Team_Members__c = toPtm.Id;
            av.Verifier__c = toPtm.User__c;
            av.OwnerId = toPtm.User__c;

            // Reset the appropriate status to 'Assigned' to indicate assignment
            if(verificationType == 'Document'){
                av.Status__c = 'Assigned';
            } else {
                av.Application_Verification_Status__c = 'Assigned';
            }
        }
        update avToUpdate;
    }

    @AuraEnabled
    public static Integer getReassignListCountByStage(
        Id programId,
        String verificationType,
        Id currentPtmId
    ){
        if (programId == null || currentPtmId == null) return 0;

        if (verificationType == 'Document') {
            List<AggregateResult> ar = [
                SELECT COUNT_DISTINCT(Application__c) c
                FROM Application_Verification__c
                WHERE Program_Team_Members__c = :currentPtmId
                  AND Application__r.Program__c = :programId
                  AND Status__c IN ('Assigned','In Progress')
            ];
            return Integer.valueOf(ar[0].get('c'));
        } else {
            List<AggregateResult> ar = [
                SELECT COUNT_DISTINCT(Application__c) c
                FROM Application_Verification__c
                WHERE Program_Team_Members__c = :currentPtmId
                  AND Application__r.Program__c = :programId
                  AND Application_Verification_Status__c IN ('Assigned','In Progress')
            ];
            return Integer.valueOf(ar[0].get('c'));
        }
    }

    @AuraEnabled
    public static List<ApplicationDTO> getReassignListPageByStage(
        Id programId,
        String verificationType,
        Id currentPtmId,
        Integer pageNumber,
        Integer pageSize
    ) {
        List<ApplicationDTO> finalResult = new List<ApplicationDTO>();

        if (programId == null || currentPtmId == null) {
            return finalResult;
        }

        Integer pNum  = normalizePageNumber(pageNumber);
        Integer pSize = normalizePageSize(pageSize);
        Integer offsetVal = (pNum - 1) * pSize;

        // 🔹 STEP 1: Fetch ALL rows (no LIMIT / OFFSET)
        List<Application_Verification__c> rows;

        if (verificationType == 'Document') {
            rows = [
                SELECT Id,
                       Application__c,
                       Application__r.Name,
                       Status__c
                FROM Application_Verification__c
                WHERE Program_Team_Members__c = :currentPtmId
                  AND Application__r.Program__c = :programId
                  AND Status__c IN ('Assigned','In Progress')
                ORDER BY Application__r.Name
            ];
        } else {
            rows = [
                SELECT Id,
                       Application__c,
                       Application__r.Name,
                       Application_Verification_Status__c
                FROM Application_Verification__c
                WHERE Program_Team_Members__c = :currentPtmId
                  AND Application__r.Program__c = :programId
                  AND Application_Verification_Status__c IN ('Assigned','In Progress')
                ORDER BY Application__r.Name
            ];
        }

        // 🔹 STEP 2: De-duplicate by Application__c
        Map<Id, ApplicationDTO> uniqueApps = new Map<Id, ApplicationDTO>();

        for (Application_Verification__c av : rows) {
            if (!uniqueApps.containsKey(av.Application__c)) {
                ApplicationDTO dto = new ApplicationDTO();
                dto.appId   = av.Application__c;
                dto.avId    = av.Id;
                dto.appName = av.Application__r.Name;
                dto.status  = (verificationType == 'Document')
                    ? av.Status__c
                    : av.Application_Verification_Status__c;

                uniqueApps.put(av.Application__c, dto);
            }
        }

        // 🔹 STEP 3: Convert to List
        List<ApplicationDTO> dedupedList = uniqueApps.values();

        // 🔹 STEP 4: Apply pagination AFTER deduplication
        Integer startIndex = Math.min(offsetVal, dedupedList.size());
        Integer endIndex   = Math.min(startIndex + pSize, dedupedList.size());

        for (Integer i = startIndex; i < endIndex; i++) {
            finalResult.add(dedupedList[i]);
        }

        return finalResult;
    }

    // Assigned apps pagination for verifiers (existing)
    @AuraEnabled
    public static Integer getAssignedApplicationsCount(Id programId, List<Id> ptms){
        if(ptms == null || ptms.isEmpty()) return 0;
        List<AggregateResult> ar = [
            SELECT COUNT(Id) c
            FROM Application_Verification__c
            WHERE Program_Team_Members__c IN :ptms
              AND Application__r.Program__c = :programId
        ];
        return !ar.isEmpty() ? Integer.valueOf(String.valueOf(ar[0].get('c'))) : 0;
    }

    @AuraEnabled
    public static List<ApplicationDTO> getAssignedApplicationsPage(Id programId, List<Id> ptms, Integer pageNumber, Integer pageSize){
        List<ApplicationDTO> out = new List<ApplicationDTO>();
        if(ptms == null || ptms.isEmpty()) return out;

        Integer pNum = normalizePageNumber(pageNumber);
        Integer pSize = normalizePageSize(pageSize);
        Integer offset = (pNum - 1) * pSize;

        for(Application_Verification__c av : [
            SELECT Id, Application__c, Application__r.Name, Application__r.First_Name__c, Application__r.Last_Name__c, Application_Verification_Status__c
            FROM Application_Verification__c
            WHERE Program_Team_Members__c IN :ptms
              AND Application__r.Program__c = :programId
            ORDER BY Application__r.Name
            LIMIT :pSize OFFSET :offset
        ]){
            ApplicationDTO dto = new ApplicationDTO();
            dto.appId = av.Application__c;
            dto.appName = av.Application__r.Name;
            dto.applicantName = ((av.Application__r.First_Name__c != null) ? av.Application__r.First_Name__c : '') + ' ' + ((av.Application__r.Last_Name__c != null) ? av.Application__r.Last_Name__c : '');
            dto.status = av.Application_Verification_Status__c;
            dto.currentVerificationId = av.Id;
            out.add(dto);
        }
        return out;
    }

}
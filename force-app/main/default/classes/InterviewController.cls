global with sharing class InterviewController {
    
    public class CsvEvaluationRow {
        public String applicationNumber;
        public String applicantName;
        public String program;
        public String round;
        public String evaluatedBy;
        
        // Dynamic criteria: <Criteria Name , Score>
        public Map<String, String> criteriaMap = new Map<String, String>();
    }
    
    
    
    
    
    
    private static String norm(String s) {
        return s == null ? '' : s.trim().toUpperCase();
    }

  
global class InterviewMatrixRequest {
    @AuraEnabled public Integer pageSize;
    @AuraEnabled public Integer pageNumber;
    @AuraEnabled public Integer round;
    @AuraEnabled public String programCode;
    @AuraEnabled public List<Id> applicationIds;
}


    /* =========================================================
       RESPONSE WRAPPERS
       ========================================================= */

    public class InterviewMatrixPage {
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public List<CriteriaHeader> criteriaHeaders;
        @AuraEnabled public List<MatrixRow> rows;
    }

    public class CriteriaHeader {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
    }

   public class MatrixRow {
    @AuraEnabled public String applicationNumber;
    @AuraEnabled public String applicantName;
    @AuraEnabled public String roundName;
    @AuraEnabled public String evaluatedBy;
    @AuraEnabled public Decimal totalScore;          // ✅ NEW
    @AuraEnabled public Map<String, Decimal> scores;
}


    /* =========================================================
       MAIN METHOD
       ========================================================= */

   @AuraEnabled
public static InterviewMatrixPage getInterviewMatrixPage(
    List<Id> applicationIds,
    Id roundId
) {
    InterviewMatrixPage page = new InterviewMatrixPage();
    page.criteriaHeaders = new List<CriteriaHeader>();
//     CriteriaHeader totalHeader = new CriteriaHeader();
// totalHeader.key = 'TOTAL_SCORE';
// totalHeader.label = 'Total Score';
// page.criteriaHeaders.add(totalHeader);
    page.rows = new List<MatrixRow>();

    System.debug('Application Ids => ' + applicationIds);
    System.debug('Round Id => ' + roundId);

    /* ---------- Guards ---------- */
    if (applicationIds == null || applicationIds.isEmpty() || roundId == null) {
        page.totalRecords = 0;
        return page;
    }

    /* =========================================================
       1️⃣ CRITERIA HEADERS (ROUND)
       ========================================================= */

    // 1️⃣ Criteria headers first
for (ScoringTemplate__c st : [
    SELECT Id, CriteriaName__c
    FROM ScoringTemplate__c
    WHERE Round__c = :roundId
    ORDER BY CriteriaName__c
]) {
    CriteriaHeader ch = new CriteriaHeader();
    ch.key = st.Id;
    ch.label = st.CriteriaName__c;
    page.criteriaHeaders.add(ch);
}

// 2️⃣ Total Score LAST
CriteriaHeader totalHeader = new CriteriaHeader();
totalHeader.key = 'TOTAL_SCORE';
totalHeader.label = 'Total Score';
page.criteriaHeaders.add(totalHeader);


    /* =========================================================
       2️⃣ FETCH APPLICATION SLOT BOOKINGS
       (Application → Slot → Completed)
       ========================================================= */

    List<ApplicationSlotBooking__c> slots = [
        SELECT Id,
               Application__r.Name,
               Applicant_Name__c,
               RoundMaster__r.Name,

               (SELECT Id, Net_Score__c
 FROM Round_Results__r
 LIMIT 1),

               (SELECT Id,
                       EvaluatedBy__c,
                       (SELECT Scoring_Template__c, Score__c
                        FROM Individual_Criteria_Results__r)
                FROM Evaluations__r
               )
        FROM ApplicationSlotBooking__c
        WHERE Application__c IN :applicationIds
          AND RoundMaster__c = :roundId
          AND Id IN (
              SELECT ApplicationSlotBooking__c
              FROM Round_Result__c
          )
        ORDER BY Application__r.Name
    ];

    /* =========================================================
       3️⃣ BUILD MATRIX ROWS
       ========================================================= */

    /* =========================================================
   3️⃣ BUILD MATRIX ROWS (ONE ROW PER SLOT)
   ========================================================= */

for (ApplicationSlotBooking__c slot : slots) {

    MatrixRow row = new MatrixRow();
    row.applicationNumber = slot.Application__r.Name;
    row.applicantName = slot.Applicant_Name__c;
    row.roundName = slot.RoundMaster__r.Name;
    row.evaluatedBy = 'Multiple Evaluators'; // or '' if you prefer
    row.scores = new Map<String, Decimal>();

    // ---- Total Score (slot-level) ----
    if (slot.Round_Results__r != null && !slot.Round_Results__r.isEmpty()) {
        row.totalScore = slot.Round_Results__r[0].Net_Score__c;
    }

    // ---- Aggregate criteria scores (optional) ----
    // If you want to show per-criteria averages / sums, we can add that.
    // For now, leave criteria cells empty (clean + correct).

    page.rows.add(row);
}



    /* =========================================================
       4️⃣ TOTAL RECORD COUNT
       ========================================================= */

    page.totalRecords = slots.size();

    return page;
}

    @AuraEnabled
    public static Interview_Excel_Log__c getlogStatus(String logId){
        List<Interview_Excel_Log__c> excelLogList = [SELECT Id, Status__c, Error_Message__c
        FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1];
        if(excelLogList.isEmpty()){
            return null;
        }
        return excelLogList[0];
    }


    
    
    
    @AuraEnabled
    public static String processInterview(String docId,String pgm){
        try {
            
                Interview_Excel_Log__c logRec = new Interview_Excel_Log__c(
                    ContentDocumentId__c = docId,
                    Status__c = 'Created'
                );
                insert logRec;
            InterviewQueueableProcess q = new InterviewQueueableProcess(docId,pgm,logRec.Id);
            System.enqueueJob(q);
            return logRec.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<ScoringTemplate__c> getScoringTemplates(String roundId){
        try {
            List<ScoringTemplate__c> listTemplates =[SELECT Id,CriteriaName__c,Round__r.RoundNumber__c,
            Maximum_Score__c 
            FROM ScoringTemplate__c 
            WHERE Round__c=:roundId];
            system.debug('List of Templates are '+listTemplates);
            
            if(!listTemplates.isEmpty()){
                return listTemplates;
            }
            return null;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    
    @AuraEnabled(cacheable=true)
    public static List<RoundMaster__c> getInterviewRounds(String pgmCode){
        try{
            if(pgmCode == null || pgmCode == ''){
                return null;
            }
            List<RoundMaster__c> listRounds= [SELECT Id,RoundNumber__c, Name 
        FROM RoundMaster__c WHERE Program__r.Program_Code__c = :pgmCode 
        ORDER BY RoundNumber__c ASC];
            system.debug('Rounds are '+listRounds);
            if(listRounds.size()>0){
                return listRounds;
            }
            return null;
        }
        catch(Exception e){
            throw new AuraHandledException(e.getMessage());
        }
        
    } 
    
    public class InterviewWrapper {
        @AuraEnabled public String applicationNumber;
        @AuraEnabled public String applicantName;
        @AuraEnabled public String applicantStateManagement;
        @AuraEnabled public Id Id;
        @AuraEnabled public String applicationUrl;
        @AuraEnabled public String evaluationScore;
    }
    
    
    @AuraEnabled(cacheable=true)
    public static List<InterviewWrapper> getShortlistedApplications(){
        try {
            List<InterviewWrapper> result = new List<InterviewWrapper>();
            for (Application__c app : [
            SELECT Id,
                   Application_Number__c,
                   Applicant__r.FirstName,Applicant__r.LastName,
                   Applicant__r.MiddleName,
                   Applicant_State_Management__c,
                   Evaluation_Score__c,Name
            FROM Application__c
            WHERE (Applicant_State_Management__c = 'Profile Shortlisted'
            OR Applicant_State_Management__c = 'Interview Round 1'
            OR Applicant_State_Management__c = 'Interview Round 2')
            AND Id NOT IN (
                SELECT Applicant__c
                FROM Account
                WHERE RecordType.DeveloperName = 'Student'
                AND Applicant__c != null
            )
            AND Program__r.Program_Code__c = 'GMP' 
            AND Applicant__c <> NULL
            ORDER BY Applicant__r.Name
        ]) {
                InterviewWrapper w = new InterviewWrapper();
                w.Id = app.Id;
                w.applicationNumber = app.Name;
                List<String> nameParts = new List<String>();
                
                if (app.Applicant__r != null) {
                    if (String.isNotBlank(app.Applicant__r.FirstName)) {
                        nameParts.add(app.Applicant__r.FirstName);
                    }
                    if (String.isNotBlank(app.Applicant__r.MiddleName)) {
                        nameParts.add(app.Applicant__r.MiddleName);
                    }
                    if (String.isNotBlank(app.Applicant__r.LastName)) {
                        nameParts.add(app.Applicant__r.LastName);
                    }
                }
                
                w.applicantName = String.join(nameParts, ' ');
                
                w.applicantStateManagement = app.Applicant_State_Management__c;
                w.applicationUrl = '/' + app.Id;
                w.evaluationScore = String.valueOf(app.Evaluation_Score__c);
                result.add(w);
            }
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    
    public class ScoreWrapper {
        @AuraEnabled public Id scoringTemplateId;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String comment;
    }
    
    @AuraEnabled
    public static void upsertIndividualResults(
        Id evaluationId,
        String payload
    ) {
        if (evaluationId == null) {
            return;
        }

        List<Evaluation__c> evalCheck = [
            SELECT Id, Status__c, EvaluatedUser__c
            FROM Evaluation__c
            WHERE Id = :evaluationId
            LIMIT 1
        ];

        Id currentAccId = getCurrentEvaluatorAccountId();

        if (evalCheck.isEmpty()
            || evalCheck[0].EvaluatedUser__c != currentAccId
            || evalCheck[0].Status__c == 'Complete') {
            throw new AuraHandledException('This evaluation is already complete and cannot be edited.');
        }

        List<ScoreWrapper> wrapper = (List<ScoreWrapper>) JSON.deserialize(
            payload,
            List<ScoreWrapper>.class
        );
        if (wrapper == null || wrapper.isEmpty()) {
            return;
        }

        Map<Id, Individual_Criteria_Result__c> existingMap =
            new Map<Id, Individual_Criteria_Result__c>();

        for (Individual_Criteria_Result__c r : [
            SELECT Id, Scoring_Template__c
            FROM Individual_Criteria_Result__c
            WHERE Evaluation__c = :evaluationId
        ]) {
            existingMap.put(r.Scoring_Template__c, r);
        }

        List<Individual_Criteria_Result__c> toUpsert = new List<Individual_Criteria_Result__c>();

        for (ScoreWrapper w : wrapper) {
            if (w.scoringTemplateId == null) continue;

            Individual_Criteria_Result__c rec;

            if (existingMap.containsKey(w.scoringTemplateId)) {
                rec = existingMap.get(w.scoringTemplateId);
            } else {
                rec = new Individual_Criteria_Result__c(
                    Evaluation__c = evaluationId,
                    Comments__c = w.comment,
                    Scoring_Template__c = w.scoringTemplateId
                );
            }
            rec.Comments__c = w.comment;
            rec.Score__c = w.score;
            toUpsert.add(rec);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
    }
    
    
    @AuraEnabled
    public static Map<String,String> getHighestCriteriaCount(){
        try{
            List<Evaluation__c> listEvals= [SELECT Id,
           Applicant_Name__c,
             EvaluatedBy__c,Program__c,
            (SELECT Id,Score__c,Criteria_Description__c,Scoring_Template__r.Round__r.RoundNumber__c,
            Scoring_Template__r.Round__r.Name
            FROM Individual_Criteria_Results__r ORDER BY Criteria_Description__c ASC),
            Criterias_Scored__c,Total_Score__c
            FROM Evaluation__c
            WHERE Status__c = 'Complete'  AND Name <> Null
            ORDER BY Criterias_Scored__c DESC ];
            
            Map<String,Individual_Criteria_Result__c> mapRoundToCriteria = new Map<String,Individual_Criteria_Result__c>();
            Integer i=0;
            Map<String,String> resultMap = new Map<String,String>();
            for(Evaluation__c eval :listEvals){
                if(eval?.Individual_Criteria_Results__r!=null){
                    for(Individual_Criteria_Result__c crit:eval?.Individual_Criteria_Results__r ){
                        if(!mapRoundToCriteria.containsKey(crit.Id)){
                            mapRoundToCriteria.put(crit.Id,crit);
                            resultMap.put('criteria'+i+' '+crit.Scoring_Template__r.Round__r.Name+' '+String.valueOf(crit.Scoring_Template__r.Round__r.RoundNumber__c),crit.Criteria_Description__c);
                            i+=1;
                        }
                    }
                }
            }
    
            
            system.debug('Result map '+resultMap);
            return resultMap;
            
        }catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    
    @AuraEnabled
    public static List<Evaluation__c> updateEvalScoreExport(){
        try {
            
            List<Evaluation__c> listEvals= [SELECT Id,
            Applicant_Name__c,
             EvaluatedBy__c,Program__c,Round__c,
            (SELECT Id,Score__c,Criteria_Description__c
             FROM Individual_Criteria_Results__r ORDER BY Criteria_Description__c ASC),
             Criterias_Scored__c,Total_Score__c
            FROM Evaluation__c
            WHERE Status__c = 'Complete'  
            AND Name <> Null
            ];
            
            
            
            
            if(!listEvals.isEmpty()){
                return listEvals;
            }
            return null;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String getApplicationUrl(String slotId){
        try {
            System.debug('1. Method start — slotId: ' + slotId);
            
            ApplicationSlotBooking__c slot = [
            SELECT Application__c 
            FROM ApplicationSlotBooking__c  
            WHERE Id = :slotId 
            LIMIT 1
        ];
            
            System.debug('2. Query result — slot: ' + JSON.serialize(slot));
            
            Network n = [
            SELECT Id, UrlPathPrefix
            FROM Network
            WHERE Name = 'FacultyPortal'
            LIMIT 1
        ];
            
            System.debug('3. Network found — Id: ' + n.Id + ', Prefix: ' + n.UrlPathPrefix);
            
            String Url = Network.getLoginUrl(n.Id);
            System.debug('4. Login URL: ' + Url);
            
            if (Url.endsWith('/login')) {
                Url = Url.substring(0, Url.length() - 5);
            }
            System.debug('5. After removing /login: ' + Url);
            
            System.debug('6. Application Id: ' + slot.Application__c);
            
            Url += 'application/' + slot.Application__c;
            System.debug('7. Final constructed URL before return: ' + Url);
            
            return Url;
            
        } catch (Exception e) {
            System.debug('❌ ERROR — ' + e.getMessage());
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    
    @AuraEnabled
    public static string getVFPageUrl(String applicationId){
        try {
            
            Map<String,String> mapApplicationToProgram = new Map<String,String>();
            mapApplicationToProgram.put('PGDM','Application_PDF');
            mapApplicationToProgram.put('PGPM','Application_PDF_V1');
            mapApplicationToProgram.put('PGDM-BM','Application_PDF');
            mapApplicationToProgram.put('GMP','GMP_Application_Form_PDF');
            List<Community_Setting__mdt> listVFUrl = [SELECT Id,Community_URL__c FROM Community_Setting__mdt
        WHERE DeveloperName = 'VisualforceUrl' LIMIT 1];
            
            List<Application__c> applicationList = [SELECT Id,
        Program__r.Program_Code__c  
        FROM Application__c WHERE Id=:applicationId LIMIT 1];
            if(applicationList.size()>0 && listVFUrl.size()>0){
                String url = listVFUrl[0].Community_URL__c+'/apex/'
                    + mapApplicationToProgram.get(applicationList[0].Program__r.Program_Code__c)
                    + '?Id=' + applicationList[0].Id;
                return url;
                
            }
            return '';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static string checkInterviewStatus(String slotId) {
        try {
            Id currentAccId = getCurrentEvaluatorAccountId();
            if (currentAccId == null) {
                return 'Pending';
            }

            List<Evaluation__c> listEvalId = [
                SELECT Id, Status__c, EvaluatedUser__c
                FROM Evaluation__c
                WHERE Application_Slot_Booking__c = :slotId
                AND EvaluatedUser__c = :currentAccId
                LIMIT 1
            ];

            if (!listEvalId.isEmpty() && listEvalId[0].EvaluatedUser__c == currentAccId) {
                if (listEvalId[0].Status__c == 'Complete') {
                    return 'Complete';
                }
            }

            return 'Pending';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String finishInterview(String evaluationId) {
        try {
            List<Evaluation__c> listEval = [
                SELECT Id, Application_Slot_Booking__c, Total_Score__c, Status__c, EvaluatedUser__c
                FROM Evaluation__c
                WHERE Id = :evaluationId
                LIMIT 1
            ];

            if (listEval.isEmpty()) {
                throw new AuraHandledException('Evaluation not found.');
            }

            Id currentAccId = getCurrentEvaluatorAccountId();
            if (listEval[0].EvaluatedUser__c != currentAccId) {
                throw new AuraHandledException('You are not authorized to complete this evaluation.');
            }

            listEval[0].Status__c = 'Complete';
            String appSlotId = listEval[0].Application_Slot_Booking__c;
            List<ApplicationSlotBooking__c> appSlotData = [SELECT Id,Panel_Master__c FROM ApplicationSlotBooking__c WHERE Id = :appSlotId];
            String programTeamId = appSlotData[0]?.Panel_Master__c;
            List<PanelInterviewer__c> listInterviewers = [SELECT Id FROM PanelInterviewer__c 
            WHERE PanelMaster__c = :programTeamId];
           // List<Program_Team_Members__c> listProgramTeamMembers= [SELECT Id FROM Program_Team_Members__c WHERE Program_Team__c = :programTeamId];
            
            try {
                update listEval;
                
                // List<Evaluation__c> listRemainingEvals = [
                //     SELECT Id, Status__c,Total_Score__c
                //     FROM Evaluation__c
                //     WHERE Application_Slot_Booking__c = :listEval[0].Application_Slot_Booking__c
                //     ];
                
                
                // Set<Id> evalIds = new Set<Id>();
                // Boolean isRoundComplete = true;
                // Decimal totalScoreSum = 0;
                // Integer criteriaCount = 0;
                // Boolean allTeamMembersDone = listRemainingEvals.size() == listInterviewers.size();
                // for (Evaluation__c eval : listRemainingEvals) {
                //     if (eval.Status__c != 'Complete' && isRoundComplete && allTeamMembersDone) {
                //         isRoundComplete = false;
                        
                //     } else {
                //         evalIds.add(eval.Id);
                //     }
                // }
                
                // if (isRoundComplete) {
                //     for (Evaluation__c eval : listRemainingEvals) {
                //         totalScoreSum+=eval.Total_Score__c;
                //     }
                    
                    
                
                    
                //     List<ApplicationSlotBooking__c> appSlotBooking = [
                //             SELECT Id, Application__c
                //             FROM ApplicationSlotBooking__c
                //             WHERE Id = :listEval[0].Application_Slot_Booking__c
                //         LIMIT 1
                //         ];
                    
                //     Round_Result__c roundResult = new Round_Result__c(
                //         // Application__c = appSlotBooking[0].Application__c,
                //     ApplicationSlotBooking__c = appSlotBooking[0].Id,
                //     Net_Score__c = totalScoreSum);
                    
                //     try {
                //         insert roundResult;
                        
                //         if (appSlotBooking.size() > 0) {
                //             appSlotBooking[0].Round_Result__c = roundResult.Id;
                //             try {
                //                 update appSlotBooking;
                //             } catch (DMLException e) {
                //                 System.debug('Could not update Application Slot Booking: ' + e.getMessage());
                //                 return e.getMessage();
                //             }
                //         }
                        
                //     } catch (DMLException e) {
                //         System.debug('Could not Insert Round Result Record ' + e.getMessage());
                //         return e.getMessage();
                //     }
                // }
                
                
            } catch (DMLException e) {
                System.debug('Could not Update Evaluation Record ' + e.getMessage());
                return e.getMessage();
            }
            
            return 'Success';
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    
    @AuraEnabled
    public static String getEvaluationId(String slotId){
        try {
            List<Evaluation__c> listEvalId = [SELECT Id 
            FROM Evaluation__c 
            WHERE EvaluatedUser__r.PersonEmail = :UserInfo.getUserEmail() 
            AND Application_Slot_Booking__c = :slotId
            LIMIT 1];
            
            if(listEvalId.isEmpty()){
                
                List<ApplicationSlotBooking__c> appSlotBookingList = [SELECT RoundMaster__c 
                FROM ApplicationSlotBooking__c 
                WHERE RoundMaster__c<>NULL AND Id=:slotId 
                LIMIT 1];
                
                List<ScoringTemplate__c> criteriaList = [SELECT 
                Id
                FROM ScoringTemplate__c 
                WHERE Round__c = :appSlotBookingList[0].RoundMaster__c];
                
                List<Account> listEvaluator= [SELECT Id,Name
                FROM Account 
                WHERE PersonEmail = :UserInfo.getUserEmail() 
                LIMIT 1];
                
                Evaluation__c evalRecord = new Evaluation__c(Application_Slot_Booking__c = slotId,
               EvaluatedUser__c = listEvaluator[0].Id,EvaluatedBy__c = listEvaluator[0].Name,
                // Scoring_Template__c =criteriaList[0].Id,
                Status__c = 'Pending' );
                
                try{
                    insert evalRecord;
                    return  evalRecord.Id;
                }
                catch(DMLException e){
                    system.debug('Could not insert evalRecord '+e.getMessage());
                }
                
                
            }
            else{
                return listEvalId[0].Id;
            }
            return '';
            
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    public class SlotBookingWrapper {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  applicantName;
        @AuraEnabled public String  programName;
        @AuraEnabled public Id      applicationId;
        @AuraEnabled public Date    slotDate;
        @AuraEnabled public Time    slotStartTime;
        @AuraEnabled public Time    slotEndTime;
        @AuraEnabled public String  mode;
        @AuraEnabled public Id      panelMasterId;
        @AuraEnabled public Id      roundMasterId;
        @AuraEnabled public String  roundMasterName;
        @AuraEnabled public String  evalStatus;   // current user's Evaluation Status
    }

    /**
     * Returns all ApplicationSlotBooking__c records for a given SlotMaster__c,
     * filtered to panels the current user belongs to, enriched with that user's
     * evaluation status per booking.
     */
    @AuraEnabled(cacheable=true)
    public static List<SlotBookingWrapper> getSlotBookingsBySlotMaster(Id slotMasterId) {
        try {
            String currentUserEmail = UserInfo.getUserEmail();

            List<Account> accList = [
                SELECT Id FROM Account
                WHERE PersonEmail = :currentUserEmail
                LIMIT 1
            ];

            if (accList.isEmpty()) {
                return new List<SlotBookingWrapper>();
            }

            Account accountEmp = accList[0];

            Set<Id> panelIds = new Set<Id>();
            for (PanelInterviewer__c ptm : [
                SELECT Id, Account__c, PanelMaster__c FROM PanelInterviewer__c
                WHERE Account__c = :accountEmp.Id
            ]) {
                if (ptm.PanelMaster__c != null) panelIds.add(ptm.PanelMaster__c);
            }

            List<ApplicationSlotBooking__c> bookings = [
                SELECT Id,
                       Name,
                       Applicant_Name__c,
                       Program_Name__c,
                       Application__c,
                       Slot_Date__c,
                       Slot_Start_Time__c,
                       Slot_End_Time__c,
                       Mode__c,
                       Panel_Master__c,
                       RoundMaster__c,
                       RoundMaster__r.Name
                FROM ApplicationSlotBooking__c
                WHERE SlotMaster__c = :slotMasterId
                AND Panel_Master__c IN :panelIds
                ORDER BY Applicant_Name__c ASC
            ];

            if (bookings.isEmpty()) {
                return new List<SlotBookingWrapper>();
            }

            // Fetch current user's evaluations for these bookings in one query
            Set<Id> bookingIds = new Map<Id, ApplicationSlotBooking__c>(bookings).keySet();
            Map<Id, String> bookingToEvalStatus = new Map<Id, String>();
            for (Evaluation__c ev : [
                SELECT Id, Application_Slot_Booking__c, Status__c
                FROM Evaluation__c
                WHERE EvaluatedUser__r.PersonEmail = :currentUserEmail
                  AND Application_Slot_Booking__c IN :bookingIds
            ]) {
                bookingToEvalStatus.put(ev.Application_Slot_Booking__c, ev.Status__c);
            }

            // Build wrappers
            List<SlotBookingWrapper> result = new List<SlotBookingWrapper>();
            for (ApplicationSlotBooking__c b : bookings) {
                SlotBookingWrapper w  = new SlotBookingWrapper();
                w.id              = b.Id;
                w.name            = b.Name;
                w.applicantName   = b.Applicant_Name__c;
                w.programName     = b.Program_Name__c;
                w.applicationId   = b.Application__c;
                w.slotDate        = b.Slot_Date__c;
                w.slotStartTime   = b.Slot_Start_Time__c;
                w.slotEndTime     = b.Slot_End_Time__c;
                w.mode            = b.Mode__c;
                w.panelMasterId   = b.Panel_Master__c;
                w.roundMasterId   = b.RoundMaster__c;
                w.roundMasterName = b.RoundMaster__r?.Name;
                w.evalStatus      = bookingToEvalStatus.containsKey(b.Id)
                                    ? bookingToEvalStatus.get(b.Id)
                                    : 'Not Started';
                result.add(w);
            }
            return result;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String,List<SObject>> getEvaluationCriteria(Id applicationSlotBookingId){
        try {
            List<ScoringTemplate__c> criteriaList = new List<ScoringTemplate__c>();
            List<ApplicationSlotBooking__c> appSlotBookingList = [SELECT RoundMaster__c,Panel_Master__r.ProgramTeam__c 
            FROM ApplicationSlotBooking__c WHERE RoundMaster__c<>NULL AND Id=:applicationSlotBookingId LIMIT 1];
            if(!appSlotBookingList.isEmpty()){
                
                List<Evaluation__c> listEvaluation = [SELECT Id FROM Evaluation__c 
                WHERE EvaluatedUser__r.PersonEmail = :UserInfo.getUserEmail() 
                AND Application_Slot_Booking__c = :applicationSlotBookingId LIMIT 1];
                
                criteriaList = [SELECT Id,CriteriaName__c,Name,Maximum_Score__c
                    FROM ScoringTemplate__c 
                    WHERE Round__c = :appSlotBookingList[0].RoundMaster__c];
                
                
                
                if(listEvaluation.isEmpty()){
                    return new Map<String,List<SObject>>{'EVAL_ABSENT'=>criteriaList};
                }
                else{
                    Boolean isCompleted = false;
                    List<Individual_Criteria_Result__c> indiResults = [SELECT Id,Evaluation__c,
                    Scoring_Template__c,Score__c,Comments__c,
                    Scoring_Template__r.CriteriaName__c 
                    FROM Individual_Criteria_Result__c 
                    WHERE Evaluation__c = :listEvaluation[0].Id];
                    
                    // List<Program_Team_Members__c> listProgramTeam = [SELECT Id FROM Program_Team_Members__c 
                    // WHERE Program_Team__c  = :appSlotBookingList[0].Panel_Master__r.ProgramTeam__c];
                    
                    isCompleted = criteriaList.size() == indiResults.size();
                    if(isCompleted){
                        // return new Map<String,List<SObject>>{'INTERVIEW_COMPLETE'=>indiResults};
                    }
                    return new Map<String,List<SObject>>{'EVAL_REMAINING'=>criteriaList,'EVAL_COMPLETE'=>indiResults,
                    'VALUE='+String.valueOf(criteriaList.size() - indiResults.size())=>new List<SObject>()};
                    
                }
                
                
            }
            return new Map<String,List<Sobject>>{'EMPTY'=>new List<SObject>()};
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Resolves the Person Account Id for the current running user.
     * Centralizes the "who is scoring right now" lookup so every method
     * compares against Evaluation__c.EvaluatedUser__c by Id, not by email string matching.
     */
    private static Id getCurrentEvaluatorAccountId() {
        List<Account> accList = [
            SELECT Id
            FROM Account
            WHERE PersonEmail = :UserInfo.getUserEmail()
            LIMIT 1
        ];
        return accList.isEmpty() ? null : accList[0].Id;
    }
}
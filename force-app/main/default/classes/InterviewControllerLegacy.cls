public with sharing class InterviewControllerLegacy {
    
    @AuraEnabled(cacheable=true)
    public static List<InterviewWrapper> getShortlistedApplications() {
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
    
    @AuraEnabled
    public static List<ScoringTemplate__c> getScoringTemplates(String roundId) {
        try {
            List<ScoringTemplate__c> listTemplates =[SELECT Id,CriteriaName__c,Round__r.RoundNumber__c,
            Maximum_Score__c, CriteriaDescription__c 
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
    
    @AuraEnabled
    public static String processInterview(String docId,String pgm) {
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
    public static Interview_Excel_Log__c getlogStatus(String logId) {
        List<Interview_Excel_Log__c> excelLogList = [SELECT Id, Status__c, Error_Message__c
        FROM Interview_Excel_Log__c WHERE Id = :logId LIMIT 1];
        if(excelLogList.isEmpty()){
            return null;
        }
        return excelLogList[0];
    }
    
    @AuraEnabled
    public static InterviewMatrixPage getInterviewMatrixPage(List<Id> applicationIds, Id roundId) {
        InterviewMatrixPage page = new InterviewMatrixPage();
        page.criteriaHeaders = new List<CriteriaHeader>();
        page.rows = new List<MatrixRow>();
        
        System.debug('Application Ids => ' + applicationIds);
        System.debug('Round Id => ' + roundId);
        
        if (applicationIds == null || applicationIds.isEmpty() || roundId == null) {
            page.totalRecords = 0;
            return page;
        }
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
        
        CriteriaHeader totalHeader = new CriteriaHeader();
        totalHeader.key = 'TOTAL_SCORE';
        totalHeader.label = 'Total Score';
        page.criteriaHeaders.add(totalHeader);
        
        List<ApplicationSlotBooking__c> slots = [
            SELECT Id,
                Application__r.Name,
                Applicant_Name__c,
                RoundMaster__r.Name,

                (SELECT 
                    Id, Net_Score__c
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
        
        for (ApplicationSlotBooking__c slot : slots) {
            
            MatrixRow row = new MatrixRow();
            row.applicationNumber = slot.Application__r.Name;
            row.applicantName = slot.Applicant_Name__c;
            row.roundName = slot.RoundMaster__r.Name;
            row.evaluatedBy = 'Multiple Evaluators';
            row.scores = new Map<String, Decimal>();
            
            if (slot.Round_Results__r != null && !slot.Round_Results__r.isEmpty()) {
                row.totalScore = slot.Round_Results__r[0].Net_Score__c;
            }
            
            page.rows.add(row);
        }
        
        page.totalRecords = slots.size();
        
        return page;
    }
    
    @AuraEnabled
    public static List<Evaluation__c> updateEvalScoreExport() {
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
    public static Map<String,String> getHighestCriteriaCount() {
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
            for (Evaluation__c eval : listEvals) {
                if (eval != null && eval.Individual_Criteria_Results__r != null) {
                    for (Individual_Criteria_Result__c crit : eval.Individual_Criteria_Results__r) {
                        if (!mapRoundToCriteria.containsKey(crit.Id)) {
                            mapRoundToCriteria.put(crit.Id, crit);
                            resultMap.put('criteria' + i + ' ' + crit.Scoring_Template__r.Round__r.Name + ' ' + String.valueOf(crit.Scoring_Template__r.Round__r.RoundNumber__c), crit.Criteria_Description__c);
                            i += 1;
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
    public static String getApplicationUrl(String slotId) {
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
    public static string getVFPageUrl(String applicationId) {
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

    @AuraEnabled(cacheable=true)
    public static List<RoundMaster__c> getInterviewRounds(String pgmCode) {
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
        @AuraEnabled public Decimal totalScore;
        @AuraEnabled public Map<String, Decimal> scores;
    }
}
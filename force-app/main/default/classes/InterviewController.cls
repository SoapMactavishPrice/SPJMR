global with sharing class InterviewController {

    private static final String RECORD_TYPE = 'Interviewer Faculty';
    
    @AuraEnabled
    public static void upsertIndividualResults(Id evaluationId, String payload) {
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
    public static Map<String, String> completeInterviewsBulk(String payload) {
        if (String.isBlank(payload)) {
            return new Map<String, String>();
        }

        List<BulkCompleteRequest> requests = (List<BulkCompleteRequest>) JSON.deserialize(
            payload,
            List<BulkCompleteRequest>.class
        );

        if (requests == null || requests.isEmpty()) {
            return new Map<String, String>();
        }

        Id currentAccId = getCurrentEvaluatorAccountId();
        if (currentAccId == null) {
            throw new AuraHandledException('Evaluator account was not found for the current user.');
        }

        Account currentEvaluator = [
            SELECT Id, Name
            FROM Account
            WHERE Id = :currentAccId
            LIMIT 1
        ];

        Set<Id> bookingIds = new Set<Id>();
        Set<Id> evaluationIds = new Set<Id>();
        for (BulkCompleteRequest request : requests) {
            if (request == null) continue;
            if (request.bookingId != null) bookingIds.add(request.bookingId);
            if (request.evaluationId != null) evaluationIds.add(request.evaluationId);
        }

        Map<Id, Evaluation__c> evaluationById = new Map<Id, Evaluation__c>();
        Map<Id, Evaluation__c> evaluationByBookingId = new Map<Id, Evaluation__c>();

        if (!evaluationIds.isEmpty()) {
            for (Evaluation__c evaluation : [
                SELECT Id, Application_Slot_Booking__c, Status__c, EvaluatedUser__c, EvaluatorComments__c
                FROM Evaluation__c
                WHERE Id IN :evaluationIds
            ]) {
                evaluationById.put(evaluation.Id, evaluation);
                if (evaluation.Application_Slot_Booking__c != null) {
                    evaluationByBookingId.put(evaluation.Application_Slot_Booking__c, evaluation);
                }
            }
        }

        if (!bookingIds.isEmpty()) {
            for (Evaluation__c evaluation : [
                SELECT Id, Application_Slot_Booking__c, Status__c, EvaluatedUser__c, EvaluatorComments__c
                FROM Evaluation__c
                WHERE Application_Slot_Booking__c IN :bookingIds
                AND EvaluatedUser__c = :currentAccId
            ]) {
                evaluationById.put(evaluation.Id, evaluation);
                evaluationByBookingId.put(evaluation.Application_Slot_Booking__c, evaluation);
            }
        }

        Map<String, String> results = new Map<String, String>();
        List<Evaluation__c> evaluationsToInsert = new List<Evaluation__c>();
        Map<Integer, BulkCompleteRequest> insertIndexToRequest = new Map<Integer, BulkCompleteRequest>();

        for (BulkCompleteRequest request : requests) {
            if (request == null || request.bookingId == null) {
                continue;
            }

            Evaluation__c evaluation = request.evaluationId == null
                ? null
                : evaluationById.get(request.evaluationId);

            if (evaluation == null) {
                evaluation = evaluationByBookingId.get(request.bookingId);
            }

            if (evaluation == null) {
                Evaluation__c newEvaluation = new Evaluation__c(
                    Application_Slot_Booking__c = request.bookingId,
                    EvaluatedUser__c = currentAccId,
                    EvaluatedBy__c = currentEvaluator.Name,
                    Status__c = 'Pending'
                );
                insertIndexToRequest.put(evaluationsToInsert.size(), request);
                evaluationsToInsert.add(newEvaluation);
            } else if (evaluation.EvaluatedUser__c != currentAccId) {
                results.put((String) request.bookingId, 'You are not authorized to complete this evaluation.');
            } else if (evaluation.Status__c == 'Complete') {
                results.put((String) request.bookingId, 'Already Complete');
            }
        }

        if (!evaluationsToInsert.isEmpty()) {
            insert evaluationsToInsert;

            for (Integer i = 0; i < evaluationsToInsert.size(); i++) {
                BulkCompleteRequest request = insertIndexToRequest.get(i);
                Evaluation__c evaluation = evaluationsToInsert[i];
                evaluationById.put(evaluation.Id, evaluation);
                evaluationByBookingId.put(request.bookingId, evaluation);
                request.evaluationId = evaluation.Id;
            }
        }

        Set<Id> targetEvaluationIds = new Set<Id>();
        for (BulkCompleteRequest request : requests) {
            if (request == null || request.bookingId == null || results.containsKey((String) request.bookingId)) {
                continue;
            }

            Evaluation__c evaluation = request.evaluationId == null
                ? null
                : evaluationById.get(request.evaluationId);

            if (evaluation == null) {
                evaluation = evaluationByBookingId.get(request.bookingId);
            }

            if (evaluation != null && evaluation.Status__c != 'Complete' && evaluation.EvaluatedUser__c == currentAccId) {
                targetEvaluationIds.add(evaluation.Id);
            }
        }

        Map<String, Individual_Criteria_Result__c> existingResultByKey = new Map<String, Individual_Criteria_Result__c>();
        if (!targetEvaluationIds.isEmpty()) {
            for (Individual_Criteria_Result__c result : [
                SELECT Id, Evaluation__c, Scoring_Template__c
                FROM Individual_Criteria_Result__c
                WHERE Evaluation__c IN :targetEvaluationIds
            ]) {
                existingResultByKey.put(criteriaResultKey(result.Evaluation__c, result.Scoring_Template__c), result);
            }
        }

        List<Individual_Criteria_Result__c> criteriaResultsToUpsert = new List<Individual_Criteria_Result__c>();
        Map<Id, Evaluation__c> evaluationsToCompleteById = new Map<Id, Evaluation__c>();

        for (BulkCompleteRequest request : requests) {
            if (request == null || request.bookingId == null || results.containsKey((String) request.bookingId)) {
                continue;
            }

            Evaluation__c evaluation = request.evaluationId == null
                ? null
                : evaluationById.get(request.evaluationId);

            if (evaluation == null) {
                evaluation = evaluationByBookingId.get(request.bookingId);
            }

            if (evaluation == null) {
                results.put((String) request.bookingId, 'Evaluation not found.');
                continue;
            }

            if (request.scores != null) {
                for (ScoreWrapper score : request.scores) {
                    if (score == null || score.scoringTemplateId == null) continue;

                    String key = criteriaResultKey(evaluation.Id, score.scoringTemplateId);
                    Individual_Criteria_Result__c result = existingResultByKey.get(key);
                    if (result == null) {
                        result = new Individual_Criteria_Result__c(
                            Evaluation__c = evaluation.Id,
                            Scoring_Template__c = score.scoringTemplateId
                        );
                        existingResultByKey.put(key, result);
                    }

                    result.Score__c = score.score;
                    result.Comments__c = score.comment;
                    criteriaResultsToUpsert.add(result);
                }
            }

            evaluation.EvaluatorComments__c = request.evaluatorComment;
            evaluation.Status__c = 'Complete';
            evaluationsToCompleteById.put(evaluation.Id, evaluation);
            results.put((String) request.bookingId, 'Success');
        }

        if (!criteriaResultsToUpsert.isEmpty()) {
            upsert criteriaResultsToUpsert;
        }

        if (!evaluationsToCompleteById.isEmpty()) {
            update evaluationsToCompleteById.values();
        }

        return results;
    }

    private static String criteriaResultKey(Id evaluationId, Id scoringTemplateId) {
        return String.valueOf(evaluationId) + '-' + String.valueOf(scoringTemplateId);
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
            String programTeamId = appSlotData.isEmpty() ? null : appSlotData[0].Panel_Master__c;
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
            WHERE EvaluatedUser__r.PersonEmail = :UserInfo.getUserEmail() AND EvaluatedUser__r.RecordType.Name = :RECORD_TYPE
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
                WHERE PersonEmail = :UserInfo.getUserEmail() AND RecordType.Name = :RECORD_TYPE
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

    @AuraEnabled(cacheable=true)
    public static List<SlotMasterWrapper> getSlotMastersForEvaluator() {
        try {
            String currentUserEmail = UserInfo.getUserEmail();
            System.debug('getSlotMastersForEvaluator: currentUserEmail = ' + currentUserEmail);

            List<Account> accList = [SELECT Id FROM Account WHERE PersonEmail = :currentUserEmail AND RecordType.Name = :RECORD_TYPE LIMIT 1];
            System.debug('getSlotMastersForEvaluator: accList size = ' + accList.size());
            if (accList.isEmpty()) {
                System.debug('getSlotMastersForEvaluator: No matching Account found for email, returning empty list');
                return new List<SlotMasterWrapper>();
            }
            Account accountEmp = accList[0];
            System.debug('getSlotMastersForEvaluator: accountEmp.Id = ' + accountEmp.Id);

            Set<Id> panelIds = new Set<Id>();
            List<PanelInterviewer__c> panelInterviewers = [SELECT Id, Account__c, PanelMaster__c FROM PanelInterviewer__c WHERE Account__c = :accountEmp.Id];
            System.debug('getSlotMastersForEvaluator: panelInterviewers size = ' + panelInterviewers.size());
            System.debug('getSlotMastersForEvaluator: panelInterviewers: ' + panelInterviewers);
            for (PanelInterviewer__c ptm : panelInterviewers) {
                if (ptm.PanelMaster__c != null) panelIds.add(ptm.PanelMaster__c);
            }
            System.debug('getSlotMastersForEvaluator: panelIds = ' + panelIds);

            if (panelIds.isEmpty()) {
                System.debug('getSlotMastersForEvaluator: No panelIds found, returning empty list');
                return new List<SlotMasterWrapper>();
            }

            // Find bookings for these panels and group by SlotMaster
            List<ApplicationSlotBooking__c> bookings = [
                SELECT Id, SlotMaster__c, RoundMaster__c, RoundMaster__r.Name
                FROM ApplicationSlotBooking__c
                WHERE Panel_Master__c IN :panelIds
                ORDER BY CreatedDate DESC
            ];
            System.debug('getSlotMastersForEvaluator: bookings size = ' + bookings.size());

            if (bookings.isEmpty()) {
                System.debug('getSlotMastersForEvaluator: No bookings found for panelIds, returning empty list');
                return new List<SlotMasterWrapper>();
            }

            Map<Id, List<ApplicationSlotBooking__c>> slotToBookingIds = new Map<Id, List<ApplicationSlotBooking__c>>();
            Set<Id> slotMasterIds = new Set<Id>();
            Set<Id> bookingIds = new Set<Id>();
            for (ApplicationSlotBooking__c b : bookings) {
                if (b.SlotMaster__c == null) {
                    System.debug('getSlotMastersForEvaluator: Skipping booking with null SlotMaster__c, bookingId = ' + b.Id);
                    continue;
                }
                slotMasterIds.add(b.SlotMaster__c);
                bookingIds.add(b.Id);
                if (!slotToBookingIds.containsKey(b.SlotMaster__c)) {
                    slotToBookingIds.put(b.SlotMaster__c, new List<ApplicationSlotBooking__c>());
                }
                slotToBookingIds.get(b.SlotMaster__c).add(b);
            }
            System.debug('getSlotMastersForEvaluator: slotMasterIds = ' + slotMasterIds);
            System.debug('getSlotMastersForEvaluator: bookingIds = ' + bookingIds);
            System.debug('getSlotMastersForEvaluator: slotToBookingIds = ' + slotToBookingIds);

            if (slotMasterIds.isEmpty()) {
                System.debug('getSlotMastersForEvaluator: No slotMasterIds found after processing bookings, returning empty list');
                return new List<SlotMasterWrapper>();
            }

            // Fetch evaluations for current user for these bookings
            Map<Id, String> bookingToEvalStatus = new Map<Id, String>();
            List<Evaluation__c> evaluations = [SELECT Id, Application_Slot_Booking__c, Status__c
                                    FROM Evaluation__c
                                    WHERE EvaluatedUser__r.PersonEmail = :currentUserEmail 
                                    AND EvaluatedUser__r.RecordType.Name = :RECORD_TYPE
                                    AND Application_Slot_Booking__c IN :bookingIds];
            System.debug('getSlotMastersForEvaluator: evaluations size = ' + evaluations.size());
            for (Evaluation__c ev : evaluations) {
                bookingToEvalStatus.put(ev.Application_Slot_Booking__c, ev.Status__c);
                System.debug('getSlotMastersForEvaluator: bookingId = ' + ev.Application_Slot_Booking__c + ', evalStatus = ' + ev.Status__c);
            }
            System.debug('getSlotMastersForEvaluator: bookingToEvalStatus = ' + bookingToEvalStatus);

            // Fetch slot master details
            List<SlotMaster__c> slots = [
                SELECT Id, Name, SlotDate__c, SlotStartTime__c, SlotEndTime__c, LocationMaster__c,
                    LocationMaster__r.LocationName__c, Status__c, Mode__c, Program_Master__r.Program_Code__c
                FROM SlotMaster__c
                WHERE Id IN :slotMasterIds
                ORDER BY SlotDate__c DESC, Name ASC
            ];
            System.debug('getSlotMastersForEvaluator: slots size = ' + slots.size());

            List<SlotMasterWrapper> result = new List<SlotMasterWrapper>();
            for (SlotMaster__c s : slots) {
                System.debug('getSlotMastersForEvaluator: Processing SlotMaster Id = ' + s.Id + ', Name = ' + s.Name);

                SlotMasterWrapper w = new SlotMasterWrapper();
                w.id = s.Id;
                w.name = s.Name;
                w.slotDate = s.SlotDate__c;
                w.slotStartTime = s.SlotStartTime__c;
                w.slotEndTime = s.SlotEndTime__c;
                w.locationId = s.LocationMaster__c;
                w.locationName = (s.LocationMaster__r != null) ? s.LocationMaster__r.LocationName__c : null;
                w.status = s.Status__c;
                w.mode = s.Mode__c;
                w.programCode = (s.Program_Master__r != null) ? s.Program_Master__r.Program_Code__c : null;

                System.debug('getSlotMastersForEvaluator: Wrapper built - locationName = ' + w.locationName
                    + ', status = ' + w.status + ', mode = ' + w.mode + ', programCode = ' + w.programCode);

                List<ApplicationSlotBooking__c> bookingsList = slotToBookingIds.containsKey(s.Id) ? slotToBookingIds.get(s.Id) : new List<ApplicationSlotBooking__c>();
                System.debug('getSlotMastersForEvaluator: SlotMaster Id = ' + s.Id + ', related bookingIds = ' + bookingsList);

                Boolean allComplete = true;
                Boolean hasAny = false;
                for (ApplicationSlotBooking__c booking : bookingsList) {
                    hasAny = true;
                    String evalStatus = bookingToEvalStatus.containsKey(booking.Id) ? bookingToEvalStatus.get(booking.Id) : null;
                    System.debug('getSlotMastersForEvaluator: bookingId = ' + booking.Id + ', evalStatus = ' + evalStatus);
                    if (evalStatus != 'Complete') {
                        allComplete = false;
                        System.debug('getSlotMastersForEvaluator: bookingId = ' + booking.Id + ' not Complete, breaking loop');
                        break;
                    }
                }
                // If there are no bookings for this slot for this evaluator, treat as not completed
                w.isCompleted = hasAny ? allComplete : false;

                if (hasAny) {
                    w.roundName = (bookingsList[0].RoundMaster__r != null) ? bookingsList[0].RoundMaster__r.Name : null;
                }

                System.debug('getSlotMastersForEvaluator: SlotMaster Id = ' + s.Id + ', hasAny = ' + hasAny
                    + ', allComplete = ' + allComplete + ', isCompleted = ' + w.isCompleted);

                result.add(w);
            }

            System.debug('getSlotMastersForEvaluator: Final result size = ' + result.size());
            return result;
        } catch (Exception e) {
            System.debug('getSlotMastersForEvaluator: Exception occurred - ' + e.getMessage() + ' | ' + e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<SlotBookingWrapper> getSlotBookingsBySlotMaster(Id slotMasterId) {
        try {
            String currentUserEmail = UserInfo.getUserEmail();

            List<Account> accList = [
                SELECT Id FROM Account
                WHERE PersonEmail = :currentUserEmail AND RecordType.Name = :RECORD_TYPE
                LIMIT 1
            ];

            if (accList.isEmpty()) {
                return new List<SlotBookingWrapper>();
            }

            Account accountEmp = accList[0];

            String programCode = '';
            List<SlotMaster__c> slotMasterList = [
                SELECT Id, Program_Master__r.Program_Code__c
                FROM SlotMaster__c
                WHERE Id = :slotMasterId
                LIMIT 1
            ];
            if (!slotMasterList.isEmpty() && slotMasterList[0].Program_Master__r != null) {
                programCode = slotMasterList[0].Program_Master__r.Program_Code__c != null
                              ? slotMasterList[0].Program_Master__r.Program_Code__c
                              : '';
            }

            Set<Id> panelIds = new Set<Id>();
            for (PanelInterviewer__c ptm : [
                SELECT Id, Account__c, PanelMaster__c FROM PanelInterviewer__c
                WHERE Account__c = :accountEmp.Id
            ]) {
                if (ptm.PanelMaster__c != null) panelIds.add(ptm.PanelMaster__c);
            }

            List<ApplicationSlotBooking__c> latestBooking = [
                SELECT Id,
                       Name,
                       Applicant_Name__c,
                       Program_Name__c,
                       Application__c,
                       Application__r.Name,
                       Slot_Date__c,
                       Slot_Start_Time__c,
                       Slot_End_Time__c,
                       Mode__c,
                       Panel_Master__c,
                       RoundMaster__c,
                       RoundMaster__r.Name,
                       SlotMaster__r.LocationMaster__c,
                       SlotMaster__r.LocationMaster__r.LocationName__c
                FROM ApplicationSlotBooking__c
                WHERE SlotMaster__c = :slotMasterId
                AND Panel_Master__c IN :panelIds
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (latestBooking.isEmpty()) {
                return new List<SlotBookingWrapper>();
            }

            Id roundId = latestBooking[0].RoundMaster__c;

            if (roundId == null) {
                throw new AuraHandledException('RoundMaster__c is not available for a booking. Cannot proceed.');
            }

            List<ApplicationSlotBooking__c> bookings = [
                SELECT Id,
                       Name,
                       Applicant_Name__c,
                       Program_Name__c,
                       Application__c,
                       Application__r.Name,
                       Application__r.Batch_Specialisation__r.Specialisation_Name__r.Name,
                       Slot_Date__c,
                       Slot_Start_Time__c,
                       Slot_End_Time__c,
                       Mode__c,
                       Panel_Master__c,
                       RoundMaster__c,
                       RoundMaster__r.Name,
                       SlotMaster__r.LocationMaster__c,
                       SlotMaster__r.LocationMaster__r.LocationName__c
                FROM ApplicationSlotBooking__c
                WHERE SlotMaster__c = :slotMasterId
                AND Panel_Master__c IN :panelIds
                AND RoundMaster__c = :roundId
                ORDER BY Applicant_Name__c ASC
            ];

            if (bookings.isEmpty()) {
                return new List<SlotBookingWrapper>();
            }

            Set<Id> bookingIds = new Map<Id, ApplicationSlotBooking__c>(bookings).keySet();
            Map<Id, String> bookingToEvalStatus = new Map<Id, String>();
            for (Evaluation__c ev : [
                SELECT Id, Application_Slot_Booking__c, Status__c
                FROM Evaluation__c
                WHERE EvaluatedUser__r.PersonEmail = :currentUserEmail AND EvaluatedUser__r.RecordType.Name = :RECORD_TYPE
                  AND Application_Slot_Booking__c IN :bookingIds
            ]) {
                bookingToEvalStatus.put(ev.Application_Slot_Booking__c, ev.Status__c);
            }

            List<SlotBookingWrapper> result = new List<SlotBookingWrapper>();
            for (ApplicationSlotBooking__c b : bookings) {
                SlotBookingWrapper w  = new SlotBookingWrapper();
                w.id              = b.Id;
                w.name            = b.Name;
                w.applicantName   = b.Applicant_Name__c;
                w.programName     = b.Program_Name__c;
                w.programCode     = programCode;
                w.applicationId   = b.Application__c;
                w.slotDate        = b.Slot_Date__c;
                w.slotStartTime   = b.Slot_Start_Time__c;
                w.slotEndTime     = b.Slot_End_Time__c;
                w.mode            = b.Mode__c;
                w.panelMasterId   = b.Panel_Master__c;
                w.roundMasterId   = b.RoundMaster__c;
                w.roundMasterName = b.RoundMaster__r != null ? b.RoundMaster__r.Name : null;
                w.evalStatus      = bookingToEvalStatus.containsKey(b.Id)
                                    ? bookingToEvalStatus.get(b.Id)
                                    : 'Not Started';
                w.applicationName = b.Application__r != null ? b.Application__r.Name : null;
                w.specialisation = (b.Application__r != null && b.Application__r.Batch_Specialisation__r != null
                                     && b.Application__r.Batch_Specialisation__r.Specialisation_Name__r != null)
                                    ? b.Application__r.Batch_Specialisation__r.Specialisation_Name__r.Name : null;
                w.locationId      = b.SlotMaster__r != null ? b.SlotMaster__r.LocationMaster__c : null;
                w.locationName    = (b.SlotMaster__r != null && b.SlotMaster__r.LocationMaster__r != null)
                                    ? b.SlotMaster__r.LocationMaster__r.LocationName__c : null;
                result.add(w);
            }
            return result;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static ScoringConfigWrapper getScoringConfig(String programCode) {
        ScoringConfigWrapper cfg = new ScoringConfigWrapper();
        cfg.showCriteriaComment = false;

        List<ApplicationProgramBasedConfig__mdt> records = [
            SELECT Intent__c, Type__c, ProgramCode__c, ConfigValue__c, Active__c
            FROM ApplicationProgramBasedConfig__mdt
            WHERE Intent__c      = 'CommentForEachCriteria'
              AND ProgramCode__c = :programCode
              AND Active__c      = true
            LIMIT 1
        ];

        if (!records.isEmpty()) {
            ApplicationProgramBasedConfig__mdt rec = records[0];
            if (rec.Type__c == 'Boolean') {
                cfg.showCriteriaComment = (Boolean) (rec.ConfigValue__c != null &&
                                           rec.ConfigValue__c.trim().equalsIgnoreCase('true'));
            }
        }
        return cfg;
    }

    @AuraEnabled
    public static void saveEvaluatorComment(Id evaluationId, String comment) {
        try {
            if (evaluationId == null) return;

            List<Evaluation__c> evalList = [
                SELECT Id, Status__c, EvaluatedUser__c, EvaluatorComments__c
                FROM Evaluation__c
                WHERE Id = :evaluationId
                LIMIT 1
            ];

            if (evalList.isEmpty()) {
                throw new AuraHandledException('Evaluation not found.');
            }
            if (evalList[0].Status__c == 'Complete') {
                throw new AuraHandledException('Evaluation is already complete and cannot be edited.');
            }

            evalList[0].EvaluatorComments__c = comment;
            update evalList;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static String getEvaluatorComment(Id slotId) {
        try {
            Id currentAccId = getCurrentEvaluatorAccountId();
            if (currentAccId == null) return '';

            List<Evaluation__c> evalList = [
                SELECT Id, EvaluatorComments__c
                FROM Evaluation__c
                WHERE Application_Slot_Booking__c = :slotId
                  AND EvaluatedUser__c = :currentAccId
                LIMIT 1
            ];

            if (evalList.isEmpty()) return '';
            return evalList[0].EvaluatorComments__c != null
                   ? evalList[0].EvaluatorComments__c
                   : '';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String,List<SObject>> getEvaluationCriteria(Id applicationSlotBookingId){
        List<ScoringTemplate__c> criteriaList = new List<ScoringTemplate__c>();
        List<ApplicationSlotBooking__c> appSlotBookingList = [SELECT RoundMaster__c,Panel_Master__r.ProgramTeam__c 
        FROM ApplicationSlotBooking__c WHERE RoundMaster__c<>NULL AND Id=:applicationSlotBookingId LIMIT 1];
        if(!appSlotBookingList.isEmpty()){
            
            List<Evaluation__c> listEvaluation = [SELECT Id FROM Evaluation__c 
            WHERE EvaluatedUser__r.PersonEmail = :UserInfo.getUserEmail() AND EvaluatedUser__r.RecordType.Name = :RECORD_TYPE
            AND Application_Slot_Booking__c = :applicationSlotBookingId LIMIT 1];
            
            criteriaList = [SELECT Id,CriteriaName__c,Name,Maximum_Score__c,CriteriaDescription__c
                FROM ScoringTemplate__c 
                WHERE Round__c = :appSlotBookingList[0].RoundMaster__c];

            if (criteriaList.isEmpty()) {
                throw new AuraHandledException('No scoring templates are configured for this slot\'s round.');
            }
            
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
    }

    @AuraEnabled(cacheable=true)
    public static Boolean getStaticPdfConfig(String programCode) {
        try {
            List<ApplicationProgramBasedConfig__mdt> records = [
                SELECT Intent__c, Type__c, ProgramCode__c, ConfigValue__c, Active__c
                FROM ApplicationProgramBasedConfig__mdt
                WHERE Intent__c      = 'StaticApplicationPdf'
                  AND ProgramCode__c = :programCode
                  AND Active__c      = true
                LIMIT 1
            ];
            if (!records.isEmpty() && records[0].Type__c == 'Boolean') {
                return records[0].ConfigValue__c != null &&
                       records[0].ConfigValue__c.trim().equalsIgnoreCase('true');
            }
            return false;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Boolean getShowSpecialisationConfig(String programCode) {
        try {
            List<ApplicationProgramBasedConfig__mdt> records = [
                SELECT Intent__c, Type__c, ProgramCode__c, ConfigValue__c, Active__c
                FROM ApplicationProgramBasedConfig__mdt
                WHERE Intent__c      = 'AdmissionDecisionShowSpecialization'
                  AND ProgramCode__c = :programCode
                  AND Active__c      = true
                LIMIT 1
            ];
            if (!records.isEmpty() && records[0].Type__c == 'Boolean') {
                return records[0].ConfigValue__c != null &&
                       records[0].ConfigValue__c.trim().equalsIgnoreCase('true');
            }
            return false;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static String getMerittoExtractFileUrl(Id applicationId) {
        try {
            List<Document_Details__c> docList = [
                SELECT Id
                FROM Document_Details__c
                WHERE Application_No__c = :applicationId
                AND Document_Code__c  = 'MerittoExtract'
                LIMIT 1
            ];
            if (docList.isEmpty()) return '';

            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :docList[0].Id
                LIMIT 1
            ];
            if (links.isEmpty()) return '';

            List<ContentVersion> versions = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId = :links[0].ContentDocumentId
                AND IsLatest          = true
                LIMIT 1
            ];
            if (versions.isEmpty()) return '';

            List<ContentDistribution> existingDist = [
                SELECT Id, DistributionPublicUrl,
                    PreferencesAllowOriginalDownload,
                    PreferencesAllowPDFDownload
                FROM ContentDistribution
                WHERE ContentVersionId = :versions[0].Id
                LIMIT 1
            ];

            ContentDistribution cd;
            if (!existingDist.isEmpty()) {
                cd = existingDist[0];
                if (cd.PreferencesAllowOriginalDownload || cd.PreferencesAllowPDFDownload) {
                    cd.PreferencesAllowOriginalDownload = false;
                    cd.PreferencesAllowPDFDownload      = false;
                    update cd;
                }
            } else {
                cd = new ContentDistribution();
                cd.Name                             = 'MerittoExtract_' + versions[0].Id;
                cd.ContentVersionId                  = versions[0].Id;
                cd.PreferencesAllowViewInBrowser      = true;
                cd.PreferencesAllowOriginalDownload   = false;
                cd.PreferencesAllowPDFDownload         = false;
                cd.PreferencesNotifyOnVisit           = false;
                cd.PreferencesPasswordRequired        = false;
                insert cd;

                cd = [
                    SELECT Id, DistributionPublicUrl
                    FROM ContentDistribution
                    WHERE Id = :cd.Id
                    LIMIT 1
                ];
            }

            return cd.DistributionPublicUrl != null ? cd.DistributionPublicUrl : '';

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Id getCurrentEvaluatorAccountId() {
        List<Account> accList = [
            SELECT Id
            FROM Account
            WHERE PersonEmail = :UserInfo.getUserEmail()
            AND RecordType.Name = :RECORD_TYPE
            LIMIT 1
        ];
        return accList.isEmpty() ? null : accList[0].Id;
    }

    //Wrapper Classes
    public class ScoreWrapper {
        @AuraEnabled public Id scoringTemplateId;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String comment;
    }

    public class BulkCompleteRequest {
        @AuraEnabled public Id bookingId;
        @AuraEnabled public Id evaluationId;
        @AuraEnabled public String evaluatorComment;
        @AuraEnabled public List<ScoreWrapper> scores;
    }

    public class SlotBookingWrapper {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  applicantName;
        @AuraEnabled public String  programName;
        @AuraEnabled public String  programCode;
        @AuraEnabled public Id      applicationId;
        @AuraEnabled public Date    slotDate;
        @AuraEnabled public Time    slotStartTime;
        @AuraEnabled public Time    slotEndTime;
        @AuraEnabled public String  mode;
        @AuraEnabled public Id      panelMasterId;
        @AuraEnabled public Id      roundMasterId;
        @AuraEnabled public String  roundMasterName;
        @AuraEnabled public String  evalStatus;
        @AuraEnabled public Id      locationId;
        @AuraEnabled public String  locationName;
        @AuraEnabled public String  applicationName;
        @AuraEnabled public String  specialisation;
    }

    public class SlotMasterWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Date slotDate;
        @AuraEnabled public Time slotStartTime;
        @AuraEnabled public Time slotEndTime;
        @AuraEnabled public Id locationId;
        @AuraEnabled public String locationName;
        @AuraEnabled public String status;
        @AuraEnabled public String mode;
        @AuraEnabled public Boolean isCompleted;
        @AuraEnabled public String programCode;
        @AuraEnabled public String roundName;
    }

    public class ScoringConfigWrapper {
        @AuraEnabled public Boolean showCriteriaComment;
        @AuraEnabled public String  evaluatorComment;
    }
}
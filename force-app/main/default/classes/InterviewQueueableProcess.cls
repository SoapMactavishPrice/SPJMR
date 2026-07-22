public with sharing class InterviewQueueableProcess implements Queueable {
    
    /* =========================
    ====== INNER DTOs =======
        ========================= */
        
    public class EvalRowDTO {
        public String applicationNumber;
        public String evaluator;
        public Map<String, Integer> scores;
        public Map<String, String> comments;
        
    }
    
    public class ParseResult {
    public Map<String, List<EvalRowDTO>> appToEvalRows;
    public String round;
    public String programCode;
    public Set<String> csvCriteria;   // ✅ ADD THIS
}

    
    /* =========================
    ====== STATE FIELDS =====
        ========================= */
        
    private String phase;
    private String docId;
    private String programCode;
    private String round;
    private Id logId;
    private Map<String, List<EvalRowDTO>> appToEvalRows;
    private Map<String, Id> appToSlotId;
    private Map<String, List<Id>> appToEvalIds;
    
    /* =========================
    ===== CONSTRUCTORS ======
        ========================= */
        
    public InterviewQueueableProcess(String docId, String programCode, Id logId) {
        this.phase = 'PARSE_CSV';
        this.docId = docId;
        this.programCode = programCode;
        this.logId = logId;
    }
    
    
    public InterviewQueueableProcess(
        Map<String, List<EvalRowDTO>> appToEvalRows,
    String round,
    String programCode,
    Id logId
    ) {
        this.phase = 'CREATE_SLOTS';
        this.appToEvalRows = appToEvalRows;
        this.round = round;
        this.programCode = programCode;
        this.logId = logId;
    }
    
    public InterviewQueueableProcess(
        Map<String, List<EvalRowDTO>> appToEvalRows,
    Map<String, Id> appToSlotId,
    String round,
    String programCode,
    Id logId
    ) {
        this.phase = 'CREATE_EVALUATIONS';
        this.appToEvalRows = appToEvalRows;
        this.appToSlotId = appToSlotId;
        this.round = round;
        this.programCode = programCode;
        this.logId = logId;
    }
    
    public InterviewQueueableProcess(
        Map<String, List<EvalRowDTO>> appToEvalRows,
    Map<String, List<Id>> appToEvalIds,
    String round,
    String programCode,
    Id logId
    ) {
        this.phase = 'CREATE_CRITERIA';
        this.appToEvalRows = appToEvalRows;
        this.appToEvalIds = appToEvalIds;
        this.round = round;
        this.programCode = programCode;
        this.logId = logId;
    }
    
    public InterviewQueueableProcess(Map<String, List<Id>> appToEvalIds,Id logId) {
        this.phase = 'CREATE_ROUNDRESULT';
        this.appToEvalIds = appToEvalIds;
        this.logId = logId;
    }
    
    /* =========================
    ====== EXECUTE ==========
        ========================= */
        
    
    private Map<Boolean,String> validateCriteriaAndScores(
        Map<String, List<EvalRowDTO>> appToEvalRows,
    String round,
    String programCode, Set<String> csvCriteria 
    ) {
        Boolean IsValid = true;
        Map<String, ScoringTemplate__c> templateByName = new Map<String, ScoringTemplate__c>();
        Map<Boolean,String> resultMap = new Map<Boolean,String>();
        for (ScoringTemplate__c st : [
        SELECT Id, CriteriaName__c, Maximum_Score__c
        FROM ScoringTemplate__c
        WHERE Round__r.RoundNumber__c = :round
        AND Round__r.Program__r.Program_Code__c = :programCode
    ]) {
            templateByName.put(
                st.CriteriaName__c.trim().toUpperCase(),
            st
                );
        }
        
        if (templateByName.isEmpty()) {
            
            String errorMessage = 'No scoring templates configured for Round ' + round;
            resultMap.put(false,errorMessage);
            return resultMap;
        }
        
        
        
        Set<String> templateCriteria = templateByName.keySet();
        
        // 3. Header mismatch validation
        if(!csvCriteria.equals(templateCriteria)) {
            Set<String> missing = new Set<String>(templateCriteria);
            missing.removeAll(csvCriteria);
            
            Set<String> extra = new Set<String>(csvCriteria);
            extra.removeAll(templateCriteria);
            
            String msg = 'Criteria mismatch detected.';
            
            if (!missing.isEmpty()) {
                msg += ' Missing criteria: ' + String.join(new List<String>(missing), ', ');
            }
            if (!extra.isEmpty()) {
                msg += ' Extra criteria: ' + String.join(new List<String>(extra), ', ');
            }
            
            resultMap.put(false,msg);
            return resultMap;
        }
        
        for (String appNum : appToEvalRows.keySet()) {
            for (EvalRowDTO row : appToEvalRows.get(appNum)) {
                for (String crit : row.scores.keySet()) {
                    
                    String normalized = crit.trim().toUpperCase();
                    Integer score = row.scores.get(crit);
                    ScoringTemplate__c st = templateByName.get(normalized);
                    
                    if (score != null && score > st.Maximum_Score__c)
                    {
                        resultMap.put(false,'Score exceeds maximum allowed.\n Application: ' + appNum + ',\n Criteria: ' + st.CriteriaName__c
                            + ',\n Max:'+ st.Maximum_Score__c +',\n Provided: ' + score);
                        
                        return resultMap;
                    }
                }
            }
        }
        resultMap.put(true,'Passed Validations');
        return resultMap;
    }
    
    
    private void updateLog(String status, String message) {
        update new Interview_Excel_Log__c(
            Id = logId,
        Status__c = status,
        Error_Message__c = message
            );
    }
    
    
    public void execute(QueueableContext context) {
        
        System.debug('===== QUEUEABLE START =====');
        System.debug('PHASE=' + phase + ' | ROUND=' + round + ' | PROGRAM=' + programCode);
        
        try {
            
            switch on phase {
                
                when 'PARSE_CSV' {
                    
                    ParseResult parsed = parseCsv(docId);
                    if(parsed==null){
                        return;
                    }
                    Map<Boolean,String> validationMap = validateCriteriaAndScores(
    parsed.appToEvalRows,
    parsed.round,
    parsed.programCode,
    parsed.csvCriteria   // ✅ PASS HEADER CRITERIA
);

                    
                    if(validationMap.containsKey(true)) {
                        
                        updateLog('Validation Passed', null);
                        
                        System.enqueueJob(
                            new InterviewQueueableProcess(
                            parsed.appToEvalRows,
                        parsed.round,
                        parsed.programCode,
                        logId
                            )
                            );
                        
                    } else {
                        
                        updateLog('Error', validationMap.get(false));
                    }
                }
                
                when 'CREATE_SLOTS' {
                    
                    Map<String, Id> slotMap = upsertSlots(appToEvalRows);
                    
                    System.enqueueJob(
                        new InterviewQueueableProcess(
                        appToEvalRows,
                    slotMap,
                    round,
                    programCode,
                    logId
                        )
                        );
                }
                
                when 'CREATE_EVALUATIONS' {
                    
                    Map<String, List<Id>> evalIds =
                        upsertEvaluations(appToEvalRows, appToSlotId);
                    
                    System.enqueueJob(
                        new InterviewQueueableProcess(
                        appToEvalRows,
                    evalIds,
                    round,
                    programCode,
                    logId
                        )
                        );
                }
                
                when 'CREATE_CRITERIA' {
                    
                    Integer CHUNK_SIZE = 1500;
                    
                    List<Individual_Criteria_Result__c> allCriteria =
                        buildAllCriteria(appToEvalRows, appToEvalIds);
                    
                    System.enqueueJob(
                        new CriteriaChunkQueueable(
                        allCriteria,
                    0,
                    CHUNK_SIZE,
                    appToEvalIds,
                    logId
                        )
                        );
                }
                
                when 'CREATE_ROUNDRESULT' {
                    
                    upsertRoundResults();
                    updateLog('Success', null);
                }
            }
            
        } catch (Exception ex) {
            
            updateLog('Error', ex.getMessage());
        }
    }
    
    
    
    /* =========================
    ===== CSV PARSING =======
        ========================= */
        
    private List<Individual_Criteria_Result__c> buildAllCriteria(
        Map<String, List<EvalRowDTO>> appToEvalRows,
    Map<String, List<Id>> appToEvalIds
    ) {
        // 1. Collect all Evaluation Ids
        Set<Id> allEvalIds = flatten(appToEvalIds.values());
        
        // 2. Fetch existing criteria keyed by EvaluationId|ScoringTemplateId
        Map<String, Id> existingCriteria =
            fetchExistingCriteriaMap(allEvalIds);
        
        // 3. Fetch scoring templates for this round + program
        Map<String, Id> critMap = new Map<String, Id>();
        for (ScoringTemplate__c st : [
        SELECT Id, CriteriaName__c
        FROM ScoringTemplate__c
        WHERE Round__r.RoundNumber__c = :round
        AND Round__r.Program__r.Program_Code__c = :programCode
    ]) {
            critMap.put(st.CriteriaName__c.trim().toUpperCase(), st.Id);
            
        }
        
        // 4. Build criteria rows (with Id reattachment)
        List<Individual_Criteria_Result__c> allCriteria =
            new List<Individual_Criteria_Result__c>();
        
        for (String appNum : appToEvalRows.keySet()) {
            
            List<EvalRowDTO> rows = appToEvalRows.get(appNum);
            // List<Id> evalIds = appToEvalIds.get(appNum);
            List<Id> evalIds = appToEvalIds.get(appNum);

if (evalIds == null || evalIds.isEmpty()) {
    continue; // nothing to process
}

            
            for (Integer i = 0; i < rows.size() && i < evalIds.size(); i++) {
                for (String crit : rows[i].scores.keySet()) {
                    
                    if (!critMap.containsKey(crit)) continue;
                    
                    Id evalId = evalIds[i];
                    Id templateId = critMap.get(crit);
                    String key = evalId + '|' + templateId;
                    
                    Individual_Criteria_Result__c icr =
                        new Individual_Criteria_Result__c(
                        Evaluation__c = evalId,
                    Scoring_Template__c = templateId,
                    Score__c = rows[i].scores.get(crit),
                    Comments__c = rows[i].comments.get(crit)
                        );
                    
                    if (existingCriteria.containsKey(key)) {
                        icr.Id = existingCriteria.get(key);
                    }
                    
                    allCriteria.add(icr);
                    
                }
            }
        }
        
        return allCriteria;
    }
    
    
    
    private Map<String, Id> fetchExistingCriteriaMap(
        Set<Id> evalIds
    ) {
        Map<String, Id> result = new Map<String, Id>();
        
        for (Individual_Criteria_Result__c icr : [
        SELECT Id, Evaluation__c, Scoring_Template__c
        FROM Individual_Criteria_Result__c
        WHERE Evaluation__c IN :evalIds
    ]) {
            String key = icr.Evaluation__c + '|' + icr.Scoring_Template__c;
            result.put(key, icr.Id);
        }
        
        return result;
    }
    
    
    private ParseResult parseCsv(String docId) {

    ContentVersion cv = [
        SELECT VersionData, FileExtension
        FROM ContentVersion
        WHERE ContentDocumentId = :docId
        AND IsLatest = true
        LIMIT 1
    ];

    if (cv.FileExtension == null || cv.FileExtension.toLowerCase() != 'csv') {
        updateLog('Error', 'Only CSV files are supported.');
        return null;
    }

    Blob data = cv.VersionData;

    DataWeave.Script script =
        new DataWeaveScriptResource.csvToJSON_InterviewScore();

    DataWeave.Result dw =
        script.execute(new Map<String, Object>{
            'data' => data
        });

    List<Object> rows =
        (List<Object>) JSON.deserializeUntyped(dw.getValueAsString());

    Map<String, List<EvalRowDTO>> appRows = new Map<String, List<EvalRowDTO>>();
    String localRound;
    String localProgram;
    List<String> headers;
    Set<String> headerCriteria = new Set<String>();   // ✅ NEW

    for (Object rowObj : rows) {

        Map<String, Object> row = (Map<String, Object>) rowObj;

        if (headers == null) {
            headers = new List<String>(row.keySet());

            // ✅ EXTRACT CRITERIA FROM HEADERS (NOT DATA)
            for (Integer h = 0; h < headers.size(); h++) {

    String headerName = headers[h].trim().toUpperCase();

    if(headerName.contains('(MAX')) {
        headerName = headerName.substringBefore('(MAX').trim();
    }

    if (
        headerName != 'APPLICATION NUMBER' &&
        headerName != 'APPLICANT NAME' &&
        headerName != 'PROGRAMME' &&
        headerName != 'ROUND' &&
        headerName != 'EVALUATED BY' &&
        !headerName.endsWith(' COMMENT')
    ) {
        headerCriteria.add(headerName);
    }
}
        }

        EvalRowDTO dto = new EvalRowDTO();
        dto.scores = new Map<String, Integer>();
        dto.comments = new Map<String, String>();

        Integer i = 0;

        while (i < headers.size()) {

            String key = headers[i];
            if (String.isBlank(key)) {
                i++;
                continue;
            }

            String normalized = key.trim().toUpperCase();
            Object rawVal = row.get(key);
            String value = rawVal == null ? null : String.valueOf(rawVal).trim();

            if (normalized == 'APPLICATION NUMBER') {
                dto.applicationNumber = value;
            }
            else if (normalized == 'APPLICANT NAME') {
                // ignore
            }
            else if (normalized == 'PROGRAMME') {
                localProgram = value;
            }
            else if (normalized == 'ROUND') {
                localRound = value;
            }
            else if (normalized == 'EVALUATED BY') {
                dto.evaluator = value != null ? value.toLowerCase() : null;
            }
            else {

    String headerName = normalized;

    if(headerName.contains('(MAX')) {
    headerName = headerName.substringBefore('(MAX').trim();
}

    // If this is a comment column
    if (headerName.endsWith(' COMMENT')) {

        String criteriaName =
            headerName.replace(' COMMENT', '').trim();

        dto.comments.put(criteriaName, value);
    }
    else {

        // This is a score column
       Integer score = null;

if (!String.isBlank(value)) {

    if (!value.isNumeric()) {
        updateLog(
            'Error',
            'Invalid score detected. Application: ' + dto.applicationNumber +
            ', Criteria: ' + headerName +
            ', Value: "' + value + '" is not a number.'
        );
        return null;
    }

    score = Integer.valueOf(value);
}

        dto.scores.put(headerName, score);
    }
}


            i++;
        }

        if (dto.applicationNumber == null || dto.scores.isEmpty()) {
            continue;
        }

        if (!appRows.containsKey(dto.applicationNumber)) {
            appRows.put(dto.applicationNumber, new List<EvalRowDTO>());
        }

        appRows.get(dto.applicationNumber).add(dto);
    }

    if (String.isBlank(localRound)) {
        updateLog('Error', 'ROUND column missing in CSV');
        return null;
    }

    if (String.isBlank(localProgram)) {
        updateLog('Error', 'PROGRAMME column missing in CSV');
        return null;
    }

    ParseResult result = new ParseResult();
    result.appToEvalRows = appRows;
    result.round = localRound;
    result.programCode = localProgram;
    result.csvCriteria = headerCriteria;   // ✅ RETURN HEADER CRITERIA

    return result;
}

    
    
    /* =========================
    ===== SLOT UPSERT =======
        ========================= */
        
    private Map<String, Id> upsertSlots(Map<String, List<EvalRowDTO>> appToEvalRows) {
        
        // 1. Fetch Round
        RoundMaster__c roundRec = [
        SELECT Id
        FROM RoundMaster__c
        WHERE Program__r.Program_Code__c = :programCode
        AND RoundNumber__c = :round
        LIMIT 1
    ];
        
        // 2. Fetch Applications
        Map<String, Id> appNumToId = new Map<String, Id>();
        for (Application__c a : [
        SELECT Id, Name
        FROM Application__c
        WHERE Name IN :appToEvalRows.keySet()
    ]) {
            appNumToId.put(a.Name, a.Id);
        }
        
        // 3. Fetch EXISTING slots for this round
        Map<String, ApplicationSlotBooking__c> existingSlots = new Map<String, ApplicationSlotBooking__c>();
        for (ApplicationSlotBooking__c s : [
        SELECT Id, Application__r.Name
        FROM ApplicationSlotBooking__c
        WHERE RoundMaster__c = :roundRec.Id
        AND Application__r.Name IN :appToEvalRows.keySet()
    ]) {
            existingSlots.put(s.Application__r.Name, s);
        }
        
        Map<String, Id> appToSlotId = new Map<String, Id>();
        List<ApplicationSlotBooking__c> toInsert = new List<ApplicationSlotBooking__c>();
        
        // 4. Decide insert vs reuse
        for (String appNum : appToEvalRows.keySet()) {
            
            if (!appNumToId.containsKey(appNum)) {
                updateLog(
                    'Error',
                'Application not found for Application Number: ' + appNum
                    );
                return new Map<String, Id>();
            }
            
            if (existingSlots.containsKey(appNum)) {
                // ✅ Reuse existing slot
                appToSlotId.put(appNum, existingSlots.get(appNum).Id);
            } else {
                
                toInsert.add(new ApplicationSlotBooking__c(
                    Application__c = appNumToId.get(appNum),
                RoundMaster__c = roundRec.Id
                    ));
            }
        }
        
        // 5. Insert only missing slots
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        
        // 6. Add newly inserted slots to map
        if (!toInsert.isEmpty()) {
            for (ApplicationSlotBooking__c s : [
            SELECT Id, Application__r.Name
            FROM ApplicationSlotBooking__c
            WHERE RoundMaster__c = :roundRec.Id
            AND Application__r.Name IN :appToEvalRows.keySet()
        ]) {
                appToSlotId.put(s.Application__r.Name, s.Id);
            }
        }
        
        return appToSlotId;
    }
    
    
    /* =========================
    ===== EVALUATION UPSERT =
        ========================= */
        
    private Map<String, List<Id>> upsertEvaluations(
        Map<String, List<EvalRowDTO>> appToEvalRows,
    Map<String, Id> appToSlotId
    ) {
        
        Map<String, Evaluation__c> existing = new Map<String, Evaluation__c>();
        for (Evaluation__c e : [
            SELECT Id, Application_Slot_Booking__c, EvaluatedBy__c
            FROM Evaluation__c
            WHERE Application_Slot_Booking__c IN :appToSlotId.values()
        ]) {
            existing.put(
                e.Application_Slot_Booking__c + '|' + e.EvaluatedBy__c,
            e
                );
        }
        
        Map<String, List<Id>> appToEvalIds = new Map<String, List<Id>>();
        List<Evaluation__c> toInsert = new List<Evaluation__c>();
        
        for (String appNum : appToEvalRows.keySet()) {
            
            appToEvalIds.put(appNum, new List<Id>());
            Id slotId = appToSlotId.get(appNum);
            
            for (EvalRowDTO dto : appToEvalRows.get(appNum)) {
                
                if (String.isBlank(dto.evaluator)) continue;
                
                String key = slotId + '|' + dto.evaluator;
                
                if (existing.containsKey(key)) {
                    appToEvalIds.get(appNum).add(existing.get(key).Id);
                } else {
                    toInsert.add(new Evaluation__c(
                        Application_Slot_Booking__c = slotId,
                    EvaluatedBy__c = dto.evaluator,
                    Status__c = 'Complete'
                        ));
                }
            }
        }
        
        if (!toInsert.isEmpty()) insert toInsert;
        
        for (Evaluation__c e : toInsert) {
            existing.put(
                e.Application_Slot_Booking__c + '|' + e.EvaluatedBy__c,
            e
                );
        }
        
        for (String appNum : appToEvalRows.keySet()) {
            for (EvalRowDTO dto : appToEvalRows.get(appNum)) {
                if (String.isBlank(dto.evaluator)) continue;
                appToEvalIds.get(appNum).add(
                    existing.get(appToSlotId.get(appNum) + '|' + dto.evaluator).Id
                    );
            }
        }
        
        return appToEvalIds;
    }
    
    /* =========================
    ===== CRITERIA UPSERT ===
        ========================= */
        
    private void upsertCriteria(
        Map<String, List<EvalRowDTO>> appToEvalRows,
    Map<String, List<Id>> appToEvalIds
    ) {
        
        Map<String, Id> critMap = new Map<String, Id>();
        for (ScoringTemplate__c st : [
            SELECT Id, CriteriaName__c
            FROM ScoringTemplate__c
            WHERE Round__r.RoundNumber__c = :round
            AND Round__r.Program__r.Program_Code__c = :programCode
        ]) {
            critMap.put(st.CriteriaName__c.trim().toUpperCase(), st.Id);
            
        }
        
        Set<Id> evalIds = flatten(appToEvalIds.values());
        
        Map<String, Individual_Criteria_Result__c> existing = new Map<String, Individual_Criteria_Result__c>();
        for (Individual_Criteria_Result__c r : [
            SELECT Id, Evaluation__c, Scoring_Template__c
            FROM Individual_Criteria_Result__c
            WHERE Evaluation__c IN :evalIds
        ]) {
            existing.put(r.Evaluation__c + '|' + r.Scoring_Template__c, r);
        }
        
        List<Individual_Criteria_Result__c> toUpsert = new List<Individual_Criteria_Result__c>();
        
        for (String appNum : appToEvalRows.keySet()) {
            List<EvalRowDTO> rows = appToEvalRows.get(appNum);
            List<Id> eIds = appToEvalIds.get(appNum);
            
            for (Integer i = 0; i < rows.size(); i++) {
                for (String crit : rows[i].scores.keySet()) {
                    
                    if (!critMap.containsKey(crit)) continue;
                    
                    String key = eIds[i] + '|' + critMap.get(crit);
                    
                    if (existing.containsKey(key)) {
                        existing.get(key).Score__c = rows[i].scores.get(crit);
                        existing.get(key).Comments__c = rows[i].comments.get(crit);
                        
                        toUpsert.add(existing.get(key));
                    } else {
                        toUpsert.add(new Individual_Criteria_Result__c(
                            Evaluation__c = eIds[i],
                        Scoring_Template__c = critMap.get(crit),
                        Score__c = rows[i].scores.get(crit),
                        Comments__c = rows[i].comments.get(crit)
                            ));
                    }
                }
            }
        }
        
        if (!toUpsert.isEmpty()) upsert toUpsert;
    }
    
    /* =========================
    ===== ROUND RESULT ======
        ========================= */
        
    private void upsertRoundResults() {
        
        // 1. Collect Evaluation Ids
        Set<Id> evalIds = flatten(appToEvalIds.values());
        if (evalIds.isEmpty()) return;
        
        // 2. Query evaluations
        // List<Evaluation__c> evals = [
        //     SELECT Id, Application_Slot_Booking__c, AverageScore__c
        //     FROM Evaluation__c
        //     WHERE Id IN :evalIds
        //     AND Application_Slot_Booking__c != null
        // ];
        
        
        
        // 3. Aggregate scores per slot
        Map<Id, Decimal> slotTotal = new Map<Id, Decimal>();
        Map<Id, Integer> slotCount = new Map<Id, Integer>();
        
        for (Evaluation__c e : [
        SELECT Id, Application_Slot_Booking__c, AverageScore__c
        FROM Evaluation__c
        WHERE Id IN :evalIds
        AND Application_Slot_Booking__c != null
    ]) {
            if (e.AverageScore__c == null) continue;
            
            Id slotId = e.Application_Slot_Booking__c;
            
            slotTotal.put(
                slotId,
            (slotTotal.containsKey(slotId) ? slotTotal.get(slotId) : 0)
                + e.AverageScore__c
                );
            
            slotCount.put(
                slotId,
            (slotCount.containsKey(slotId) ? slotCount.get(slotId) : 0) + 1
                );
        }
        
        if (slotTotal.isEmpty()) return;
        
        // 4. Query EXISTING round results and key them by SLOT ID
        Map<Id, Round_Result__c> slotIdToRoundResult = new Map<Id, Round_Result__c>();
        for (Round_Result__c rr : [
        SELECT Id, ApplicationSlotBooking__c
        FROM Round_Result__c
        WHERE ApplicationSlotBooking__c IN :slotTotal.keySet()
    ]) {
            slotIdToRoundResult.put(rr.ApplicationSlotBooking__c, rr);
        }
        
        // 5. Insert or update (exactly one per slot)
        List<Round_Result__c> toUpsert = new List<Round_Result__c>();
        
        for (Id slotId : slotTotal.keySet()) {
            
            Decimal avgScore =
                slotTotal.get(slotId) / slotCount.get(slotId);
            
            if (slotIdToRoundResult.containsKey(slotId)) {
                // ✅ UPDATE existing
                Round_Result__c existing = slotIdToRoundResult.get(slotId);
                existing.Net_Score__c = avgScore;
                toUpsert.add(existing);
            } else {
                // ➕ CREATE new (only once ever)
                toUpsert.add(new Round_Result__c(
                    ApplicationSlotBooking__c = slotId,
                Net_Score__c = avgScore
                    ));
            }
        }
        
        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
    }
    
    
    /* =========================
    ===== UTIL ==============
        ========================= */
        
    private static Set<Id> flatten(List<List<Id>> lists) {
        Set<Id> result = new Set<Id>();
        for (List<Id> l : lists) result.addAll(l);
        return result;
    }
}
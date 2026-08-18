public class ApplicationEvaluationExport implements Database.Batchable<SObject>, Database.Stateful {
    private static final Integer MAX_ROWS_PER_FILE = 5000;
    private static final String EVENT_INTENT = 'ApplicationEvaluationExport';

    private Id programId;
    private Id roundId;
    private Date slotStartDate;
    private Date slotEndDate;
    private Time slotStartTime;
    private Time slotEndTime;
    private String programName;
    private String roundName;
    private Id batchJobId;
    private Boolean recordsFound = false;
    private Integer currentRowCount = 0;
    private Integer fileNumber = 1;
    private Boolean showCriteriaComment = false;
    private List<String> csvRows = new List<String>();
    private List<ScoringTemplate__c> scoringTemplates = new List<ScoringTemplate__c>();
    private List<ExportUtils.GeneratedFile> generatedFiles = new List<ExportUtils.GeneratedFile>();

    public ApplicationEvaluationExport(Id programId, Id roundId, Date slotStartDate, Date slotEndDate, Time slotStartTime, Time slotEndTime) {
        this.programId = programId;
        this.roundId = roundId;
        this.slotStartDate = slotStartDate;
        this.slotEndDate = slotEndDate;
        this.slotStartTime = slotStartTime;
        this.slotEndTime = slotEndTime;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        batchJobId = bc.getJobId();
        initializeExportContext();

        Date effectiveEndDate = slotEndDate;
        if (slotStartDate != null && effectiveEndDate == null) {
            effectiveEndDate = Date.today();
        }

        String query =
            'SELECT Id, EvaluatorComments__c, Total_Score__c, ' +
            'EvaluatedUser__r.Name, ' +
            'Application_Slot_Booking__r.Application__r.Name, ' +
            'Application_Slot_Booking__r.Applicant_Name__c, ' +
            'Application_Slot_Booking__r.SlotMaster__r.Name, ' +
            'Application_Slot_Booking__r.SlotMaster__r.SlotDate__c, ' +
            'Application_Slot_Booking__r.SlotMaster__r.SlotStartTime__c, ' +
            'Application_Slot_Booking__r.SlotMaster__r.SlotEndtime__c, ' +
            'Application_Slot_Booking__r.SlotMaster__r.Program_Master__r.Name, ' +
            'Application_Slot_Booking__r.RoundMaster__r.Name, ' +
            'Application_Slot_Booking__r.SlotMaster__r.LocationMaster__r.LocationName__c, ' +
            'Application_Slot_Booking__r.SlotMaster__r.LocationMaster__r.AddressInformation__c, ' +
            '(SELECT Id, Score__c, Comments__c, Criteria_Description__c, Scoring_Template__c, Scoring_Template__r.CriteriaName__c ' +
            ' FROM Individual_Criteria_Results__r) ' +
            'FROM Evaluation__c ' +
            'WHERE Application_Slot_Booking__r.SlotMaster__r.Program_Master__c = :programId ' +
            'AND Application_Slot_Booking__r.RoundMaster__c = :roundId';

        if (slotStartDate != null) {
            query += ' AND Application_Slot_Booking__r.Slot_Date__c >= :slotStartDate';
            query += ' AND Application_Slot_Booking__r.Slot_Date__c <= :effectiveEndDate';
        }
        if (slotStartTime != null) {
            query += ' AND Application_Slot_Booking__r.SlotMaster__r.SlotStartTime__c >= :slotStartTime';
        }
        if (slotEndTime != null) {
            query += ' AND Application_Slot_Booking__r.SlotMaster__r.SlotEndtime__c <= :slotEndTime';
        }

        query += ' ORDER BY Application_Slot_Booking__r.Application__r.Name, EvaluatedUser__r.Name';

        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Evaluation__c> scope) {
        if (!scope.isEmpty()) {
            recordsFound = true;
        }

        for (Evaluation__c evaluation : scope) {
            ApplicationSlotBooking__c booking = evaluation.Application_Slot_Booking__r;
            SlotMaster__c slotMaster = booking == null ? null : booking.SlotMaster__r;
            LocationMaster__c location = slotMaster == null ? null : slotMaster.LocationMaster__r;

            List<String> row = new List<String>{
                ExportUtils.csvCell(booking == null || booking.Application__r == null ? null : booking.Application__r.Name),
                ExportUtils.csvCell(booking == null ? null : booking.Applicant_Name__c),
                ExportUtils.csvCell(evaluation.EvaluatedUser__r == null ? null : evaluation.EvaluatedUser__r.Name),
                ExportUtils.csvCell(slotMaster == null ? null : slotMaster.Name),
                ExportUtils.csvCell(slotMaster == null || slotMaster.SlotDate__c == null ? null : String.valueOf(slotMaster.SlotDate__c)),
                ExportUtils.csvCell(slotMaster == null || slotMaster.SlotStartTime__c == null ? null : formatTime(slotMaster.SlotStartTime__c)),
                ExportUtils.csvCell(slotMaster == null || slotMaster.SlotEndtime__c == null ? null : formatTime(slotMaster.SlotEndtime__c)),
                ExportUtils.csvCell(slotMaster == null || slotMaster.Program_Master__r == null ? programName : slotMaster.Program_Master__r.Name),
                ExportUtils.csvCell(booking == null || booking.RoundMaster__r == null ? roundName : booking.RoundMaster__r.Name),
                ExportUtils.csvCell(location == null ? null : location.LocationName__c),
                ExportUtils.csvCell(location == null ? null : location.AddressInformation__c)
            };

            Map<String, Individual_Criteria_Result__c> resultByTemplateId = new Map<String, Individual_Criteria_Result__c>();
            Map<String, Individual_Criteria_Result__c> resultByCriteriaName = new Map<String, Individual_Criteria_Result__c>();

            if (evaluation.Individual_Criteria_Results__r != null) {
                for (Individual_Criteria_Result__c result : evaluation.Individual_Criteria_Results__r) {
                    if (result.Scoring_Template__c != null) {
                        resultByTemplateId.put((String) result.Scoring_Template__c, result);
                    }

                    String descriptionKey = ExportUtils.normalize(result.Criteria_Description__c);
                    if (String.isNotBlank(descriptionKey)) {
                        resultByCriteriaName.put(descriptionKey, result);
                    }

                    String templateNameKey = result.Scoring_Template__r == null
                        ? ''
                        : ExportUtils.normalize(result.Scoring_Template__r.CriteriaName__c);
                    if (String.isNotBlank(templateNameKey)) {
                        resultByCriteriaName.put(templateNameKey, result);
                    }
                }
            }

            for (ScoringTemplate__c template : scoringTemplates) {
                Individual_Criteria_Result__c result = resultByTemplateId.get((String) template.Id);
                if (result == null) {
                    result = resultByCriteriaName.get(ExportUtils.normalize(template.CriteriaName__c));
                }
                row.add(ExportUtils.csvCell(result == null ? null : result.Score__c));
                if (showCriteriaComment) {
                    row.add(ExportUtils.csvCell(result == null ? null : result.Comments__c));
                }
            }
            row.add(ExportUtils.csvCell(evaluation.Total_Score__c == null ? null : String.valueOf(evaluation.Total_Score__c)));
            row.add(ExportUtils.csvCell(evaluation.EvaluatorComments__c));
            csvRows.add(String.join(row, ','));
            currentRowCount++;

            if (currentRowCount == MAX_ROWS_PER_FILE) {
                createCsvFile();
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (currentRowCount > 0) {
            createCsvFile();
        }
        ExportUtils.publishExportEvent(EVENT_INTENT, recordsFound, generatedFiles);
    }

    private void initializeExportContext() {
        Program programRecord = [
            SELECT Name, Program_Code__c
            FROM Program
            WHERE Id = :programId
            LIMIT 1
        ];
        programName = String.isBlank(programRecord.Program_Code__c)
            ? programRecord.Name
            : programRecord.Program_Code__c;
        showCriteriaComment = shouldShowCriteriaComment(programName);

        RoundMaster__c roundRecord = [
            SELECT Name
            FROM RoundMaster__c
            WHERE Id = :roundId
            LIMIT 1
        ];
        roundName = roundRecord.Name;

        scoringTemplates = [
            SELECT Id, CriteriaName__c
            FROM ScoringTemplate__c
            WHERE Round__c = :roundId
            ORDER BY CriteriaName__c
        ];

        csvRows.add(buildHeaderRow());
    }

    private String buildHeaderRow() {
        List<String> headers = new List<String>{
            ExportUtils.csvCell('Application Number'),
            ExportUtils.csvCell('Applicant Name'),
            ExportUtils.csvCell('Evaluated By'),
            ExportUtils.csvCell('Slot Code'),
            ExportUtils.csvCell('Slot Date'),
            ExportUtils.csvCell('Slot Start Time'),
            ExportUtils.csvCell('Slot End Time'),
            ExportUtils.csvCell('Program'),
            ExportUtils.csvCell('Round name'),
            ExportUtils.csvCell('Interview location'),
            ExportUtils.csvCell('Interview location address')
        };

        for (ScoringTemplate__c template : scoringTemplates) {
            String criteriaName = String.isBlank(template.CriteriaName__c)
                ? 'Criteria'
                : template.CriteriaName__c;
            headers.add(ExportUtils.csvCell(criteriaName + ' score'));
            if (showCriteriaComment) {
                headers.add(ExportUtils.csvCell(criteriaName + ' comment'));
            }
        }
        headers.add(ExportUtils.csvCell('Total Score'));
        headers.add(ExportUtils.csvCell('Evaluator comment'));
        return String.join(headers, ',');
    }

    private void createCsvFile() {
        if (currentRowCount == 0) {
            return;
        }

        String fileName = ExportUtils.safeFilePart(programName) + '_' + ExportUtils.safeFilePart(roundName) + '_Application_Evaluations_Part_' + fileNumber;

        ExportUtils.GeneratedFile generated = ExportUtils.createCsvFile(fileName, csvRows, batchJobId);

        if (generated != null) {
            generatedFiles.add(generated);
        }

        csvRows.clear();
        csvRows.add(buildHeaderRow());
        currentRowCount = 0;
        fileNumber++;
    }

    private static Boolean shouldShowCriteriaComment(String programCode) {
        if (String.isBlank(programCode)) {
            return false;
        }

        List<ApplicationProgramBasedConfig__mdt> records = [
            SELECT Type__c, ConfigValue__c
            FROM ApplicationProgramBasedConfig__mdt
            WHERE Intent__c = 'CommentForEachCriteria'
            AND ProgramCode__c = :programCode
            AND Active__c = true
            LIMIT 1
        ];

        return !records.isEmpty()
            && records[0].Type__c == 'Boolean'
            && records[0].ConfigValue__c != null
            && records[0].ConfigValue__c.trim().equalsIgnoreCase('true');
    }

    private static String formatTime(Time val) {
        if (val == null) {
            return '';
        }
        DateTime dt = DateTime.newInstance(Date.newInstance(2000, 1, 1), val);
        return dt.format('hh:mm a');
    }
}
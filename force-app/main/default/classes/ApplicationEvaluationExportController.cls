public with sharing class ApplicationEvaluationExportController {
    @AuraEnabled
    public static String startExport(Id programId, Id roundId, Date slotStartDate, Date slotEndDate) {
        validateRequest(programId, roundId, slotStartDate, slotEndDate);

        return Database.executeBatch(
            new ApplicationEvaluationExport(programId, roundId, slotStartDate, slotEndDate),
            1000
        );
    }

    @AuraEnabled(cacheable=true)
    public static Integer getEvaluationCount(Id programId, Id roundId, Date slotStartDate, Date slotEndDate) {
        validateRequest(programId, roundId, slotStartDate, slotEndDate);

        Date effectiveEndDate = slotEndDate;
        if (slotStartDate != null && effectiveEndDate == null) {
            effectiveEndDate = Date.today();
        }

        String query =
            'SELECT Count() ' +
            'FROM Evaluation__c ' +
            'WHERE Application_Slot_Booking__r.SlotMaster__r.Program_Master__c = :programId ' +
            'AND Application_Slot_Booking__r.RoundMaster__c = :roundId';

        if (slotStartDate != null) {
            query += ' AND Application_Slot_Booking__r.Slot_Date__c >= :slotStartDate';
            query += ' AND Application_Slot_Booking__r.Slot_Date__c <= :effectiveEndDate';
        }

        return Database.countQuery(query);
    }

    @AuraEnabled
    public static void sendExportEmail(String filesJson) {
        ExportUtils.sendExportEmail(filesJson, 'Application Evaluation Export');
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isRoundForProgram(Id programId, Id roundId) {
        if (programId == null || roundId == null) {
            return false;
        }

        return [
            SELECT Count()
            FROM RoundMaster__c
            WHERE Id = :roundId
            AND Program__c = :programId
        ] > 0;
    }

    private static void validateRequest(Id programId, Id roundId, Date slotStartDate, Date slotEndDate) {
        if (programId == null) {
            throw new AuraHandledException('Select a program before starting the export.');
        }
        if (roundId == null) {
            throw new AuraHandledException('Select a round before starting the export.');
        }
        if (slotStartDate != null && slotStartDate > Date.today()) {
            throw new AuraHandledException('Slot Start Date cannot be a future date.');
        }
        if (slotStartDate == null && slotEndDate != null) {
            throw new AuraHandledException('Enter Slot Start Date before selecting Slot End Date.');
        }
        if (slotStartDate != null && slotEndDate != null && slotEndDate < slotStartDate) {
            throw new AuraHandledException('Slot End Date cannot be before Slot Start Date.');
        }
        if (!isRoundForProgram(programId, roundId)) {
            throw new AuraHandledException('The selected round does not belong to the selected program.');
        }
    }
}

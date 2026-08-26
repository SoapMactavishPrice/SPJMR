public with sharing class ApplicationEvaluationExportController {
    @AuraEnabled
    public static String startExport(Id programId, Id roundId, Date slotStartDate, Date slotEndDate, String slotStartTimeStr, String slotEndTimeStr) {
        Time slotStartTime = parseTimeFilter(slotStartTimeStr);
        Time slotEndTime = parseTimeFilter(slotEndTimeStr);
        validateRequest(programId, roundId, slotStartDate, slotEndDate, slotStartTime, slotEndTime);

        return Database.executeBatch(
            new ApplicationEvaluationExport(programId, roundId, slotStartDate, slotEndDate, slotStartTime, slotEndTime),
            1000
        );
    }

    @AuraEnabled(cacheable=true)
    public static Integer getEvaluationCount(Id programId, Id roundId, Date slotStartDate, Date slotEndDate, String slotStartTimeStr, String slotEndTimeStr) {
        Time slotStartTime = parseTimeFilter(slotStartTimeStr);
        Time slotEndTime = parseTimeFilter(slotEndTimeStr);
        validateRequest(programId, roundId, slotStartDate, slotEndDate, slotStartTime, slotEndTime);

        String query =
            'SELECT COUNT_DISTINCT(Application_Slot_Booking__c) cnt ' +
            'FROM Evaluation__c ' +
            'WHERE Application_Slot_Booking__r.SlotMaster__r.Program_Master__c = :programId ' +
            'AND Application_Slot_Booking__r.RoundMaster__c = :roundId';

        if (slotStartDate != null) {
            query += ' AND Application_Slot_Booking__r.Slot_Date__c >= :slotStartDate';
        }
        if (slotEndDate != null) {
            query += ' AND Application_Slot_Booking__r.Slot_Date__c <= :slotEndDate';
        }
        if (slotStartTime != null) {
            query += ' AND Application_Slot_Booking__r.SlotMaster__r.SlotStartTime__c >= :slotStartTime';
        }
        if (slotEndTime != null) {
            query += ' AND Application_Slot_Booking__r.SlotMaster__r.SlotEndtime__c <= :slotEndTime';
        }

        AggregateResult[] results = Database.query(query);
        return results.isEmpty() ? 0 : (Integer) results[0].get('cnt');
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

    private static void validateRequest(Id programId, Id roundId, Date slotStartDate, Date slotEndDate, Time slotStartTime, Time slotEndTime) {
        if (programId == null) {
            throw new AuraHandledException('Select a program before starting the export.');
        }
        if (roundId == null) {
            throw new AuraHandledException('Select a round before starting the export.');
        }
        if (slotStartDate == null && slotEndDate != null) {
            throw new AuraHandledException('Enter Slot Start Date before selecting Slot End Date.');
        }
        if (slotStartDate != null && slotEndDate != null && slotEndDate < slotStartDate) {
            throw new AuraHandledException('Slot End Date cannot be before Slot Start Date.');
        }
        if (slotStartTime != null && slotEndTime != null && slotEndTime < slotStartTime) {
            throw new AuraHandledException('Slot End Time cannot be before Slot Start Time.');
        }
        if (!isRoundForProgram(programId, roundId)) {
            throw new AuraHandledException('The selected round does not belong to the selected program.');
        }
    }

    private static Time parseTimeFilter(String val) {
        if (String.isBlank(val)) {
            return null;
        }
        try {
            if (val.endsWith('Z')) {
                val = val.substring(0, val.length() - 1);
            }
            if (val.contains('.')) {
                val = val.split('\\.')[0];
            }
            List<String> parts = val.split(':');
            Integer hours = Integer.valueOf(parts[0]);
            Integer minutes = Integer.valueOf(parts[1]);
            Integer seconds = parts.size() > 2 ? Integer.valueOf(parts[2]) : 0;
            return Time.newInstance(hours, minutes, seconds, 0);
        } catch (Exception e) {
            return null;
        }
    }
}
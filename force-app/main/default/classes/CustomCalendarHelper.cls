public with sharing class CustomCalendarHelper {
    
    @AuraEnabled
    public static List<sObject> getEvents(
        String recordId,
        String childObject,
        String parentFieldName,
        String startDatetimeField,
        String endDatetimeField,
        String titleField,
        Date startDate,
        Date endDate) {

        if (
            recordId == null ||
            childObject == null ||
            parentFieldName == null ||
            startDatetimeField == null ||
            endDatetimeField == null ||
            titleField == null
        ) {
            throw new AuraHandledException('Missing Config');
        }

        DateTime startDateTime = DateTime.newInstance(startDate.year(), startDate.month(), startDate.day());
        DateTime endDateTime = DateTime.newInstance(endDate.year(), endDate.month(), endDate.day());

        String query = 'SELECT Id, ' + titleField + ', ';
        // query = childObject== 'Event' ? query : query + 'Name, ';
        query += startDatetimeField + ', ' + endDatetimeField;
        query += ' FROM ' +  childObject;
        query += ' WHERE ' + parentFieldName + ' = ' + '\'' + recordId +'\'';
        query += ' AND ' + startDatetimeField + ' >= : startDateTime';
        query += ' AND ' + endDatetimeField + ' <=  : endDateTime';
        system.debug(query);
        return Database.query(query);
    }

    // New method to create Event records via custom form (avoiding UI API limitations)
    @AuraEnabled
    public static String createEvent(CreateEventPayload payload) {
        if (payload == null || payload.subject == null || payload.startIso == null || payload.endIso == null) {
            throw new AuraHandledException('Required fields missing: subject, startIso, endIso.');
        }

        Event evt = new Event();

        // Required fields
        evt.Subject = payload.subject;
        evt.StartDateTime = DateTime.parse(payload.startIso);
        evt.EndDateTime = DateTime.parse(payload.endIso);

        // Optional fields
        if (payload.ownerId != null && payload.ownerId != '') {
            evt.OwnerId = payload.ownerId;
        } else {
            evt.OwnerId = UserInfo.getUserId(); // Assign to current user if not provided
        }

        if (payload.currencyIsoCode != null) {
            evt.CurrencyIsoCode = payload.currencyIsoCode;
        }

        // Parent relationship (if provided)
        if (payload.parentFieldApiName != null && payload.parentRecordId != null) {
            evt.put(payload.parentFieldApiName, payload.parentRecordId);
        }

        try {
            insert evt;
            return evt.Id;
        } catch (DmlException e) {
            System.debug('Error creating Event: ' + e.getMessage());
            throw new AuraHandledException('Failed to create Event: ' + e.getMessage());
        }
    }

    // Payload class for createEvent
    public class CreateEventPayload {
        @AuraEnabled public String subject;
        @AuraEnabled public String startIso;
        @AuraEnabled public String endIso;
        @AuraEnabled public String ownerId;
        @AuraEnabled public String currencyIsoCode;
        @AuraEnabled public String parentFieldApiName;
        @AuraEnabled public String parentRecordId;
    }
}
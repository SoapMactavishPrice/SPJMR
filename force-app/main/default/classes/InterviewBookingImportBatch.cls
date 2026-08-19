public with sharing class InterviewBookingImportBatch implements Database.Batchable<SObject>, Database.Stateful {
    private static final String WITHOUT_PANEL = 'WITHOUT_PANEL';
    private static final String WITH_PANEL = 'WITH_PANEL';
    private static final String ASSIGN_PANEL = 'ASSIGN_PANEL';

    private class ImportException extends Exception {}
    private class Row {
        Map<String, String> values;
        Row(Map<String, String> values) { this.values = values; }
    }
    private class PendingBooking {
        Row row;
        ApplicationSlotBooking__c booking;
        Id programId;
        String panelKey;
        Date slotDate;
        public Boolean hasError = false;
        PendingBooking(Row row, ApplicationSlotBooking__c booking, Id programId, String panelKey) {
            this.row = row; this.booking = booking; this.programId = programId; this.panelKey = panelKey;
        }
    }

    private List<Id> contentVersionIds;
    private String importType;
    private Id selectedProgramId;
    private Boolean notifyApplicants;
    private Boolean notifyInterviewers;
    private Boolean emailErrorCsv;
    private Integer successCount = 0;
    private Integer failedCount = 0;
    private List<String> errorRows = new List<String>();
    private List<String> successRows = new List<String>();
    private Id errorContentDocumentId;
    private List<Id> successContentDocumentIds = new List<Id>();
    private List<String> errorHeaders = new List<String>();
    private List<String> successHeaders = new List<String>();

    public InterviewBookingImportBatch(
        List<Id> contentVersionIds, String importType, Id selectedProgramId, Boolean notifyApplicants,
        Boolean notifyInterviewers, Boolean emailErrorCsv
    ) {
        this.contentVersionIds = contentVersionIds;
        this.importType = importType;
        this.selectedProgramId = selectedProgramId;
        this.notifyApplicants = notifyApplicants;
        this.notifyInterviewers = notifyInterviewers;
        this.emailErrorCsv = emailErrorCsv;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Title, VersionData FROM ContentVersion WHERE Id IN :contentVersionIds ORDER BY CreatedDate
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
         for (SObject scopeRecord : scope) {
            try {
                processFile((contentVersion)scopeRecord);
            } catch (Exception exp) {
                addFileError(((contentVersion)scopeRecord).Title, exp.getMessage());
            }
        }
    }

    private void processFile(ContentVersion version) {
        List<List<String>> csvRows = RT_CSVReader.read(version.VersionData.toString());
        if (csvRows == null || csvRows.size() <= 1) throw new ImportException('The uploaded file has no data rows.');
        Map<String, Integer> indexes = getHeaderIndexes(csvRows[0]);
        validateHeaders(indexes);

        errorHeaders = new List<String>();
        if (importType == ASSIGN_PANEL) {
            errorHeaders.add('ApplicationSlotBookingCode');
            errorHeaders.add('Interviewer Emails');
        } else {
            errorHeaders.add('Application Number');
            errorHeaders.add('Slot Code');
            errorHeaders.add('Round Name');

            if (importType == WITH_PANEL) {
                errorHeaders.add('Interviewer Emails');
            }
        }
        errorHeaders.add('Error');

        successHeaders = new List<String>(errorHeaders);
        successHeaders.remove(successHeaders.size() - 1);
        if (importType == WITHOUT_PANEL) {
            successHeaders.add('ApplicationSlotBookingCode');
            successHeaders.add('Interviewer Emails');
        } else if (importType == WITH_PANEL) {
            successHeaders.add('ApplicationSlotBookingCode');
            successHeaders.add('Panel Code');
        } else {
            successHeaders.add('Panel Code');
        }

        if (errorRows.isEmpty()) {
            errorRows.add(String.join(errorHeaders, ','));
        }
        if (successRows.isEmpty()) {
            successRows.add(String.join(successHeaders, ','));
        }

        List<Row> rows = new List<Row>();
        for (Integer index = 1; index < csvRows.size(); index++) {
            if (csvRows[index] == null || csvRows[index].isEmpty()) continue;
            rows.add(new Row(mapValues(csvRows[index], indexes)));
        }
        if (importType == ASSIGN_PANEL) processAssignPanel(rows);
        else processBooking(rows, importType == WITH_PANEL);
    }

    private Map<String, Integer> getHeaderIndexes(List<String> headerRow) {
        Map<String, Integer> indexes = new Map<String, Integer>();
        for (Integer index = 0; index < headerRow.size(); index++) {
            String header = headerRow[index] == null ? '' : headerRow[index].trim().replace('\uFEFF', '');
            indexes.put(header, index);
        }
        return indexes;
    }

    private void validateHeaders(Map<String, Integer> indexes) {
        List<String> required = importType == ASSIGN_PANEL
            ? new List<String>{ 'ApplicationSlotBookingCode', 'Interviewer Emails' }
            : new List<String>{ 'Application Number', 'Slot Code', 'Round Name' };
        if (importType == WITH_PANEL) required.add('Interviewer Emails');
        List<String> missing = new List<String>();
        for (String header : required) if (!indexes.containsKey(header)) missing.add(header);
        if (!missing.isEmpty()) throw new ImportException('Missing mandatory header(s): ' + String.join(missing, ', '));
    }

    private Map<String, String> mapValues(List<String> csvRow, Map<String, Integer> indexes) {
        Map<String, String> values = new Map<String, String>();
        for (String header : indexes.keySet()) {
            Integer index = indexes.get(header);
            values.put(header, index < csvRow.size() && csvRow[index] != null ? csvRow[index].trim() : '');
        }
        return values;
    }

    private void processBooking(List<Row> rows, Boolean withPanel) {
        Set<String> appNumbers = new Set<String>(); 
        Set<String> slotCodes = new Set<String>(); 
        Set<String> roundNames = new Set<String>();
        for (Row row : rows) { 
            appNumbers.add(row.values.get('Application Number')); 
            slotCodes.add(row.values.get('Slot Code')); 
            roundNames.add(row.values.get('Round Name')); 
        }
        Map<String, Application__c> apps = new Map<String, Application__c>();
        for (Application__c app : [SELECT Id, Name, Program__c FROM Application__c WHERE Name IN :appNumbers]) apps.put(app.Name, app);
        Map<String, SlotMaster__c> slots = new Map<String, SlotMaster__c>();
        for (SlotMaster__c slot : [SELECT Id, Name, SlotDate__c FROM SlotMaster__c WHERE Name IN :slotCodes]) slots.put(slot.Name, slot);
        Map<String, RoundMaster__c> rounds = new Map<String, RoundMaster__c>();
        for (RoundMaster__c round : [SELECT Id, Name FROM RoundMaster__c WHERE Name IN :roundNames]) rounds.put(round.Name, round);
        Map<String, ApplicationSlotBooking__c> existingBookings = getExistingBookings(appNumbers);

        List<PendingBooking> pending = new List<PendingBooking>();
        for (Row row : rows) {
            try {
                String appNumber = require(row, 'Application Number');
                String slotCode = require(row, 'Slot Code');
                String roundName = require(row, 'Round Name');
                if (!apps.containsKey(appNumber)) throw new ImportException('Application not found: ' + appNumber);
                if (!slots.containsKey(slotCode)) throw new ImportException('Slot not found: ' + slotCode);
                if (!rounds.containsKey(roundName)) throw new ImportException('Round not found: ' + roundName);
                if (slots.get(slotCode).SlotDate__c < Date.today()) {
                    throw new ImportException('Cannot book an interview for a slot whose Slot Date is in the past.');
                }
                String existingBookingKey = bookingKey(appNumber, slotCode, roundName);
                // A With panel booking is only a duplicate when the resolved panel also matches
                if (!withPanel && existingBookings.containsKey(existingBookingKey)) {
                    addSuccess(row, existingBookings.get(existingBookingKey));
                    successCount++;
                    continue;
                }
                ApplicationSlotBooking__c booking = new ApplicationSlotBooking__c(
                    Application__c = apps.get(appNumber).Id, SlotMaster__c = slots.get(slotCode).Id,
                    RoundMaster__c = rounds.get(roundName).Id, BookingState__c = 'Booked'
                );
                PendingBooking pendingBooking = new PendingBooking(
                    row,
                    booking,
                    withPanel ? selectedProgramId : null,
                    withPanel ? getEmailKey(require(row, 'Interviewer Emails')) : null
                );
                pendingBooking.slotDate = slots.get(slotCode).SlotDate__c;
                pending.add(pendingBooking);
            } catch (Exception exp) {
                 addError(row, exp.getMessage()); 
            }
        }
        if (withPanel) resolvePanelsAndInsert(pending);
        else insertBookings(pending);
    }

    private static Map<String, ApplicationSlotBooking__c> getExistingBookings(Set<String> applicationNumbers) {
        Map<String, ApplicationSlotBooking__c> bookingsByKey = new Map<String, ApplicationSlotBooking__c>();
        Date today = Date.today();
        for (ApplicationSlotBooking__c booking : [
            SELECT Id, Name, Application__r.Name, SlotMaster__r.Name, RoundMaster__r.Name,
                   Panel_Master__r.Name, Slot_Date__c
            FROM ApplicationSlotBooking__c
            WHERE Application__r.Name IN :applicationNumbers
            AND Slot_Date__c >= :today
        ]) {
            bookingsByKey.put(
                bookingKey(booking.Application__r.Name, booking.SlotMaster__r.Name, booking.RoundMaster__r.Name),
                booking
            );
        }
        return bookingsByKey;
    }

    private static String bookingKey(String applicationNumber, String slotCode, String roundName) {
        return applicationNumber + '|' + slotCode + '|' + roundName;
    }

    private void processAssignPanel(List<Row> rows) {
        Set<String> bookingCodes = new Set<String>();
        for (Row row : rows) bookingCodes.add(row.values.get('ApplicationSlotBookingCode'));
        Map<String, ApplicationSlotBooking__c> bookings = new Map<String, ApplicationSlotBooking__c>();

        for (ApplicationSlotBooking__c booking : [
            SELECT Id, Name, Application__r.Program__c FROM ApplicationSlotBooking__c WHERE Name IN :bookingCodes
        ]) bookings.put(booking.Name, booking);

        List<PendingBooking> pending = new List<PendingBooking>();
        for (Row row : rows) {
            try {
                String bookingCode = require(row, 'ApplicationSlotBookingCode');
                if (!bookings.containsKey(bookingCode)) throw new ImportException('Application Slot Booking not found: ' + bookingCode);
                ApplicationSlotBooking__c booking = new ApplicationSlotBooking__c(Id = bookings.get(bookingCode).Id);
                pending.add(new PendingBooking(row, booking, bookings.get(bookingCode).Application__r.Program__c, getEmailKey(require(row, 'Interviewer Emails'))));
            } catch (Exception exp) { 
                addError(row, exp.getMessage()); 
            }
        }
        resolvePanelsAndUpdate(pending);
    }

    private void resolvePanelsAndInsert(List<PendingBooking> pending) {
        Map<String, Id> panels = resolvePanels(pending);
        Map<Id, String> panelNamesById = getPanelNames(panels.values());
        Map<String, ApplicationSlotBooking__c> existingBookings = getExistingPanelBookings(pending);
        List<PendingBooking> valid = new List<PendingBooking>();
        for (PendingBooking item : pending) {
            if (item.hasError) {
                continue;
            }
            if (panels.containsKey(panelMapKey(item.programId, item.panelKey))) {
                Id panelId = panels.get(panelMapKey(item.programId, item.panelKey));
                item.booking.Panel_Master__c = panelId;
                String existingBookingKey = panelBookingKey(
                    item.row.values.get('Application Number'),
                    item.slotDate,
                    item.row.values.get('Round Name'),
                    panelNamesById.get(panelId)
                );
                if (existingBookings.containsKey(existingBookingKey)) {
                    addSuccess(item.row, existingBookings.get(existingBookingKey));
                    successCount++;
                }else{
                    valid.add(item);
                }
            }else addError(item.row, 'Unable to create or find a matching panel.');
        }
        insertBookings(valid);
    }

    private static Map<Id, String> getPanelNames(List<Id> panelIds) {
        Map<Id, String> namesById = new Map<Id, String>();
        if (panelIds.isEmpty()) return namesById;
        for (PanelMaster__c panel : [ SELECT Id, Name FROM PanelMaster__c WHERE Id IN :panelIds]) {
            namesById.put(panel.Id, panel.Name);
        }
        return namesById;
    }

    private static Map<String, ApplicationSlotBooking__c> getExistingPanelBookings(
        List<PendingBooking> pending
    ) {
        Map<String, ApplicationSlotBooking__c> bookingsByKey = new Map<String, ApplicationSlotBooking__c>();
        Set<String> applicationNumbers = new Set<String>();
        for (PendingBooking item : pending) {
            if (!item.hasError) applicationNumbers.add(item.row.values.get('Application Number'));
        }
        if (applicationNumbers.isEmpty())  return bookingsByKey;
        Date today = Date.today();

        for (ApplicationSlotBooking__c booking : [
            SELECT Id, Name, Application__r.Name, Slot_Date__c, RoundMaster__r.Name, Panel_Master__r.Name
            FROM ApplicationSlotBooking__c
            WHERE Application__r.Name IN :applicationNumbers
                AND Slot_Date__c >= :today
                AND Panel_Master__c != NULL
        ]) {
            bookingsByKey.put(
                panelBookingKey(
                    booking.Application__r.Name,
                    booking.slot_Date__c,
                    booking.RoundMaster__r.Name,
                    booking.Panel_Master__r.Name
                ),
                booking
            );
        }
        return bookingsByKey;
    }

    private static String panelBookingKey(
        String applicationNumber,
        Date slotDate,
        String roundName,
        String panelName
    ){
        return applicationNumber + '|' + String.valueOf(slotDate) + '|' + roundName + '|' + panelName;
    }
    
    private void resolvePanelsAndUpdate(List<PendingBooking> pending) {
        Map<String, Id> panels = resolvePanels(pending);
        List<ApplicationSlotBooking__c> updates = new List<ApplicationSlotBooking__c>(); 
        List<PendingBooking> updatePending = new List<PendingBooking>();
        for (PendingBooking item : pending) {
            if (item.hasError) {
                continue;
            }
            if (panels.containsKey(panelMapKey(item.programId, item.panelKey))) { 
                item.booking.Panel_Master__c = panels.get(panelMapKey(item.programId, item.panelKey)); 
                updates.add(item.booking); updatePending.add(item); 
            }
            else addError(item.row, 'Unable to create or find a matching panel.');
        }
        processUpdateResults(Database.update(updates, false), updatePending);
    }

    private Map<String, Id> resolvePanels(List<PendingBooking> pending) {
        Set<Id> programIds = new Set<Id>(); 
        Set<String> emails = new Set<String>();

        for (PendingBooking item : pending) { 
            programIds.add(item.programId); 
            emails.addAll(item.panelKey.split(';')); 
        }
        
        Map<String, Id> accountByEmail = new Map<String, Id>();
        for (Account account : [SELECT Id, PersonEmail FROM Account WHERE PersonEmail IN :emails]) accountByEmail.put(account.PersonEmail.toLowerCase(), account.Id);
        Map<Id, String> programCodeById = new Map<Id, String>();
        for (Program program : [SELECT Id, Program_Code__c FROM Program WHERE Id IN :programIds]) programCodeById.put(program.Id, program.Program_Code__c);
        Map<String, Id> panelByKey = getExistingPanels(programIds);
        Map<String, List<String>> newKeys = new Map<String, List<String>>();
        Map<String, Id> programIdByPanelKey = new Map<String, Id>();
        for (PendingBooking item : pending) {
            String key = panelMapKey(item.programId, item.panelKey);
            if (!panelByKey.containsKey(key) && !newKeys.containsKey(key)) {
                newKeys.put(key, item.panelKey.split(';'));
                programIdByPanelKey.put(key, item.programId);
            }
        }
        List<PanelMaster__c> panelsToInsert = new List<PanelMaster__c>(); List<String> panelKeys = new List<String>();
        // for (String key : newKeys.keySet()) {
        //     // List<String> keyParts = key.split('\|'); 
        //     List<String> keyParts = key.split('\\|');
        //     Id programId = keyParts[0];
        //     for (String email : newKeys.get(key)) if (!accountByEmail.containsKey(email)) { addError('Panel ' + key, 'Account not found for interviewer email: ' + email); }
        //     Boolean allAccountsFound = true; 
        //     for (String email : newKeys.get(key)) if (!accountByEmail.containsKey(email)) allAccountsFound = false;
        //     if (!allAccountsFound) continue;
        //     panelsToInsert.add(new PanelMaster__c(
        //         Program__c = programId,
        //         PanelName__c = programCodeById.get(programId) + '-' + String.valueOf(Crypto.getRandomLong()).replace('-', ''),
        //         Status__c = 'Active'
        //     ));
        //     panelKeys.add(key);
        // }

        Set<String> processedPanelKeys = new Set<String>();
        for (PendingBooking item : pending) {
            String key = panelMapKey(item.programId, item.panelKey);
            if (!newKeys.containsKey(key) || processedPanelKeys.contains(key)) {
                continue;
            }
            processedPanelKeys.add(key);
            Id programId = programIdByPanelKey.get(key);
            String missingEmail;
            for (String email : newKeys.get(key)) {
                if (!accountByEmail.containsKey(email)) {
                    missingEmail = email;
                    break;
                }
            }
            if (missingEmail != null) {
                for (PendingBooking pendingItem : pending) {
                    if (panelMapKey(pendingItem.programId, pendingItem.panelKey) == key) {
                        pendingItem.hasError = true;
                        addError(pendingItem.row, 'Account not found for interviewer email: ' + missingEmail);
                    }
                }
                continue;
            }
            panelsToInsert.add(new PanelMaster__c(
                    Program__c = programId,
                    PanelName__c = programCodeById.get(programId) + '-' +
                        String.valueOf(Crypto.getRandomLong()).replace('-', ''),
                    Status__c = 'Active'
                )
            );
            panelKeys.add(key);
        }
        
        if (!panelsToInsert.isEmpty()) {
            insert panelsToInsert;
            List<PanelInterviewer__c> interviewers = new List<PanelInterviewer__c>();
            for (Integer index = 0; index < panelsToInsert.size(); index++) {
                panelByKey.put(panelKeys[index], panelsToInsert[index].Id);
                for (String email : newKeys.get(panelKeys[index])) {
                    interviewers.add(new PanelInterviewer__c(
                        PanelMaster__c = panelsToInsert[index].Id,
                        Account__c = accountByEmail.get(email)
                    ));
                }
            }
            insert interviewers;
        }
        return panelByKey;
    }

    private static Map<String, Id> getExistingPanels(Set<Id> programIds) {
        Map<Id, Set<String>> emailsByPanel = new Map<Id, Set<String>>(); 
        Set<Id> panelIds = new Set<Id>();
        for (PanelMaster__c panel : [SELECT Id, Program__c FROM PanelMaster__c WHERE Status__c = 'Active' AND Program__c IN :programIds]) { 
            panelIds.add(panel.Id); 
            emailsByPanel.put(panel.Id, new Set<String>()); 
        }

        for (PanelInterviewer__c interviewer : [SELECT PanelMaster__c, Account__r.PersonEmail FROM PanelInterviewer__c WHERE PanelMaster__c IN :panelIds]) if (interviewer.Account__r.PersonEmail != null) emailsByPanel.get(interviewer.PanelMaster__c).add(interviewer.Account__r.PersonEmail.toLowerCase());
        Map<String, Id> result = new Map<String, Id>();
        for (PanelMaster__c panel : [SELECT Id, Program__c FROM PanelMaster__c WHERE Id IN :panelIds]) result.put(panelMapKey(panel.Program__c, getEmailKey(emailsByPanel.get(panel.Id))), panel.Id);
        return result;
    }

    private void insertBookings(List<PendingBooking> pending) {
        List<ApplicationSlotBooking__c> bookings = new List<ApplicationSlotBooking__c>(); 
        List<Row> rows = new List<Row>();
        for (PendingBooking item : pending) { 
            bookings.add(item.booking); 
            rows.add(item.row); 
        }
        processInsertResults(Database.insert(bookings, false), pending);
    }

    private void processResults(Database.SaveResult[] results, List<Row> rows) {
        for (Integer index = 0; index < results.size(); index++) {
            if (results[index].isSuccess()) successCount++;
            else { 
                List<String> messages = new List<String>(); 
                for (Database.Error error : results[index].getErrors()) messages.add(error.getMessage()); 
                addError(rows[index], String.join(messages, '; ')); 
            }
        }
    }

    private void processInsertResults(Database.SaveResult[] results, List<PendingBooking> pending) {
        Map<Id, PendingBooking> pendingByBookingId = new Map<Id, PendingBooking>();
        for (Integer index = 0; index < results.size(); index++) {
            if (results[index].isSuccess()) {
                successCount++;
                pendingByBookingId.put(results[index].getId(), pending[index]);
            } else {
                List<String> messages = new List<String>();
                for (Database.Error error : results[index].getErrors()) messages.add(error.getMessage());
                addError(pending[index].row, String.join(messages, '; '));
            }
        }
        addInsertedBookingSuccessRows(pendingByBookingId);
    }

    private void processUpdateResults(Database.SaveResult[] results, List<PendingBooking> pending) {
        Map<Id, PendingBooking> pendingByBookingId = new Map<Id, PendingBooking>();
        for (Integer index = 0; index < results.size(); index++) {
            if (results[index].isSuccess()) {
                successCount++;
                pendingByBookingId.put(results[index].getId(), pending[index]);
            } else {
                List<String> messages = new List<String>();
                for (Database.Error error : results[index].getErrors()) messages.add(error.getMessage());
                addError(pending[index].row, String.join(messages, '; '));
            }
        }
        addInsertedBookingSuccessRows(pendingByBookingId);
    }

    private void addInsertedBookingSuccessRows(Map<Id, PendingBooking> pendingByBookingId) {
        if (pendingByBookingId.isEmpty()) return;
        for (ApplicationSlotBooking__c booking : [
            SELECT Id, Name, Panel_Master__r.Name
            FROM ApplicationSlotBooking__c
            WHERE Id IN :pendingByBookingId.keySet()
        ]) {
            addSuccess(pendingByBookingId.get(booking.Id).row, booking);
        }
    }

    private void addSuccess(Row row, ApplicationSlotBooking__c booking) {
        List<String> values = new List<String>();
        for (String header : successHeaders) {
            if (header == 'ApplicationSlotBookingCode') values.add(csvValue(booking.Name));
            else if (header == 'Panel Code') values.add(csvValue(booking.Panel_Master__r == null ? null : booking.Panel_Master__r.Name));
            //else if (header == 'Interviewer Emails') values.add(csvValue(''));
            else if (header == 'Interviewer Emails'){
                String interviewerEmails = importType == WITHOUT_PANEL ? '' : row.values.get('Interviewer Emails');
                values.add(csvValue(interviewerEmails));
            } 
            else values.add(csvValue(row.values.get(header)));
        }
        successRows.add(String.join(values, ','));
    }

    private static String require(Row row, String header) { 
        String value = row.values.get(header); 
        if (String.isBlank(value)) throw new ImportException(header + ' is mandatory.'); 
        return value; 
    }

    private static String getEmailKey(String emails) { 
        Set<String> values = new Set<String>(); 
        for (String email : emails.split(';')) if (!String.isBlank(email)) values.add(email.trim().toLowerCase()); 
        List<String> sorted = new List<String>(values); 
        sorted.sort(); 
        if (sorted.isEmpty()) throw new ImportException('Interviewer Emails is mandatory.'); 
        return String.join(sorted, ';'); 
    }

    private static String getEmailKey(Set<String> emails) { 
        return getEmailKey(String.join(new List<String>(emails), ';')); 
    }

    private static String panelMapKey(Id programId, String emailKey) { 
        return String.valueOf(programId) + '|' + emailKey; 
    }

    private void addError(Row row, String message) {
        failedCount++;
        List<String> values = new List<String>();
        for (String header : errorHeaders) {
            if (header == 'Error') {
                values.add(
                    '"' + message.replace('"','""') + '"'
                );
            } else {
                String value = row.values.get(header);
                values.add(
                    '"' +
                    (value == null ? '' : value.replace('"','""')) +
                    '"'
                );
            }
        }
        errorRows.add(String.join(values, ','));
    }


    private void addFileError(String fileName, String message) {
        failedCount++;

        // Initialize generic header if processing failed before CSV headers were read.
        if (errorHeaders.isEmpty()) {
            errorHeaders.add('File');
            errorHeaders.add('Error');
            errorRows.add(String.join(errorHeaders, ','));
        }
        List<String> rowData = new List<String>();
        for (String header : errorHeaders) {
            if (header == 'File') {
                rowData.add(
                    '"' +
                    (fileName == null ? '' : fileName.replace('"', '""')) +
                    '"'
                );
            } else if (header == 'Error') {
                rowData.add(
                    '"' +
                    (message == null ? '' : message.replace('"', '""')) +
                    '"'
                );
            } else {
                rowData.add('""');
            }
        }
        errorRows.add(String.join(rowData, ','));
    }

    public void finish(Database.BatchableContext context) {
        Map<String, Object> payload = new Map<String, Object>{ 'status' => 'Completed', 'successCount' => successCount, 'failedCount' => failedCount, 'hasErrors' => failedCount > 0 };
        if (failedCount > 0) createErrorReport(payload, context.getJobId());
        if (successRows.size() > 1) createSuccessReports(payload, context.getJobId());
        EventBus.publish(new AdmissionConsoleEvent__e(Intent__c = 'InterviewBookingImport', UserId__c = UserInfo.getUserId(), Message__c = JSON.serialize(payload)));
        if (emailErrorCsv && (errorContentDocumentId != null || !successContentDocumentIds.isEmpty())) sendReportsEmail();
        deleteUploadedFiles();
    }

    private void createErrorReport(Map<String, Object> payload, Id jobId) {
        ContentVersion version = new ContentVersion(Title = 'Interview_Booking_Import_Error_Report', PathOnClient = 'Interview_Booking_Import_Error_Report.csv', VersionData = Blob.valueOf(String.join(errorRows, '\n')));
        insert version; 
        version = [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :version.Id]; 
        errorContentDocumentId = version.ContentDocumentId;
        insert new Export_Job__c(DocumentId__c = errorContentDocumentId, JobId__c = jobId, Name = version.Title, Status__c = 'Completed');
        payload.put('contentDocumentId', errorContentDocumentId); 
        payload.put('contentVersionId', version.Id); 
        payload.put('fileName', version.Title + '.csv');
    }

    private void createSuccessReports(Map<String, Object> payload, Id jobId) {
        List<Object> files = new List<Object>();
        Integer partNumber = 1;
        for (Integer startIndex = 1; startIndex < successRows.size(); startIndex += 5000) {
            Integer endIndex = Math.min(startIndex + 5000, successRows.size());
            List<String> rows = new List<String>{ successRows[0] };
            for (Integer rowIndex = startIndex; rowIndex < endIndex; rowIndex++) {
                rows.add(successRows[rowIndex]);
            }
            String title = 'Interview_Booking_Import_Success_Part_' + partNumber;
            ContentVersion version = new ContentVersion(
                Title = title,
                PathOnClient = title + '.csv',
                VersionData = Blob.valueOf(String.join(rows, '\n'))
            );
            insert version;
            version = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];
            insert new Export_Job__c(
                DocumentId__c = version.ContentDocumentId,
                JobId__c = jobId,
                Name = title,
                Status__c = 'Completed'
            );
            successContentDocumentIds.add(version.ContentDocumentId);
            files.add(new Map<String, Object>{ 'name' => title + '.csv', 'documentId' => version.ContentDocumentId, 'contentVersionId' => version.Id });
            partNumber++;
        }
        payload.put('successFiles', files);
    }

    private void sendReportsEmail() {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[]{ UserInfo.getUserEmail() });
        email.setSubject('Interview Booking Import Success/Error CSV Files');
        String body = 'Your Interview Booking import files are ready.\n\n';
        if (errorContentDocumentId != null) {
            body += 'Error CSV: ' + URL.getOrgDomainUrl().toExternalForm() +
                '/lightning/r/ContentDocument/' + errorContentDocumentId + '/view\n';
        }
        for (Id documentId : successContentDocumentIds) {
            body += 'Success CSV: ' + URL.getOrgDomainUrl().toExternalForm() +
                '/lightning/r/ContentDocument/' + documentId + '/view\n';
        }
        email.setPlainTextBody(body);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ email });
    }

    private void deleteUploadedFiles() { 
        if (contentVersionIds.isEmpty()) return; 
        List<ContentDocument> documents = [SELECT Id FROM ContentDocument WHERE Id IN (SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :contentVersionIds)]; 
        if (!documents.isEmpty()) delete documents; 
    }

    private static String csvValue(String value) {
        return '"' + (value == null ? '' : value.replace('"', '""')) + '"';
    }
}
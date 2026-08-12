public without sharing class AdmissionDecisionImportBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private class ImportException extends Exception {}

    private class Row {
        Map<String,String> values;
        Row(Map<String,String> values){
            this.values = values;
        }
    }

    private class PendingDecision{
        Row row;
        Admission_Decision__c decision;

        PendingDecision(Row row, Admission_Decision__c decision){
            this.row = row;
            this.decision = decision;
        }
    }

    private List<Id> contentVersionIds;
    private Boolean emailReports;

    private Integer successCount = 0;
    private Integer failedCount = 0;

    private List<String> errorRows = new List<String>();
    private List<String> successRows = new List<String>();

    private List<String> errorHeaders = new List<String>();
    private List<String> successHeaders = new List<String>();

    private Id errorContentDocumentId;
    private List<Id> successContentDocumentIds = new List<Id>();
    private static Boolean isCsvImport = false;

    public AdmissionDecisionImportBatch(
        List<Id> contentVersionIds,
        Boolean emailReports
    ){
        this.contentVersionIds = contentVersionIds;
        this.emailReports = emailReports;
    }

    public static Boolean isCsvImportInProgress() {
        return isCsvImport;
    }


        public Database.QueryLocator start(Database.BatchableContext context){

        return Database.getQueryLocator(

            [
                SELECT
                    Id,
                    Title,
                    VersionData
                FROM ContentVersion
                WHERE Id IN :contentVersionIds
                ORDER BY CreatedDate
            ]

        );

    }

    public void execute(
        Database.BatchableContext context,
        List<SObject> scope
    ){

        for(SObject obj : scope){

            try{

                processFile((ContentVersion)obj);

            }
            catch(Exception ex){

                addFileError(
                    ((ContentVersion)obj).Title,
                    ex.getMessage()
                );

            }

        }

    }


        private void processFile(ContentVersion version){

        List<List<String>> csvRows =
            RT_CSVReader.read(version.VersionData.toString());

        if(csvRows==null || csvRows.size()<=1){

            throw new ImportException(
                'The uploaded file has no data rows.'
            );

        }

        Map<String,Integer> indexes =
            getHeaderIndexes(csvRows[0]);

        initialiseHeaders();

        validateHeaders(indexes);

        List<Row> rows = new List<Row>();

        for(Integer i=1;i<csvRows.size();i++){

            if(csvRows[i]==null || csvRows[i].isEmpty()){
                continue;
            }

            rows.add(
                new Row(
                    mapValues(
                        csvRows[i],
                        indexes
                    )
                )
            );

        }

        processAdmissionDecisions(rows);

    }


        private void initialiseHeaders(){

        if(errorHeaders.isEmpty()){

            errorHeaders.addAll(new List<String>{

                'Application Number',
                'Admission Decision',
                'Waitlist Number',
                'Offer Date',
                'Last Date of Acceptance',
                'Last Date of Uploading the Signed Letter of Acceptance',
                'Last Date for Completing the Payment of the Acceptance Fee',
                'Last Date for Completing the Payment of the First Installment',
                'Error'

            });

            errorRows.add(
                String.join(errorHeaders,',')
            );

        }

        if(successHeaders.isEmpty()){

            successHeaders.addAll(new List<String>{

                'Application Number',
                'Admission Decision',
                'Waitlist Number',
                'Offer Date',
                'Last Date of Acceptance',
                'Last Date of Uploading the Signed Letter of Acceptance',
                'Last Date for Completing the Payment of the Acceptance Fee',
                'Last Date for Completing the Payment of the First Installment',
                'Admission Decision Name'

            });

            successRows.add(
                String.join(successHeaders,',')
            );

        }

    }


        private Map<String, Integer> getHeaderIndexes(List<String> headerRow) {

        Map<String, Integer> indexes = new Map<String, Integer>();

        for (Integer index = 0; index < headerRow.size(); index++) {

            String header = headerRow[index] == null
                ? ''
                : headerRow[index].trim().replace('\uFEFF', '');

            indexes.put(header, index);

        }

        return indexes;

    }

    private void validateHeaders(Map<String, Integer> indexes) {

        List<String> requiredHeaders = new List<String>{
            'Application Number',
            'Admission Decision',
            'Waitlist Number',
            'Offer Date',
            'Last Date of Acceptance',
            'Last Date of Uploading the Signed Letter of Acceptance',
            'Last Date for Completing the Payment of the Acceptance Fee',
            'Last Date for Completing the Payment of the First Installment'
        };

        List<String> missingHeaders = new List<String>();

        for (String header : requiredHeaders) {

            if (!indexes.containsKey(header)) {

                missingHeaders.add(header);

            }

        }

        if (!missingHeaders.isEmpty()) {

            throw new ImportException(
                'Missing mandatory header(s): ' +
                String.join(missingHeaders, ', ')
            );

        }

    }

    private Map<String, String> mapValues(
        List<String> csvRow,
        Map<String, Integer> indexes
    ) {

        Map<String, String> values = new Map<String, String>();

        for (String header : indexes.keySet()) {

            Integer index = indexes.get(header);

            values.put(
                header,
                index < csvRow.size() && csvRow[index] != null
                    ? csvRow[index].trim()
                    : ''
            );

        }

        return values;

    }

    private static String require(
        Row row,
        String header
    ) {

        String value = row.values.get(header);

        if (String.isBlank(value)) {

            throw new ImportException(
                header + ' is mandatory.'
            );

        }

        return value;

    }

    private static Date parseDate(String value) {

        if (String.isBlank(value)) {
            return null;
        }

        List<String> parts = value.trim().split('-');

        if (parts.size() != 3) {

            throw new ImportException(
                'Invalid Date Format : ' + value +
                '. Expected format is dd-MM-yyyy.'
            );

        }

        Integer day = Integer.valueOf(parts[0]);
        Integer month = Integer.valueOf(parts[1]);
        Integer year = Integer.valueOf(parts[2]);

        return Date.newInstance(year, month, day);

    }


        private void processAdmissionDecisions(List<Row> rows) {

        Set<String> applicationNumbers = new Set<String>();

        for (Row row : rows) {

            applicationNumbers.add(
                row.values.get('Application Number')
            );

        }

        Map<String, Application__c> applicationByNumber =
            new Map<String, Application__c>();

        for (Application__c application : [

            SELECT
                Id,
                Name

            FROM Application__c

            WHERE Name IN :applicationNumbers

        ]) {

            applicationByNumber.put(
                application.Name,
                application
            );

        }

        List<PendingDecision> pending =
            new List<PendingDecision>();

        for (Row row : rows) {

            try {

                String applicationNumber =
                    require(
                        row,
                        'Application Number'
                    );

                if (!applicationByNumber.containsKey(applicationNumber)) {

                    throw new ImportException(
                        'Application not found : ' +
                        applicationNumber
                    );

                }

                String admissionDecision = normaliseAdmissionDecision(
                    require(row, 'Admission Decision')
                );

                if (admissionDecision == null) {

                    throw new ImportException(
                        'Admission Decision must be one of : Eligible for Admission, Waitlisted or Not Eligible.'
                    );

                }

                Admission_Decision__c decision =
                    new Admission_Decision__c();

                decision.Application__c =
                    applicationByNumber.get(applicationNumber).Id;

                decision.Result__c =
                    admissionDecision;

                if (admissionDecision == 'Waitlisted') {

                    String waitlistNumber =
                        require(
                            row,
                            'Waitlist Number'
                        );

                    decision.WaitlistNumber__c = Decimal.valueOf(waitlistNumber);

                }

                if (admissionDecision == 'Eligible for Admission') {

                    decision.Offer_Letter_Date__c =
                        parseDate(
                            require(
                                row,
                                'Offer Date'
                            )
                        );

                    decision.LastDateOfAcceptance__c =
                        parseDate(
                            require(
                                row,
                                'Last Date of Acceptance'
                            )
                        );

                    decision.SignedLetterOfAcceptanceEta__c =
                        parseDate(
                            require(
                                row,
                                'Last Date of Uploading the Signed Letter of Acceptance'
                            )
                        );

                    decision.PaymentOfTheAcceptanceFeeEta__c =
                        parseDate(
                            require(
                                row,
                                'Last Date for Completing the Payment of the Acceptance Fee'
                            )
                        );

                    decision.PaymentOfTheFirstInstallmentEta__c =
                        parseDate(
                            require(
                                row,
                                'Last Date for Completing the Payment of the First Installment'
                            )
                        );

                }

                pending.add(

                    new PendingDecision(
                        row,
                        decision
                    )

                );

            }
            catch (Exception ex) {

                addError(
                    row,
                    ex.getMessage()
                );

            }

        }

        insertAdmissionDecisions(
            pending
        );

    }


    private void insertAdmissionDecisions(
        List<PendingDecision> pending
    ) {

        if (pending.isEmpty()) {
            return;
        }

        List<Admission_Decision__c> decisions =
            new List<Admission_Decision__c>();

        for (PendingDecision item : pending) {
            decisions.add(item.decision);
        }

        Database.SaveResult[] results;
        isCsvImport = true;
        try {
            results = Database.insert(decisions, false);
        } finally {
            isCsvImport = false;
        }

        processInsertResults(
            results,
            pending
        );

    }

    private static String normaliseAdmissionDecision(String value) {
        String normalisedValue = value == null ? '' : value.trim().toLowerCase();

        if (normalisedValue == 'eligible for admission') {
            return 'Eligible for Admission';
        }
        if (normalisedValue == 'waitlisted') {
            return 'Waitlisted';
        }
        if (normalisedValue == 'not eligible') {
            return 'Not Eligible';
        }

        return null;
    }

    private void processInsertResults(
        Database.SaveResult[] results,
        List<PendingDecision> pending
    ) {

        Map<Id, PendingDecision> pendingById =
            new Map<Id, PendingDecision>();

        for (Integer index = 0; index < results.size(); index++) {

            if (results[index].isSuccess()) {

                successCount++;

                pendingById.put(
                    results[index].getId(),
                    pending[index]
                );

            }
            else {

                List<String> messages =
                    new List<String>();

                for (Database.Error error :
                    results[index].getErrors()) {

                    messages.add(
                        error.getMessage()
                    );

                }

                addError(
                    pending[index].row,
                    String.join(messages, '; ')
                );

            }

        }

        addInsertedSuccessRows(
            pendingById
        );

    }

    private void addInsertedSuccessRows(
        Map<Id, PendingDecision> pendingById
    ) {

        if (pendingById.isEmpty()) {
            return;
        }

        for (Admission_Decision__c decision : [

            SELECT
                Id,
                Name

            FROM Admission_Decision__c

            WHERE Id IN :pendingById.keySet()

        ]) {

            addSuccess(

                pendingById.get(
                    decision.Id
                ).row,

                decision

            );

        }

    }

    private void addSuccess(
        Row row,
        Admission_Decision__c decision
    ) {

        List<String> values =
            new List<String>();

        for (String header : successHeaders) {

            if (header == 'Admission Decision Name') {

                values.add(
                    csvValue(
                        decision.Name
                    )
                );

            }
            else {

                values.add(
                    csvValue(
                        row.values.get(header)
                    )
                );

            }

        }

        successRows.add(
            String.join(values, ',')
        );

    }


        /**
     * Adds a row level validation error to the Error CSV.
     */
    private void addError(
        Row row,
        String errorMessage
    ) {

        failedCount++;

        List<String> values = new List<String>();

        for (String header : errorHeaders) {

            if (header == 'Error') {

                values.add(
                    csvValue(errorMessage)
                );

            } else {

                values.add(
                    csvValue(
                        row.values.get(header)
                    )
                );

            }

        }

        errorRows.add(
            String.join(values, ',')
        );

    }

    /**
     * Adds a file level error.
     * Used when the complete CSV cannot be processed
     * (invalid headers, corrupt CSV, etc.).
     */
    private void addFileError(
        String fileName,
        String message
    ) {

        if (errorHeaders.isEmpty()) {
            initialiseHeaders();
        }

        failedCount++;

        List<String> values = new List<String>();

        values.add(csvValue(fileName));

        // Populate remaining columns with blanks
        while (values.size() < errorHeaders.size() - 1) {

            values.add('');

        }

        values.add(
            csvValue(message)
        );

        errorRows.add(
            String.join(values, ',')
        );

    }

    /**
     * Escapes CSV values.
     */
    private static String csvValue(
        Object value
    ) {

        String text =
            value == null
                ? ''
                : String.valueOf(value);

        text = text.replace('"', '""');

        return '"' + text + '"';

    }


        public void finish(Database.BatchableContext context) {

        Id errorVersionId;
        Id successVersionId;

        if (errorRows.size() > 1) {

            ContentVersion errorVersion = new ContentVersion(
                Title = 'AdmissionDecision_Error_' + System.now().getTime(),
                PathOnClient = 'AdmissionDecision_Error.csv',
                VersionData = Blob.valueOf(
                    String.join(errorRows, '\n')
                )
            );

            insert errorVersion;

            errorVersionId = errorVersion.Id;

            errorContentDocumentId =
                [
                    SELECT ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :errorVersionId
                ].ContentDocumentId;

        }

        if (successRows.size() > 1) {

            ContentVersion successVersion = new ContentVersion(
                Title = 'AdmissionDecision_Success_' + System.now().getTime(),
                PathOnClient = 'AdmissionDecision_Success.csv',
                VersionData = Blob.valueOf(
                    String.join(successRows, '\n')
                )
            );

            insert successVersion;

            successVersionId = successVersion.Id;

            successContentDocumentIds.add(

                [
                    SELECT ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :successVersionId
                ].ContentDocumentId

            );

        }

        publishCompletionEvent(
            errorVersionId,
            successVersionId
        );

        if (emailReports) {

            sendCompletionEmail(
                errorVersionId,
                successVersionId
            );

        }

        deleteUploadedChunks();

    }

    private void publishCompletionEvent(
        Id errorVersionId,
        Id successVersionId
    ) {

        Map<String,Object> payload =
            new Map<String,Object>();

        payload.put(
            'hasErrors',
            errorVersionId != null
        );

        if (errorVersionId != null) {

            ContentVersion version =
                [
                    SELECT
                        Id,
                        Title,
                        ContentDocumentId
                    FROM ContentVersion
                    WHERE Id=:errorVersionId
                ];

            payload.put(
                'fileName',
                version.Title + '.csv'
            );

            payload.put(
                'contentDocumentId',
                version.ContentDocumentId
            );

            payload.put(
                'contentVersionId',
                version.Id
            );

        }

        List<Object> successFiles =
            new List<Object>();

        if (successVersionId != null) {

            ContentVersion version =
                [
                    SELECT
                        Id,
                        Title,
                        ContentDocumentId
                    FROM ContentVersion
                    WHERE Id=:successVersionId
                ];

            Map<String,Object> file =
                new Map<String,Object>();

            file.put(
                'name',
                version.Title + '.csv'
            );

            file.put(
                'documentId',
                version.ContentDocumentId
            );

            file.put(
                'contentVersionId',
                version.Id
            );

            successFiles.add(file);

        }

        payload.put(
            'successFiles',
            successFiles
        );

        EventBus.publish(

            new AdmissionConsoleEvent__e(

                Intent__c='AdmissionDecisionImport',

                UserId__c=UserInfo.getUserId(),

                Message__c=JSON.serialize(payload)

            )

        );

    }

    private void sendCompletionEmail(
        Id errorVersionId,
        Id successVersionId
    ) {

        Messaging.SingleEmailMessage email =
            new Messaging.SingleEmailMessage();

        email.setToAddresses(
            new String[]{
                UserInfo.getUserEmail()
            }
        );

        email.setSubject('Admission Decision Import Success/Error CSV Files');

        String body = 'Your Admission Decision import files are ready.\n\n';
        String orgUrl = URL.getOrgDomainUrl().toExternalForm();

        if (errorContentDocumentId != null) {
            body += 'Error CSV: ' + orgUrl +
                '/lightning/r/ContentDocument/' + errorContentDocumentId + '/view\n';
        }

        for (Id successContentDocumentId : successContentDocumentIds) {
            body += 'Success CSV: ' + orgUrl +
                '/lightning/r/ContentDocument/' + successContentDocumentId + '/view\n';
        }

        email.setPlainTextBody(body);

        Messaging.sendEmail(
            new Messaging.SingleEmailMessage[]{
                email
            }
        );

    }

    private void deleteUploadedChunks() {

        if (
            contentVersionIds == null ||
            contentVersionIds.isEmpty()
        ) {
            return;
        }

        List<ContentVersion> versions =
            [
                SELECT Id
                FROM ContentVersion
                WHERE Id IN :contentVersionIds
            ];

        if (!versions.isEmpty()) {

            //delete versions;

        }

    }

}
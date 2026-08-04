public with sharing class ExportUtils {

    public class GeneratedFile {
        public String name;
        public String documentId;

        public GeneratedFile(String name, String documentId) {
            this.name = name;
            this.documentId = documentId;
        }
    }

    public static String csvCell(Object value) {
        if (value == null) {
            return '""';
        }
        return '"' + String.valueOf(value).replace('"', '""') + '"';
    }

    public static String normalize(String value) {
        return value == null ? '' : value.trim().toLowerCase();
    }

    public static String safeFilePart(String value) {
        if (String.isBlank(value)) {
            return 'Export';
        }
        String cleaned = value.replaceAll('[^A-Za-z0-9]+', '_');
        cleaned = cleaned.replaceAll('(^_+|_+$)', '');
        return String.isBlank(cleaned) ? 'Export' : cleaned;
    }

    public static GeneratedFile createCsvFile(String fileNameWithoutExtension, List<String> csvRows, Id batchJobId) {
        if (csvRows == null || csvRows.isEmpty()) {
            return null;
        }

        String csvContent = String.join(csvRows, '\n');

        ContentVersion version = new ContentVersion(
            Title = fileNameWithoutExtension,
            PathOnClient = fileNameWithoutExtension + '.csv',
            VersionData = Blob.valueOf(csvContent)
        );
        insert version;

        version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ];

        insert new Export_Job__c(
            DocumentId__c = version.ContentDocumentId,
            JobId__c = batchJobId,
            Name = fileNameWithoutExtension,
            Status__c = 'Completed'
        );

        return new GeneratedFile(fileNameWithoutExtension + '.csv', version.ContentDocumentId);
    }

    public static void publishExportEvent(String intent, Boolean recordsFound, List<GeneratedFile> generatedFiles) {
        Map<String, Object> payload = new Map<String, Object>();
        List<Object> files = new List<Object>();

        if (generatedFiles != null) {
            for (GeneratedFile f : generatedFiles) {
                files.add(new Map<String, Object>{
                    'name' => f.name,
                    'documentId' => f.documentId
                });
            }
        }

        payload.put('status', recordsFound ? 'Completed' : 'NoRecords');
        payload.put('files', recordsFound ? files : new List<Object>());

        EventBus.publish(new AdmissionConsoleEvent__e(
            UserId__c = UserInfo.getUserId(),
            Intent__c = intent,
            Message__c = JSON.serialize(payload)
        ));
    }

    @AuraEnabled
    public static void sendExportEmail(String filesJson, String exportLabel) {
        if (String.isBlank(filesJson)) {
            return;
        }

        String safeExportLabel = String.isBlank(exportLabel) ? 'Export' : exportLabel;
        List<Object> fileObjects = (List<Object>) JSON.deserializeUntyped(filesJson);

        if (fileObjects.isEmpty()) {
            return;
        }

        String htmlBody = 'Hello ' + escapeHtml(UserInfo.getName()) + '<br/><br/>';
        htmlBody += 'Your ' + escapeHtml(safeExportLabel) + ' has completed successfully.<br/><br/>';
        htmlBody += '<b>Download Files: </b><br/><br/>';

        for (Object obj : fileObjects) {
            Map<String, Object> file = (Map<String, Object>) obj;
            String name = String.valueOf(file.get('name'));
            String documentId = String.valueOf(file.get('documentId'));

            if (String.isBlank(documentId)) {
                continue;
            }

            String downloadUrl = URL.getOrgDomainUrl().toExternalForm()
                + '/sfc/servlet.shepherd/document/download/'
                + EncodingUtil.urlEncode(documentId, 'UTF-8');

            htmlBody += '<a href="' + downloadUrl + '">' + escapeHtml(name) + '</a><br/>';
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[]{ UserInfo.getUserEmail() });
        mail.setSubject(safeExportLabel + ' Completed');
        mail.setHtmlBody(htmlBody);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
    }

    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }
}
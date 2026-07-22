public with sharing class EventMonitoringController {

    public List<EventLogFile> reportExports { get; set; }

    public EventMonitoringController() {
        reportExports = [
            SELECT Id, EventType, LogDate, LogFileLength, LogFile
            FROM EventLogFile
            WHERE EventType = 'ReportExport'
            ORDER BY LogDate DESC
            LIMIT 50
        ];
    }

    // Download the raw CSV log file
    public PageReference downloadLog() {
        Id fileId = ApexPages.currentPage().getParameters().get('id');

        EventLogFile elf = [
            SELECT Id, LogFile
            FROM EventLogFile
            WHERE Id = :fileId
            LIMIT 1
        ];

        // Prepare CSV content
        Blob csv = elf.LogFile;
        String fileName = 'ReportExportLog.csv';

        // Return as downloadable
        PageReference pr = new PageReference('data:text/csv;charset=utf-8,' + EncodingUtil.urlEncode(csv.toString(), 'UTF-8'));
        pr.setRedirect(true);
        return pr;
    }
}
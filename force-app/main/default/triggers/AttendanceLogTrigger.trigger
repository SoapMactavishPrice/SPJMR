trigger AttendanceLogTrigger on Attendance_Log__c (before insert) {
    // Only DIW imports need datetime conversion. UI/integration paths set
    // Log_Date_Time__c directly and skip this trigger entirely.
    //
    // DIW can't reliably parse loose datetime strings (e.g. "10/04/26 10:17")
    // and reads CSV datetimes as UTC regardless of user locale. So imports
    // mark Is_Import__c=TRUE and put the raw string in Log_Date_Time_Raw__c
    // (Text). We parse it here as IST wall-clock and populate Log_Date_Time__c.
    // Expected format: dd/MM/yyyy HH:mm or dd-MM-yyyy HH:mm
    // (seconds optional, 2-digit year ok). The date separator may be '/' or '-';
    // the day-month-year order is the same for both.
    for (Attendance_Log__c record : Trigger.new) {
        if (record.Is_Import__c != true) continue;
        if (String.isBlank(record.Log_Date_Time_Raw__c)) continue;

        try {
            List<String> parts = record.Log_Date_Time_Raw__c.trim().split('\\s+');
            // Support both '/' and '-' as the date separator.
            String datePart = parts[0];
            List<String> d = datePart.contains('/') ? datePart.split('/') : datePart.split('-');
            List<String> t = parts[1].split(':');
            Integer year = Integer.valueOf(d[2]);
            if (year < 100) year += 2000;

            // Build the datetime in GMT from IST components, then shift -5:30
            // so the stored UTC value renders back as the original wall-clock
            // time when displayed in IST.
            DateTime ist = DateTime.newInstanceGmt(
                year,
                Integer.valueOf(d[1]),
                Integer.valueOf(d[0]),
                Integer.valueOf(t[0]),
                Integer.valueOf(t[1]),
                t.size() > 2 ? Integer.valueOf(t[2]) : 0
            );
            record.Log_Date_Time__c = ist.addMinutes(-330);
            record.Is_Import__c = false;
        } catch (Exception e) {
            record.addError(
                'Could not parse Log_Date_Time_Raw__c="' + record.Log_Date_Time_Raw__c +
                '". Expected format: dd/MM/yyyy HH:mm or dd-MM-yyyy HH:mm'
            );
        }
    }
}
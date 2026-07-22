public with sharing class B2CValidationBatch
implements Database.Batchable<String>, Database.Stateful {
    
    private Id contentVersionId;
    private Id campaignId;
    private Integer globalRowCounter = 2;
    private List<B2CRowWrapper> validRows = new List<B2CRowWrapper>();
    private List<String> errorLogs = new List<String>();
    
    
    private String headerError;
    
    public B2CValidationBatch(Id contentVersionId, Id campaignId) {
        this.contentVersionId = contentVersionId;
        this.campaignId = campaignId;
    }
    
    public Iterable<String> start(Database.BatchableContext bc) {
        
        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Id  = :contentVersionId
            LIMIT 1
        ];
        
        String csvString = cv.VersionData.toString();
        List<String> lines = csvString.replace('\r','').split('\n');
        
        if (lines.isEmpty()) {
            headerError = 'File is empty';
            return new List<String>();
        }
        
        String headerLine = lines[0];
        Set<String> expectedHeaders = new Set<String>{
            'name','email','phone','programme','country'
        };
        
        Set<String> actualHeaders = new Set<String>();
        for (String h : headerLine.split(',')) {
            actualHeaders.add(h.trim().toLowerCase().replace('\uFEFF',''));
        }
        
        Set<String> missing = expectedHeaders.clone();
        missing.removeAll(actualHeaders);
        
        if (!missing.isEmpty()) {
            headerError = 'Missing headers: ' + String.join(new List<String>(missing), ', ');
            return new List<String>();
        }
        
        lines.remove(0);
        return lines;
    }
    
    public void execute(Database.BatchableContext bc, List<String> scope) {
        
        Set<String> countries = new Set<String>();
        
        for (String line : scope) {
            if (String.isBlank(line)) continue;
            
            List<String> cols = line.contains('\t') ? line.split('\t') : line.split(',');
            
            if (cols.size() < 5) continue;
            
            String country = clean(cols, 4);
            if (!String.isBlank(country)) {
                countries.add(country.trim());
            }
        }
        
        Map<String, Integer> countryToLength = new Map<String, Integer>();
        
        if (!countries.isEmpty()) {
            for (Country_Master__c cm : [
                SELECT Name, AcceptedNumberLength__c
                FROM Country_Master__c
                WHERE Name IN :countries
            ]) {
                if (cm.AcceptedNumberLength__c != null) {
                    countryToLength.put(
                        cm.Name.toLowerCase(),
                    Integer.valueOf(cm.AcceptedNumberLength__c)
                        );
                }
            }
        }
        
        
        for (String line : scope) {
            
            Integer rowNum = globalRowCounter;
            globalRowCounter++;
            
            if (String.isBlank(line)) continue;
            
            List<String> cols = line.contains('\t') ? line.split('\t') : line.split(',');
            
            if (cols.size() < 5) {
                errorLogs.add('Row ' + rowNum + ': Invalid column structure');
                continue;
            }
            
            B2CRowWrapper row = new B2CRowWrapper();
            
            row.name = clean(cols, 0);
            row.email = clean(cols, 1);
            row.phone = clean(cols, 2);
            row.program = clean(cols, 3);
            row.country = clean(cols, 4);
            
            if (String.isBlank(row.phone) || String.isBlank(row.country)) {
                errorLogs.add('Row ' + rowNum + ': Missing phone or country');
                continue;
            }
            
            String countryKey = row.country.toLowerCase();
            
            if (!countryToLength.containsKey(countryKey)) {
                errorLogs.add('Row ' + rowNum + ': Invalid country - ' + row.country);
                continue;
            }
            
            Integer expectedLength = countryToLength.get(countryKey);
            
            String cleanPhone = row.phone.replaceAll('[^0-9]', '');
            
            if (cleanPhone.length() != expectedLength) {
                errorLogs.add(
                    'Row ' + rowNum + ': Invalid phone length (' + cleanPhone +
                    ') for country ' + row.country +
                    ' expected ' + expectedLength
                    );
                continue;
            }
            
            validRows.add(row);
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        Integer maxErrors = 100;
        String body = '';
        
        if (headerError != null) {
            body += 'HEADER ERROR:\n' + headerError + '\n\n';
        }
        
        List<String> trimmedErrors = new List<String>();
        Integer maxNum = Math.min(maxErrors, errorLogs.size());
        
        for (Integer i = 0; i < maxNum; i++) {
            trimmedErrors.add(errorLogs[i]);
        }
        
        if (!trimmedErrors.isEmpty()) {
            body += 'ROW ERRORS :\n'
                + String.join(trimmedErrors, '\n');
        }
        
        if (errorLogs.size() > maxErrors) {
            body += '\n\n...and ' + (errorLogs.size() - maxErrors) + ' more errors';
        }
        
        if (headerError != null || !errorLogs.isEmpty()) {
            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{UserInfo.getUserEmail()});
            mail.setSubject('B2C Upload Failed - Validation Errors');
            mail.setPlainTextBody(body);
            
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
            
        } else {
            
            Database.executeBatch(
                new B2CImportBatch(validRows, campaignId),
            200
                );
        }
    }
    
    private static String clean(List<String> cols, Integer index) {
        if (cols.size() <= index) return null;
        String val = cols[index];
        if (val == null) return null;
        
        val = val.trim();
        if (val.startsWith('"') && val.endsWith('"')) {
            val = val.substring(1, val.length() - 1);
        }
        
        return val.trim();
    }
}
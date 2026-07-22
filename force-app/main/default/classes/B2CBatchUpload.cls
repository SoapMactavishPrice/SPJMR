public with sharing class B2CBatchUpload 
implements Database.Batchable<String>, Database.Stateful {

    private Id contentVersionId;
    private Id campaignId;

    private String leftover = '';
    private Boolean headerProcessed = false;
    private Integer globalRowCounter = 2;

    private List<String> errorLogs = new List<String>();

    public B2CBatchUpload(Id contentVersionId, Id campaignId) {
        this.contentVersionId = contentVersionId;
        this.campaignId = campaignId;
    }

    public Iterable<String> start(Database.BatchableContext bc) {

        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        String base64Data = EncodingUtil.base64Encode(cv.VersionData);

        Integer chunkSize = 5000000; 
        List<String> chunks = new List<String>();

        for (Integer i = 0; i < base64Data.length(); i += chunkSize) {
            Integer endPos = Math.min(i + chunkSize, base64Data.length());
            chunks.add(base64Data.substring(i, endPos));
        }

        return chunks;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {

        for (String base64Chunk : scope) {

            Blob chunkBlob = EncodingUtil.base64Decode(base64Chunk);
            String chunkString = chunkBlob.toString();

            chunkString = leftover + chunkString;

            List<String> lines = chunkString.split('\n');

            if (!chunkString.endsWith('\n')) {
                leftover = lines.remove(lines.size() - 1);
            } else {
                leftover = '';
            }

            if (!headerProcessed && !lines.isEmpty()) {

                String headerLine = lines.remove(0);

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
                    errorLogs.add('Missing headers: ' + String.join(new List<String>(missing), ', '));
                    return;
                }

                headerProcessed = true;
            }

            processLines(lines);
        }
    }

    private void processLines(List<String> lines) {

        Set<String> countries = new Set<String>();

        for (String line : lines) {
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

        List<B2CRowWrapper> validRows = new List<B2CRowWrapper>();

        for (String line : lines) {

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
                errorLogs.add('Row ' + rowNum + ': Invalid phone length');
                continue;
            }

            validRows.add(row);
        }

        if (!validRows.isEmpty()) {
            insertLeadsAndPrograms(validRows);
        }
    }

    public void finish(Database.BatchableContext bc) {

        if (!errorLogs.isEmpty()) {

            Integer maxErrors = 100;
            List<String> trimmed = new List<String>();

            Integer maxNum = Math.min(maxErrors, errorLogs.size());

            for (Integer i = 0; i < maxNum; i++) {
                trimmed.add(errorLogs[i]);
            }

            String body = 'Errors (showing up to 100):\n' + String.join(trimmed, '\n');

            if (errorLogs.size() > maxErrors) {
                body += '\n\n...and ' + (errorLogs.size() - maxErrors) + ' more errors';
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{UserInfo.getUserEmail()});
            mail.setSubject('B2C Upload Errors');
            mail.setPlainTextBody(body);

            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
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
    
    
    
    private void insertLeadsAndPrograms(List<B2CRowWrapper> scope) {

    Set<String> processedEmails = new Set<String>();
    Set<String> processedPhones = new Set<String>();

    Set<String> emails = new Set<String>();
    Set<String> phones = new Set<String>();
    Set<String> programCodes = new Set<String>();

    for (B2CRowWrapper r : scope) {
        if (!String.isBlank(r.email)) emails.add(r.email.toLowerCase());
        if (!String.isBlank(r.phone)) phones.add(r.phone);
        if (!String.isBlank(r.program)) programCodes.add(r.program.toLowerCase());
    }

    Map<String, Lead> leadByEmail = new Map<String, Lead>();
    Map<String, Lead> leadByPhone = new Map<String, Lead>();

    for (Lead l : [
        SELECT Id, Email, Phone
        FROM Lead
        WHERE Email IN :emails OR Phone IN :phones
    ]) {
        if (l.Email != null) leadByEmail.put(l.Email.toLowerCase(), l);
        if (l.Phone != null) leadByPhone.put(l.Phone, l);
    }

    Map<String, Program> programMap = new Map<String, Program>();
    for (Program p : [
        SELECT Id, Program_Code__c
        FROM Program
        WHERE Program_Code__c IN :programCodes
    ]) {
        programMap.put(p.Program_Code__c.toLowerCase(), p);
    }

    List<Lead> leadsToInsert = new List<Lead>();
    List<Lead_Program__c> lpDraftList = new List<Lead_Program__c>();
    List<CampaignMember> cmToInsert = new List<CampaignMember>();

    Id b2cRecordTypeId = Schema.SObjectType.Lead
        .getRecordTypeInfosByName()
        .get('B2C')
        .getRecordTypeId();

    for (B2CRowWrapper row : scope) {

        String emailKey = row.email != null ? row.email.toLowerCase() : null;
        String phoneKey = row.phone;

        Lead existingLead;

        if (emailKey != null && leadByEmail.containsKey(emailKey)) {
            existingLead = leadByEmail.get(emailKey);
        } else if (phoneKey != null && leadByPhone.containsKey(phoneKey)) {
            existingLead = leadByPhone.get(phoneKey);
        }

        Boolean alreadyProcessed =
            (emailKey != null && processedEmails.contains(emailKey)) ||
            (phoneKey != null && processedPhones.contains(phoneKey));

        if (existingLead == null && !alreadyProcessed) {

            Lead newLead = new Lead(
                LastName = String.isBlank(row.name) ? 'Unknown' : row.name,
                Email = row.email,
                Phone = row.phone,
                RecordTypeId = b2cRecordTypeId
            );

            leadsToInsert.add(newLead);

            if (emailKey != null) processedEmails.add(emailKey);
            if (phoneKey != null) processedPhones.add(phoneKey);
        }

        Program prog = programMap.get(row.program != null ? row.program.toLowerCase() : null);
        if (prog == null) continue;

        lpDraftList.add(new Lead_Program__c(
            Program__c = prog.Id,
            Email__c = row.email,
            Phone__c = row.phone
        ));
    }

    if (!leadsToInsert.isEmpty()) {
        insert leadsToInsert;

        for (Lead l : leadsToInsert) {
            if (l.Email != null) leadByEmail.put(l.Email.toLowerCase(), l);
            if (l.Phone != null) leadByPhone.put(l.Phone, l);
        }
    }

    List<Lead_Program__c> lpToInsert = new List<Lead_Program__c>();

    for (Lead_Program__c lp : lpDraftList) {

        Lead l;

        if (lp.Email__c != null && leadByEmail.containsKey(lp.Email__c.toLowerCase())) {
            l = leadByEmail.get(lp.Email__c.toLowerCase());
        } else if (lp.Phone__c != null && leadByPhone.containsKey(lp.Phone__c)) {
            l = leadByPhone.get(lp.Phone__c);
        }

        if (l != null) {
            lp.Lead__c = l.Id;
            lpToInsert.add(lp);

            if (campaignId != null) {
                cmToInsert.add(new CampaignMember(
                    CampaignId = campaignId,
                    LeadId = l.Id
                ));
            }
        }
    }

    if (!lpToInsert.isEmpty()) insert lpToInsert;
    if (!cmToInsert.isEmpty()) insert cmToInsert;
}
}
public without sharing class B2CImportController {
    public string errorMessage;

private static Map<String,String> validateHeader(String csvData) {

    Map<String,String> errorMap = new Map<String,String>();
   List<String> errors = new List<String>();

    if (String.isBlank(csvData)) {
        errors.add('Empty file');
        errorMap.put('ERROR','Empty file');
        return errorMap;
    }

    List<String> lines = csvData.replace('\r','').split('\n');

    if (lines.isEmpty()) {
        errorMap.put('ERROR','Invalid file format');
        return errorMap;
    }

    String headerLine = lines[0];
    system.debug('Header is  '+headerLine);
    List<String> headers = headerLine.split(',');
    
    Set<String> actualHeaders = new Set<String>();
    for (String h : headers) {
        String cleaned = h.trim().toLowerCase();

    if (cleaned.startsWith('\uFEFF')) {
        cleaned = cleaned.replace('\uFEFF', '');
    }

    actualHeaders.add(cleaned);
        system.debug('Headers From File is '+h);
        System.debug('Header ASCII: ' + EncodingUtil.convertToHex(Blob.valueOf(h)));
        system.debug('Headers From File after trimming and cleaning '+cleaned);
    }

    Set<String> expectedHeaders = new Set<String>{
        'name','email','phone','programme','country','state','city',
        'years of work experience',
        'do you have entrance exam scores?',
        'entrance exam name',
        'spjimr partner company',
        'organization',
        'how did you find out about us?',
        'current designation','age','college','graduation year'
    };

    Set<String> missingHeaders = expectedHeaders.clone();
    missingHeaders.removeAll(actualHeaders);

    for(String header:missingHeaders)
    if (!missingHeaders.isEmpty()) {
        errorMap.put('ERROR','Missing headers: ' + String.join(new List<String>(missingHeaders), ', '));
    }

    if(!errorMap.containsKey('ERROR')) errorMap.put('SUCCESS','File validated successfully');

    return errorMap;
}

    @AuraEnabled
    public static Map<String,String> validateFile(Id contentDocumentId,Id campaignId) {

    List<String> errors = new List<String>();
    Map<String,String> errorMap = new Map<String,String>();

    ContentVersion cv = [
        SELECT Id, VersionData, Title,ContentSize
        FROM ContentVersion
        WHERE ContentDocumentId  = :contentDocumentId
        LIMIT 1
    ];

    if(cv==null){
        errors.add('Could not find content version.');
        errorMap.put('ERROR','Could not find content version.');
        return errorMap;
    }

    // if (cv.ContentSize > 12000000) { 
    //         errorMap.put('ERROR','File larger than 12 MB. Please upload a smaller file.');
    //        // errors.add('File larger than 12 MB. Please upload a smaller file.');
    //         return errorMap;
    //     }

        // String csvString = cv.VersionData.toString();

        // errorMap = validateHeader(csvString);

        // if (!errorMap.isEmpty() && errorMap.containsKey('ERROR')) {
        //     return errorMap; 
        // }
    
        Database.executeBatch(
            new B2CBatchUpload(cv.Id, campaignId),
            200
        );

        return new Map<String,String>{'SUCCESS'=>'File validated successfully'}; 

        // List<String> errors = new List<String>();

        // if (String.isBlank(csvData)) {
        //     errors.add('No file uploaded');
        //     return errors;
        // }

        // List<String> lines = csvData.replace('\r','').split('\n');

        // if (lines.size() <= 1) {
        //     errors.add('No data rows found');
        //     return errors;
        // }

        // // Header validation
        // String header = lines[0];
        // if (!header.contains('Name') || !header.contains('Programme')) {
        //     errors.add('Invalid template format');
        //     return errors;
        // }

        // lines.remove(0);

        // Pattern emailPattern = Pattern.compile('^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+$');

        // // 🔹 Country Map
        // Map<String, Country_Master__c> countryMap = new Map<String, Country_Master__c>();
        // for (Country_Master__c c : [
        //     SELECT Name, AcceptedNumberLength__c
        //     FROM Country_Master__c
        // ]) {
        //     countryMap.put(c.Name.toLowerCase().trim(), c);
        // }

        // // 🔹 Collect Program Codes (RAW, not lowercased)
        // Set<String> programCodes = new Set<String>();

        // for (String line : lines) {
        //     if (String.isBlank(line)) continue;

        //     List<String> cols;
        //     if (line.contains('\t')) {
        //         cols = line.split('\t');
        //     } else {
        //         cols = line.split(',');
        //     }

        //     if (cols.size() > 3) {
        //         programCodes.add(cleanValue(cols[3]));
        //     }
        // }

        // // 🔹 Query Programs
        // Map<String, Program> programMap = new Map<String, Program>();

        // if (!programCodes.isEmpty()) {
        //     for (Program p : [
        //         SELECT Id, Program_Code__c
        //         FROM Program
        //         WHERE Program_Code__c IN :programCodes
        //     ]) {
        //         programMap.put(p.Program_Code__c.toLowerCase().trim(), p);
        //     }
        // }

        // Integer rowNum = 2;

        // // 🔥 Validation Loop
        // for (String line : lines) {

        //     if (String.isBlank(line)) {
        //         rowNum++;
        //         continue;
        //     }

        //     List<String> cols;

        //     if (line.contains('\t')) {
        //         cols = line.split('\t');
        //     } else {
        //         cols = line.split(',');
        //     }

        //     if (cols.size() < 5) {
        //         errors.add('Row ' + rowNum + ': Invalid column structure');
        //         rowNum++;
        //         continue;
        //     }

        //     String email   = cleanValue(cols[1]).toLowerCase();
        //     String phone   = cleanValue(cols[2]);
        //     String program = cleanValue(cols[3]).toLowerCase();
        //     String country = cleanValue(cols[4]).toLowerCase();

        //     // 🔹 Mandatory
        //     if (String.isBlank(phone) || String.isBlank(country)) {
        //         errors.add('Row ' + rowNum + ': Phone and Country are required');
        //         rowNum++;
        //         continue;
        //     }

        //     // 🔹 Program validation
        //     if (!programMap.containsKey(program)) {
        //         errors.add('Row ' + rowNum + ': Invalid program code');
        //     }

        //     // 🔹 Email validation
        //     if (!String.isBlank(email)) {
        //         Matcher m = emailPattern.matcher(email);
        //         if (!m.matches()) {
        //             errors.add('Row ' + rowNum + ': Invalid email format');
        //         }
        //     }

        //     // 🔹 Country validation
        //     Country_Master__c cm = countryMap.get(country);
        //     if (cm == null) {
        //         errors.add('Row ' + rowNum + ': Invalid country');
        //         rowNum++;
        //         continue;
        //     }

        //     // 🔹 Phone length
        //     if (phone.length() != Integer.valueOf(cm.AcceptedNumberLength__c)) {
        //         errors.add('Row ' + rowNum + ': Invalid phone length');
        //     }

        //     rowNum++;
        // }

        // return errors;
    }

    // @AuraEnabled
    // public static void startBatch(String csvData) {
    //     system.debug('Batch execution starts');
    //    Database.executeBatch(
    //     new B2CImportBatch(contentVersionId, campaignId),
    //     200
    // );
    // }

    // private static String cleanValue(String val) {
    //     if (val == null) return '';
    //     val = val.trim();
    //     if (val.startsWith('"') && val.endsWith('"')) {
    //         val = val.substring(1, val.length() - 1);
    //     }
    //     return val.trim();
    // }
}
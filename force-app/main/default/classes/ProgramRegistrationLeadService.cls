/** 
 * Persists program registration form data to Lead using Program_Registration_Field__mdt mappings.
 * When registering for a child Program, pass registrationConfigProgramId as the parent (or form config key)
 * so field and config metadata match the page the user used, while programId remains the target Program for Lead_Program__c.
 */ 
public without sharing class ProgramRegistrationLeadService{
private static Id existingRecordId;
private static String existingRecordType;
    
    @testVisible
    private static ProgramRegistrationFormController.SaveLeadResult errorResult(
    ProgramRegistrationFormController.SaveLeadResult result,
    String message
) {
    result.success = false;
    result.message = message;
    return result;
}
    
    /*
     * 
  
     
    /**
     * Saves registration: Lead/Lead_Program use programId; metadata lookups use registrationConfigProgramId when set, else programId.
     *
     * @param programId Target Program Id for Lead_Program__c (child or parent).
     * @param formValuesJson JSON map of field keys to values from the LWC.
     * @param recaptchaToken Optional reCAPTCHA token when enforced.
     * @param registrationConfigProgramId Program_Id__c key for config/field metadata (e.g. parent when saving a child offering).
     * @return Success flag, Lead Id when inserted, and error message when applicable.
     */
    public static ProgramRegistrationFormController.SaveLeadResult saveRegistration(
        String programId,
        String formValuesJson,
        String recaptchaToken,
        String registrationConfigProgramId,
        Boolean brochureMode
    ) {
        existingRecordId = null;
        existingRecordType = null;
        ProgramRegistrationFormController.SaveLeadResult result = new ProgramRegistrationFormController.SaveLeadResult();
        result.success = false;
		system.debug('JSON is :'+formValuesJson);
        if (String.isBlank(programId)) {
            result.message = 'Program Id is required.';
            return result;
        }
        if (String.isBlank(formValuesJson)) {
            result.message = 'Form data is required.';
            return result;
        }

        String configProgramKey = String.isNotBlank(registrationConfigProgramId)
            ? registrationConfigProgramId.trim()
            : programId.trim();

        Map<String, Object> formValues;
        try {
            formValues = (Map<String, Object>) JSON.deserializeUntyped(formValuesJson);
        } catch (Exception e) {
            result.message = 'Invalid form data.';
            return result;
        }

        List<Program_Registration_Config__mdt> configs = [
            SELECT
                Program_Id__c,
                Recaptcha_Site_Key__c,
                Lead_Record_Type_Developer_Name__c,
                Default_Lead_Source__c,
                Lead_Default_Status__c
            FROM Program_Registration_Config__mdt
            WHERE Program_Id__c = :configProgramKey
            LIMIT 1
        ]; 

        if (configs.isEmpty()) {
            result.message = 'Program configuration not found.';
            return result;
        }

        Program_Registration_Config__mdt cfg = configs[0];

        if (String.isNotBlank(cfg.Recaptcha_Site_Key__c)) {
            if (String.isBlank(recaptchaToken)) {
                result.message = 'reCAPTCHA verification is required.';
                return result;
            }
            Map<String, Object> verifyResult = ProgramRegistrationFormController.verifyToken(recaptchaToken);
            Object ok = verifyResult != null ? verifyResult.get('success') : null;
            if (verifyResult == null || !(ok instanceof Boolean) || (Boolean) ok != true) {
                //result.message = verifyResult != null ? (String) verifyResult.get('message') : null;
                if (String.isBlank(result.message)) {
                  //  result.message = 'reCAPTCHA verification failed.';
                }
               // return result;
            }
        }

        List<Program_Registration_Field__mdt> fieldDefsRaw = [
            SELECT
                Field_Key__c,
                Field_Type__c,
                Required__c,
                Label__c,
                Lead_Field_API_Name__c,
                Visible_When_Field_Key__c,
                Visible_When_Value__c,
                Is_Brochure_Field__c
            FROM Program_Registration_Field__mdt
            WHERE Program_Id__c = :configProgramKey
            ORDER BY Layout_Row__c NULLS LAST, Display_Order__c ASC
        ];
        List<Program_Registration_Field__mdt> fieldDefs = filterFieldDefsForBrochureMode(fieldDefsRaw, brochureMode);

        List<String> validationErrors = new List<String>();
        for (Program_Registration_Field__mdt fd : fieldDefs) {
            if (fd.Required__c != true) {
                continue;
            }
            if (!isFieldVisible(fd, formValues)) {
                continue;
            }
            Object raw = formValues.get(fd.Field_Key__c);
            if (isEmptyValue(raw, fd.Field_Type__c)) {
                validationErrors.add(
                    String.isNotBlank(fd.Label__c) ? fd.Label__c + ' is required' : fd.Field_Key__c + ' is required'
                );
            }
        }
		system.debug('Validation Error is: '+validationErrors);
        if (!validationErrors.isEmpty()) {
            result.message = validationErrors[0];
            return result;
        }

        // Registration programId (custom metadata) matches Program__c.Program_Code__c (see LeadPublicAPIService).
        String programCode = programId.trim();
        List<Program> programRows = [
            SELECT Id, Name, Program_Code__c
            FROM Program
            WHERE Id = :programCode
            LIMIT 1
        ];
        if (programRows.isEmpty()) {
             return errorResult(result,'No Program found with Program_Code__c \'' +programCode +'\'. Create or align the Program record with this registration id.');
            
        }
        Id programSfId = programRows[0].Id;
        //Change
        String programName = programRows[0].Name;
        String programCodeForApplication = programRows[0].Program_Code__c;
        Lead lead = new Lead();
        String rtDevName = String.isNotBlank(cfg.Lead_Record_Type_Developer_Name__c)
            ? cfg.Lead_Record_Type_Developer_Name__c.trim()
            : 'B2C';
        try {
            lead.RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get(rtDevName).getRecordTypeId();
        } catch (Exception e) {
            return errorResult(result,'Lead record type not found: ' + rtDevName);
        }

        String statusVal = String.isNotBlank(cfg.Lead_Default_Status__c) ? cfg.Lead_Default_Status__c.trim() : 'Untouched';
        lead.Status = statusVal;

        if (String.isNotBlank(cfg.Default_Lead_Source__c)) {
            lead.LeadSource = cfg.Default_Lead_Source__c.trim();
        }

        Map<String, Schema.SObjectField> leadFieldMap = Schema.SObjectType.Lead.fields.getMap();
        Map<String, Integer> mergeFieldCountByKey = buildMergeFieldCountByMapKey(fieldDefs, leadFieldMap);
        Map<String, List<String>> valuesByApi = new Map<String, List<String>>();

        for (Program_Registration_Field__mdt fd : fieldDefs) {
            if (!isFieldVisible(fd, formValues)) {
                continue;
            }
            String ft = fd.Field_Type__c != null ? fd.Field_Type__c.toLowerCase() : '';
            if ('password'.equals(ft) || 'captcha'.equals(ft)) {
                continue;
            }
            if (String.isBlank(fd.Lead_Field_API_Name__c)) {
                continue;
            }

            String apiName = fd.Lead_Field_API_Name__c.trim();
            Object raw = formValues.get(fd.Field_Key__c);

            if (
                'full_name'.equalsIgnoreCase(fd.Field_Key__c) &&
                'FirstName'.equalsIgnoreCase(apiName)
            ) {
                String full = raw != null ? String.valueOf(raw).trim() : '';
                if (String.isNotBlank(full)) {
                    List<String> parts = full.split('\\s+', 2);
                    lead.FirstName = parts[0];
                    lead.LastName = parts.size() > 1 ? parts[1] : '.';
                }
                continue;
            }

            // getMap() keys are lowercase; metadata often uses PascalCase (Email vs email).
            String fieldMapKey = resolveLeadFieldMapKey(leadFieldMap, apiName);
            if (fieldMapKey == null) {
                continue;
            }
            Schema.DescribeFieldResult dfr = leadFieldMap.get(fieldMapKey).getDescribe();
            if (dfr.isCalculated()) {
                continue;
            }

            if (dfr.getType() == Schema.DisplayType.BOOLEAN) {
                putLeadValue(lead, dfr, raw);
                continue;
            }

            if (raw == null) {
                continue;
            }
            String asText;
            if (raw instanceof Boolean) {
                asText = ((Boolean) raw) ? 'Yes' : 'No';
            } else {
                asText = String.valueOf(raw).trim();
            }
            if (String.isBlank(asText)) {
                continue;
            }

            // One form field → one Lead field (Email, City, Phone): store value only. Several fields → same Lead
            // (often Description): "Label: value" lines so they stay readable when merged.
            Integer mergeCount = mergeFieldCountByKey.get(fieldMapKey);
            Boolean labeledMerge = mergeCount != null && mergeCount > 1;
            String labelPart = String.isNotBlank(fd.Label__c) ? fd.Label__c : fd.Field_Key__c;
            String line =
                labeledMerge && String.isNotBlank(labelPart) ? labelPart + ': ' + asText : asText;

            if (!valuesByApi.containsKey(fieldMapKey)) {
                valuesByApi.put(fieldMapKey, new List<String>());
            }
            valuesByApi.get(fieldMapKey).add(line);
        }

        for (String fieldMapKey : valuesByApi.keySet()) {
            Schema.DescribeFieldResult dfr = leadFieldMap.get(fieldMapKey).getDescribe();
            List<String> parts = valuesByApi.get(fieldMapKey);
            String merged = String.join(parts, '\n');
            putLeadValue(lead, dfr, merged);
        }

        if (String.isBlank(lead.LastName)) {
            lead.LastName = '.';
        }
        if (String.isBlank(lead.Company)) {
            String fn = String.isNotBlank(lead.FirstName) ? lead.FirstName : 'Lead';
            String ln = String.isNotBlank(lead.LastName) ? lead.LastName : '';
            lead.Company = (fn + ' ' + ln).trim() + ' (Individual)';
        }

                    if (lead.Country_Master_backend__c != null) {
                List<Country_Master__c> countries = [
                    SELECT Name
                    FROM Country_Master__c
                    WHERE Id = :lead.Country_Master_backend__c
                    LIMIT 1
                ];
                if (!countries.isEmpty()) {
                    lead.Country = countries[0].Name;
                }
            }

            if (lead.State_Master__c != null) {
                List<State__c> states = [
                    SELECT Name
                    FROM State__c
                    WHERE Id = :lead.State_Master__c
                    LIMIT 1
                ];
                if (!states.isEmpty()) {
                    lead.State = states[0].Name;
                }
            }

            if (lead.District_City__c != null) {
                List<City__c> cities = [
                    SELECT Name
                    FROM City__c
                    WHERE Id = :lead.District_City__c
                    LIMIT 1
                ];
                if (!cities.isEmpty()) {
                    lead.City = cities[0].Name;
                }
            }

        String phoneValidationError = validatePhoneAgainstCountryRule(lead);
        system.debug('Phone Validation: '+phoneValidationError);
        if (String.isNotBlank(phoneValidationError)) {
            result.message = phoneValidationError;
            return result;
        }

        Savepoint sp = Database.setSavepoint();
        try {
            //Change
                            Integer existingStatus = handleExistingRecords(
                    lead,
                    programSfId,
                    programName,
                    programCodeForApplication,
                    cfg 
                );

                if (existingStatus == 2) {
                    result.success = true;
                    result.alreadyRegistered = true;
                    result.leadOrAccountId = existingRecordId;
                    result.leadOrAccountType = existingRecordType;
                    result.message = 'Your email ID is already registered with us. '+ 
                    'Click here to receive your credentials email and proceed with your application.';
                    return result;
                }


                if (existingStatus == 3) {
                    result.success = true;
                    result.alreadyRegistered = true;
                    result.existingStatus='3';
                    result.message = 'Your mobile number is already registered with another email ID. '+
                    'Please use a different mobile number to register';
                    return result;
                }

                if (existingStatus == 1) {
                    result.success = true;
                    result.message = 'Registration Successful .Please check your email inbox.';
                    return result;
                }
            createLeadAndProgram(lead, programSfId, cfg);
            /*insert lead;

            Lead_Program__c leadProgram = new Lead_Program__c(
                Lead__c = lead.Id,
                Program__c = programSfId
            );
            if (String.isNotBlank(cfg.Default_Lead_Source__c)) {
                leadProgram.Lead_Source__c = cfg.Default_Lead_Source__c.trim();
            }
            if (String.isNotBlank(lead.Email)) {
                leadProgram.Email__c = lead.Email;
            }
            if (String.isNotBlank(lead.Phone)) {
                leadProgram.Phone__c = lead.Phone;
            }
            insert leadProgram;*/
        } catch (DmlException e) {
            Database.rollback(sp);
            return errorResult(result, e.getDmlMessage(0));
        }

        result.success = true;
        result.leadId = lead.Id;
        result.message = 'Registration Successful. Please check your email inbox.';
        return result;
    }

    /**
     * How many form fields (excluding full_name→FirstName, booleans on Lead, password/captcha)
     * map to each Lead field. Used to decide labeled vs raw merge text.
     */
    @TestVisible
    private static Map<String, Integer> buildMergeFieldCountByMapKey(
        List<Program_Registration_Field__mdt> fieldDefs,
        Map<String, Schema.SObjectField> leadFieldMap
    ) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (Program_Registration_Field__mdt fd : fieldDefs) {
            if (String.isBlank(fd.Lead_Field_API_Name__c)) {
                continue;
            }
            String ft = fd.Field_Type__c != null ? fd.Field_Type__c.toLowerCase() : '';
            if ('password'.equals(ft) || 'captcha'.equals(ft)) {
                continue;
            }
            String apiName = fd.Lead_Field_API_Name__c.trim();
            if ('full_name'.equalsIgnoreCase(fd.Field_Key__c) && 'FirstName'.equalsIgnoreCase(apiName)) {
                continue;
            }
            String fieldMapKey = resolveLeadFieldMapKey(leadFieldMap, apiName);
            if (fieldMapKey == null) {
                continue;
            }
            Schema.DescribeFieldResult dfr = leadFieldMap.get(fieldMapKey).getDescribe();
            if (dfr.isCalculated()) {
                continue;
            }
            if (dfr.getType() == Schema.DisplayType.BOOLEAN) {
                continue;
            }
            Integer n = counts.get(fieldMapKey);
            counts.put(fieldMapKey, n == null ? 1 : n + 1);
        }
        return counts;
    }

    /**
     * Lead.fields.getMap() uses lowercase keys; metadata may use mixed case.
     */
    @TestVisible
    private static String resolveLeadFieldMapKey(Map<String, Schema.SObjectField> leadFieldMap, String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        String trimmed = apiName.trim();
        if (leadFieldMap.containsKey(trimmed)) {
            return trimmed;
        }
        String lower = trimmed.toLowerCase();
        if (leadFieldMap.containsKey(lower)) {
            return lower;
        }
        return null;
    }

    /**
     * Aligns save-time field set with {@link ProgramRegistrationFormController#getFormConfiguration}: brochure vs standard rows only.
     */
    private static List<Program_Registration_Field__mdt> filterFieldDefsForBrochureMode(
        List<Program_Registration_Field__mdt> raw,
        Boolean brochureMode
    ) {
        List<Program_Registration_Field__mdt> out = new List<Program_Registration_Field__mdt>();
        if (raw == null || raw.isEmpty()) {
            return out;
        }
        Boolean brochureOnly = brochureMode == true;
        for (Program_Registration_Field__mdt fd : raw) {
            Boolean isBrochureField = fd.Is_Brochure_Field__c == true;
            if (brochureOnly) {
                if (!isBrochureField) {
                    continue;
                }
            } else if (isBrochureField) {
                continue;
            }
            out.add(fd);
        }
        return out;
    }

    private static Boolean isFieldVisible(Program_Registration_Field__mdt fd, Map<String, Object> formValues) {
        if (String.isBlank(fd.Visible_When_Field_Key__c)) {
            return true;
        }
        Object v = formValues.get(fd.Visible_When_Field_Key__c);
        String expected = fd.Visible_When_Value__c;
        return v != null && String.valueOf(v).equals(expected);
    }

    private static Boolean isEmptyValue(Object raw, String fieldType) {
        String ft = fieldType != null ? fieldType.toLowerCase() : '';
        if ('checkbox'.equals(ft)) {
            return raw == null || raw == false;
        }
        if (raw == null) {
            return true;
        }
        if (raw instanceof Boolean) {
            return false;
        }
        return String.isBlank(String.valueOf(raw));
    }
	@TestVisible
    private static void putLeadValue(Lead lead, Schema.DescribeFieldResult dfr, Object raw) {
        if (raw == null) {
            return;
        }
        String name = dfr.getName();
        Schema.DisplayType t = dfr.getType();

        if (t == Schema.DisplayType.BOOLEAN) {
            if (raw instanceof Boolean) {
                lead.put(name, (Boolean) raw);
            } else {
                String s = String.valueOf(raw).trim();
                lead.put(name, 'true'.equalsIgnoreCase(s) || '1'.equals(s));
            }
            return;
        }

        String s = String.valueOf(raw).trim();
        if (String.isBlank(s)) {
            return;
        }

        switch on t {
            when INTEGER {
                lead.put(name, Integer.valueOf(Decimal.valueOf(s).intValue()));
            }
            when DOUBLE, CURRENCY, PERCENT {
                lead.put(name, Decimal.valueOf(s));
            }
            when DATE {
                lead.put(name, Date.valueOf(s));
            }
            when DATETIME {
                lead.put(name, DateTime.valueOf(s.replace('T', ' ')));
            }
            when else {
                lead.put(name, s);
            }
        }
    }

    @TestVisible
    private static String formatAlternatePhone(Id countryId, String phone) {
    if (String.isBlank(phone)) {
        return null;
    }

    String phoneDigits = digitsOnly(phone);

    if (countryId == null) {
        return phone;
    }

    List<Country_Master__c> countries = [
        SELECT Country_Code__c
        FROM Country_Master__c
        WHERE Id = :countryId
        LIMIT 1
    ];

    if (countries.isEmpty() ||
        String.isBlank(countries[0].Country_Code__c)) {
        return phone;
    }

    String countryCode = digitsOnly(countries[0].Country_Code__c);

    // Remove country code if already present
    if (phoneDigits.startsWith(countryCode)) {
        phoneDigits = phoneDigits.substring(countryCode.length());
    }

    return '+' + countryCode + ' ' + phoneDigits;
}

@TestVisible
   private static Integer handleExistingRecords(
    Lead lead,
    Id programId,
    String programName,
    String programCode,
    Program_Registration_Config__mdt cfg
) {
    String email = normalizeEmail(lead.Email);
    String phoneRaw = lead.Phone != null ? lead.Phone.trim() : null;
    String phoneDigits = normalizePhone(phoneRaw);
    String leadSource = cfg.Default_Lead_Source__c;
	system.debug('Email:::: '+email);
    if (String.isBlank(email)) {
        return 0;
    }

    List<Account> emailAccounts = new List<Account>();

    if (String.isNotBlank(email)) {
        emailAccounts = [
            SELECT
                Id,
                FirstName,
                LastName,
                PersonEmail,
                PersonMobilePhone,
                PersonOtherPhone,
                Phone,
                Country_Master__c
            FROM Account
            WHERE PersonEmail = :email
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }
    //Match by Email
     if (!emailAccounts.isEmpty()) {
        Account acc = emailAccounts[0];

        existingRecordId = acc.Id;
        existingRecordType = 'Account';

        /*
         * The email already belongs to this account.
         *
         * If the incoming phone is a new phone and PersonOtherPhone
         * is empty, store it as the alternate phone.
         */
        Boolean alternatePhoneUpdated = false;
        if (String.isNotBlank(phoneDigits)) {
            String accountPhoneDigits = normalizePhone(acc.Phone);
            String mobilePhoneDigits = normalizePhone(acc.PersonMobilePhone);
            String otherPhoneDigits = normalizePhone(acc.PersonOtherPhone);

            Boolean phoneAlreadyExists =
                phoneDigits == accountPhoneDigits ||
                phoneDigits == mobilePhoneDigits ||
                phoneDigits == otherPhoneDigits;

            Boolean hasProgram = [
        SELECT COUNT()
        FROM Opportunity
        WHERE AccountId = :acc.Id
        AND Program__c = :programId
    ] > 0;

            if (hasProgram && !phoneAlreadyExists && String.isBlank(acc.PersonOtherPhone)) {
                String alternatePhone = formatAlternatePhone(
                    lead.Country_Master_backend__c,
                    phoneRaw
                );

                if (String.isNotBlank(alternatePhone)) {
                    update new Account(
                        Id = acc.Id,
                        PersonOtherPhone = alternatePhone
                    );
                    alternatePhoneUpdated = true;
                }
            }
        }

        Boolean created = createOpportunityAndApplicationIfMissing(
            acc.Id,
            programId,
            programName,
            programCode,
            leadSource,
            String.isNotBlank(lead.FirstName) ? lead.FirstName : acc.FirstName,
            String.isNotBlank(lead.LastName) ? lead.LastName : acc.LastName,
            email,
            phoneRaw
        );
        if (alternatePhoneUpdated) {
            return 1;
        }
        
        return 2;
    }

    //Match by Phone
    if (String.isNotBlank(phoneDigits)) {
        List<Account> phoneAccounts = [
            SELECT
                Id,
                FirstName,
                LastName,
                PersonEmail,
                PersonMobilePhone,
                PersonOtherPhone,
                Phone,
                Country_Master__c
            FROM Account
            WHERE
                PersonMobilePhone = :phoneRaw
                OR PersonMobilePhone = :phoneDigits
                // OR PersonOtherPhone = :phoneRaw
                // OR PersonOtherPhone = :phoneDigits
                OR Phone = :phoneRaw
                OR Phone = :phoneDigits
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];

        for (Account acc : phoneAccounts) {
            String accountPhoneDigits = normalizePhone(acc.Phone);
            String mobilePhoneDigits = normalizePhone(acc.PersonMobilePhone);
            String otherPhoneDigits = normalizePhone(acc.PersonOtherPhone);

            Boolean phoneMatches =
                phoneDigits == accountPhoneDigits || phoneDigits == mobilePhoneDigits || phoneDigits == otherPhoneDigits;

            if (phoneMatches) {
                existingRecordId = acc.Id;
                existingRecordType = 'Account';

                return 3;
            }
        }
    }
    // 2) If Account exists by email: create Opportunity for new program.
    // List<Account> accList = [
    //     SELECT Id, FirstName, LastName,PersonOtherPhone,PersonMobilePhone,Country_Master__c,Phone,PersonEmail
    //     FROM Account
    //     WHERE (PersonEmail = :email
    //     OR PersonMobilePhone=:phoneRaw
    //     OR PersonMobilePhone=:phoneDigits
    //     OR Phone=:phoneRaw OR Phone=:phoneDigits)
    //     ORDER BY CreatedDate DESC
    //     LIMIT 1
    // ];
    // if (!accList.isEmpty()) {
    //     Account acc = accList[0];
    //     existingRecordId = acc.Id;
    //     existingRecordType = 'Account';
    //    Boolean created = createOpportunityAndApplicationIfMissing(
    //         acc.Id,
    //         programId,
    //         programName,
    //         programCode,
    //         leadSource,
    //         String.isNotBlank(lead.FirstName) ? lead.FirstName : acc.FirstName,
    //         String.isNotBlank(lead.LastName) ? lead.LastName : acc.LastName,
    //         email,
    //         phoneRaw
    //     );
    //     if(acc.Phone!=phoneRaw || acc.Phone!=phoneDigits){
    //         if(acc.PersonOtherPhone==null){
    //             String alternatePhone = formatAlternatePhone(acc.Country_Master__c, phoneRaw);
    //             Update new Account(Id=acc.Id,PersonOtherPhone = alternatePhone);   
    //         }

    //     }
    //     if(acc.PersonEmail == email){
    //         return 2;
    //     }
    //     if(acc.PersonMobilePhone==phoneRaw || acc.PersonMobilePhone==phoneDigits ||
    //     acc.Phone==phoneRaw || acc.Phone==phoneDigits){
    //         return 3;
    //     }
    // existingRecordId = acc.Id;
    // existingRecordType = 'Account';

    //     return 2;
    // }

    // 1) If unconverted Lead exists by email: create Lead Program only.
      /*
     * SCENARIO 2 / 3
     * Same email already exists.
     */
    List<Lead> leadList = [
        SELECT Id, Email, Phone, FirstName, 
        LastName, IsConverted, ConvertedAccountId,AlternateContactNumber__c
        FROM Lead
        WHERE (Email = :email)// OR Phone=:phoneRaw OR Phone=:phoneDigits)
          AND IsConverted = false
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];

    if (!leadList.isEmpty()) {
        Lead existingLead = leadList[0];
        Boolean hasProgram = [
        SELECT COUNT()
        FROM Lead_Program__c
        WHERE Lead__c = :existingLead.Id
        AND Program__c = :programId
    ] > 0;
        
    if (!hasProgram) {
        // Email is same, but this is a NEW program.
        // Create another Lead Program under the existing Lead.
        createLeadProgram(
            existingLead.Id,
            programId,
            email,
            phoneRaw,
            cfg
        );

        return 1;
    }

    
        String existingPhoneDigits =
            normalizePhone(existingLead.Phone);

        if (existingPhoneDigits == phoneDigits || existingPhoneDigits == phoneRaw) {
                    existingRecordId = existingLead.Id;
                    existingRecordType = 'Lead';
                    return 2;
                }
                if (String.isBlank(existingLead.AlternateContactNumber__c)) {
                    String alternatePhone = formatAlternatePhone(
                lead.Country_Master_backend__c,
                phoneRaw
            );
            update new Lead(
                Id = existingLead.Id,
                AlternateContactNumber__c = alternatePhone
            );
            return 1;
        }

        existingRecordId = existingLead.Id;
        existingRecordType = 'Lead';

         return 2;
       
    }

    List<Lead> phoneLeads = [
        SELECT Id, Email, Phone
        FROM Lead
        WHERE IsConverted = false
        AND (
            Phone = :phoneRaw
            OR Phone = :phoneDigits
        )
        ORDER BY CreatedDate ASC
        LIMIT 1
    ];

    if (!phoneLeads.isEmpty()) {
        return 3;
    }


    

    return 0;
}




@TestVisible
private static Boolean leadProgramExists(
    Id leadId,
    Id programId,
    String email,
    String phoneRaw,
    String phoneDigits,
    String leadSource
) {
    String likeDigits = String.isNotBlank(phoneDigits) ? '%' + phoneDigits : null;
    List<Lead_Program__c> lp = [
        SELECT Id
        FROM Lead_Program__c
        WHERE Lead__c = :leadId
        AND Program__c = :programId
        AND Email__c = :email
        AND (
            Phone__c = :phoneRaw
            OR Phone__c = :phoneDigits
            OR Phone__c LIKE :likeDigits
        )
        AND Lead_Source__c = :leadSource
        LIMIT 1
    ];

    return !lp.isEmpty();
}

private static void createLeadProgram(
    Id leadId,
    Id programId,
    String email,
    String phone,
    Program_Registration_Config__mdt cfg
) {
    Lead_Program__c lp = new Lead_Program__c(
        Lead__c = leadId,
        Program__c = programId,
        Email__c = email,
        Phone__c = phone
    );

    if (String.isNotBlank(cfg.Default_Lead_Source__c)) {
        lp.Lead_Source__c = cfg.Default_Lead_Source__c.trim();
    }

    insert lp;
}

@TestVisible
private static Boolean leadProgramExists(
    Id leadId,
    Id programId
) {
    return [
        SELECT COUNT()
        FROM Lead_Program__c
        WHERE Lead__c = :leadId
        AND Program__c = :programId
    ] > 0;
}

@TestVisible
private static Boolean createOpportunityAndApplicationIfMissing(
    Id accountId,
    Id programId,
    String programName,
    String programCode,
    String leadSource,
    String firstName,
    String lastName,
    String email,
    String phone
) {
    if (accountId == null || programId == null) {
        return false;
    }

    Id reusableApplicationId = B2CProgramParentHelper.findReusableApplicationForParentFamily(
        accountId,
        programId
    );
    if (reusableApplicationId != null) {
        String fn = String.isNotBlank(firstName) ? firstName.trim() : 'Applicant';
        String ln = String.isNotBlank(lastName) ? lastName.trim() : '';
        String pName = String.isNotBlank(programName) ? programName.trim() : 'Program';

        Opportunity newOpp = new Opportunity();
        newOpp.AccountId = accountId;
        newOpp.Program__c = programId;
        newOpp.Name = (fn + ' ' + ln).trim() + ' - ' + pName;
        newOpp.StageName = 'Prospecting';
        newOpp.CloseDate = Date.today().addDays(90);
        newOpp.Application__c = reusableApplicationId;
        if (String.isNotBlank(leadSource)) {
            newOpp.LeadSource = leadSource.trim();
        }
        Schema.RecordTypeInfo b2cOppRti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('B2C_Opportunity');
        if (b2cOppRti != null) {
            newOpp.RecordTypeId = b2cOppRti.getRecordTypeId();
        }
        insert newOpp;
        UpdateUserRecord(accountId);
        return true;
    }

    List<Opportunity> existingOpp = [
        SELECT Id, Application__c
        FROM Opportunity
        WHERE AccountId = :accountId
          AND Program__c = :programId
        LIMIT 1
    ];

    Opportunity opp;
    if (!existingOpp.isEmpty()) {
        return false;
    } else {
        String fn = String.isNotBlank(firstName) ? firstName.trim() : 'Applicant';
        String ln = String.isNotBlank(lastName) ? lastName.trim() : '';
        String pName = String.isNotBlank(programName) ? programName.trim() : 'Program';

        opp = new Opportunity();
        opp.AccountId = accountId;
        opp.Program__c = programId;
        opp.Name = (fn + ' ' + ln).trim() + ' - ' + pName;
        opp.StageName = 'Prospecting';
        opp.CloseDate = Date.today().addDays(90);
        if (String.isNotBlank(leadSource)) {
            opp.LeadSource = leadSource.trim();
        }
        Schema.RecordTypeInfo b2cOppRti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('B2C_Opportunity');
        if (b2cOppRti != null) {
            opp.RecordTypeId = b2cOppRti.getRecordTypeId();
        }
        insert opp;
        UpdateUserRecord(accountId);
    }
 List<User> applicantUserList = [SELECT Id,Programs_Applied__c FROM User WHERE ContactId IN (SELECT PersonContactId 
                    FROM Account 
                    WHERE Id = :accountId)];
     String userId = applicantUserList[0].Id;
    
     
    if (opp.Application__c == null) {
        Application__c app = new Application__c();
        app.Applicant__c = accountId;
        app.Program__c = programId;
        app.OwnerId = userId;
        app.LeadSource__c = leadSource;
        
        if (String.isNotBlank(programCode)) {
            List<String> applicationNumbers = ConvertB2CLeadController.generateApplicationNumbersInBulk(
                new List<String>{ programCode }
            );
            if (!applicationNumbers.isEmpty() && String.isNotBlank(applicationNumbers[0])) {
                app.Name = applicationNumbers[0];
            }
        }

        insert app;
        insertApplicationRelatedRecordsFromAccount(new List<Application__c>{app},accountId,userId);
        update new Opportunity(
            Id = opp.Id,
            Application__c = app.Id
        );
    }

    return true;
}


@TestVisible
private static void UpdateUserRecord(Id accountId){
    List<Contact> applicantCon = [SELECT Id FROM Contact WHERE AccountId=:accountId LIMIT 1];
    
    List<User> applicantUserList = [SELECT Id,Programs_Applied__c FROM User WHERE ContactId IN (SELECT PersonContactId 
                    FROM Account 
                    WHERE Id = :accountId)];
     String userId = applicantUserList[0].Id;
    if(userId!=null){
        List<Opportunity> OppList = [SELECT Id,Program__r.Name 
        FROM Opportunity WHERE AccountId=:accountId];
        Set<String> programNames = new Set<String>();
        for(Opportunity opp:OppList){
            if(String.IsNotBlank(opp.Program__r.Name )){
                programNames.add(opp.Program__r.Name);
            }
        }
        List<String> programNameList = new List<String>(programNames);
       String formattedProgrammeNames = ApplicantWelcomeEmailQueue.formatProgrammeList(programNameList);
       //Update new User(Programs_Applied__c=formattedProgrammeNames,Id=userId);
       Update new Contact(Id=applicantCon[0].Id,Programs_Applied__c=formattedProgrammeNames);
    }

}

 private static void insertApplicationRelatedRecordsFromAccount(
        List<Application__c> applications,
        Id accountRecordId,
        String UserId
    ) {
        List<Personal_Detail__c> personalDetails = new List<Personal_Detail__c>();
       List<Account> accList = [SELECT Id,FirstName,LastName,
       PersonEmail,PersonMobilePhone,Phone FROM Account WHERE Id =:accountRecordId LIMIT 1]; 
        Account accountRecord = accList[0];
        for (Application__c app : applications) {
            Personal_Detail__c pd = new Personal_Detail__c();
            pd.Application__c = app.Id;
            pd.First_Name__c = accountRecord.FirstName;
            pd.Last_Name__c = accountRecord.LastName;
            pd.Primary_E_mail__c = accountRecord.PersonEmail;
            pd.Mobile_Number__c = String.isNotBlank(accountRecord.PersonMobilePhone) ? accountRecord.PersonMobilePhone : accountRecord.Phone;
            pd.Age_as_on_Customisable_Date__c = null;
            pd.OwnerId = UserId;
            personalDetails.add(pd);
        }

        if (!personalDetails.isEmpty()) {
            insert personalDetails;
        }
        
    }

private static String normalizeEmail(String email) {
    return email != null ? email.trim().toLowerCase() : null;
}

private static String normalizePhone(String phone) {
    return phone != null ? phone.replaceAll('[^0-9]', '') : null;
}
@TestVisible
private static String validatePhoneAgainstCountryRule(Lead lead) {
    if (lead == null || String.isBlank(lead.Phone) || lead.Country_Master_backend__c == null) {
        return null;
    }

    List<Country_Master__c> rows = [
        SELECT Id, Name, Country_Code__c, AcceptedNumberLength__c
        FROM Country_Master__c
        WHERE Id = :lead.Country_Master_backend__c
        LIMIT 1
    ];
    if (rows.isEmpty()) {
        return null;
    }
    Country_Master__c country = rows[0];
    if (String.isBlank(country.AcceptedNumberLength__c)) {
        return null;
    }

    if (String.isNotBlank(lead.Phone) && country != null) {
    if (String.isNotBlank(country.Country_Code__c)) {
        String phone = digitsOnly(lead.Phone);
        String countryCode = country.Country_Code__c.trim();

        // Avoid duplicating the country code
        if (!phone.startsWith(digitsOnly(countryCode))) {
            lead.Phone = '+'+countryCode + ' ' + phone;
        } else {
            lead.Phone =  '+'+countryCode + ' ' + phone.substring(digitsOnly(countryCode).length());
        }
    }
}

    Set<Integer> accepted = parseAcceptedLengths(country.AcceptedNumberLength__c);
    if (accepted.isEmpty()) {
        return null;
    }

    String phoneDigits = digitsOnly(lead.Phone);
    if (String.isBlank(phoneDigits)) {
        return null;
    }

    Integer localLen = phoneDigits.length();
    String countryCodeDigits = digitsOnly(country.Country_Code__c);
    if (String.isNotBlank(countryCodeDigits) &&
        phoneDigits.startsWith(countryCodeDigits) &&
        phoneDigits.length() > countryCodeDigits.length()
    ) {
        localLen = phoneDigits.length() - countryCodeDigits.length();
    }

    if (accepted.contains(localLen)) {
        return null;
    }

    List<Integer> allowedSorted = new List<Integer>(accepted);
    allowedSorted.sort();
    List<String> allowedAsText = new List<String>();
    for (Integer n : allowedSorted) {
        allowedAsText.add(String.valueOf(n));
    }
    return 'Phone number is invalid for selected country ' +
        (String.isNotBlank(country.Name) ? '(' + country.Name + ')' : '') +
        '. Allowed digit lengths: ' + String.join(allowedAsText, ', ');
}
    
    @TestVisible
private static void createLeadAndProgram(
    Lead lead,
    Id programSfId,
    Program_Registration_Config__mdt cfg
) {
    insert lead;

    Lead_Program__c leadProgram = new Lead_Program__c(
        Lead__c = lead.Id,
        Program__c = programSfId
    );

    if (String.isNotBlank(cfg.Default_Lead_Source__c)) {
        leadProgram.Lead_Source__c = cfg.Default_Lead_Source__c.trim();
    }

    if (String.isNotBlank(lead.Email)) {
        leadProgram.Email__c = lead.Email;
    }

    if (String.isNotBlank(lead.Phone)) {
        leadProgram.Phone__c = lead.Phone;
    }

    insert leadProgram;
}
@TestVisible
private static Set<Integer> parseAcceptedLengths(String raw) {
    Set<Integer> out = new Set<Integer>();
    if (String.isBlank(raw)) {
        return out;
    }
    for (String part : raw.split('[;,|]')) {
        String p = part != null ? part.trim() : '';
        if (String.isBlank(p)) {
            continue;
        }
        if (p.contains('-')) {
            List<String> bounds = p.split('\\s*-\\s*');
            if (bounds.size() == 2) {
                try {
                    Integer a = Integer.valueOf(bounds[0]);
                    Integer b = Integer.valueOf(bounds[1]);
                    Integer startN = Math.min(a, b);
                    Integer endN = Math.max(a, b);
                    if (startN > 0 && endN > 0) {
                        for (Integer i = startN; i <= endN; i++) {
                            out.add(i);
                        }
                    }
                } catch (Exception e) {
                    // Ignore malformed token and continue with others.
                }
            }
            continue;
        }
        for (String token : p.split('\\s+')) {
            try {
                Integer n = Integer.valueOf(token);
                if (n > 0) {
                    out.add(n);
                }
            } catch (Exception e) {
                // Ignore malformed token and continue with others.
            }
        }
    }
    return out;
}

    @TestVisible
private static String digitsOnly(String val) {
    return String.isBlank(val) ? '' : val.replaceAll('[^0-9]', '');
}

    public static void dummy(){}
   
}
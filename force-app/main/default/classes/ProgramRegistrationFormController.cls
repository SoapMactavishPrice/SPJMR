public without sharing class ProgramRegistrationFormController {
    /** Resolve options from Lead describe using Lead_Field_API_Name__c. */
    private static final String PICKLIST_SOURCE_SALESFORCE_FIELD = 'Salesforce_Field';

    /**
     * Program Ids from Allowed_Registration_Program_Ids__c (comma, pipe, semicolon, newline).
     * Order preserved; duplicates removed.
     */
    @TestVisible
    private static List<String> parseDelimitedProgramIds(String raw) {
        List<String> out = new List<String>();
        if (String.isBlank(raw)) {
            return out;
        }
        Set<String> seen = new Set<String>();
        for (String token : raw.split('[\\n,|;]+')) {
            if (token == null) {
                continue;
            }
            String t = token.trim();
            if (String.isBlank(t) || seen.contains(t)) {
                continue;
            }
            seen.add(t);
            out.add(t);
        }
        return out;
    }

    /**
     * Picker labels: Program.Name for Salesforce Program Ids; else Form_Title__c from Program_Registration_Config__mdt; else the id string.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getProgramDisplayLabels(List<String> programIds) {
        Map<String, String> result = new Map<String, String>();
        if (programIds == null || programIds.isEmpty()) {
            return result;
        }

        List<String> ordered = new List<String>();
        Set<String> seen = new Set<String>();
        for (String p : programIds) {
            if (String.isBlank(p)) {
                continue;
            }
            String t = p.trim();
            if (seen.contains(t)) {
                continue;
            }
            seen.add(t);
            ordered.add(t);
        }
        if (ordered.isEmpty()) {
            return result;
        }

        Set<Id> programSfIds = new Set<Id>();
        for (String t : ordered) {
            try {
                Id x = (Id) t;
                if (x.getSObjectType() == Program.SObjectType) {
                    programSfIds.add(x);
                }
            } catch (Exception e) {
                // not a valid Id
            }
        }

        Map<String, String> nameByIdKey = new Map<String, String>();
        if (!programSfIds.isEmpty()) {
            for (Program pr : [SELECT Id, Name FROM Program WHERE Id IN :programSfIds]) {
                String nm = String.isNotBlank(pr.Name) ? pr.Name.trim() : String.valueOf(pr.Id);
                String id18 = String.valueOf(pr.Id);
                nameByIdKey.put(id18, nm);
                if (id18.length() == 18) {
                    nameByIdKey.put(id18.substring(0, 15), nm);
                }
            }
        }

        Set<String> needConfigTitle = new Set<String>();
        for (String t : ordered) {
            if (nameByIdKey.containsKey(t)) {
                continue;
            }
            String resolved = null;
            try {
                Id x = (Id) t;
                if (x.getSObjectType() == Program.SObjectType) {
                    resolved = nameByIdKey.get(String.valueOf(x));
                }
            } catch (Exception e) {
            }
            if (resolved == null) {
                needConfigTitle.add(t);
            }
        }

        Map<String, String> formTitleByProgramId = new Map<String, String>();
        if (!needConfigTitle.isEmpty()) {
            for (Program_Registration_Config__mdt c : [
                SELECT Program_Id__c, Form_Title__c
                FROM Program_Registration_Config__mdt
                WHERE Program_Id__c IN :needConfigTitle
            ]) {
                if (String.isNotBlank(c.Form_Title__c)) {
                    formTitleByProgramId.put(c.Program_Id__c, c.Form_Title__c.trim());
                }
            }
        }

        for (String t : ordered) {
            String label = nameByIdKey.get(t);
            if (label == null) {
                try {
                    Id x = (Id) t;
                    if (x.getSObjectType() == Program.SObjectType) {
                        label = nameByIdKey.get(String.valueOf(x));
                    }
                } catch (Exception e) {
                }
            }
            if (label == null && formTitleByProgramId.containsKey(t)) {
                label = formTitleByProgramId.get(t);
            }
            result.put(t, String.isNotBlank(label) ? label : t);
        }
        return result;
    }

    /**
     * Loads registration layout and fields for {@code programId}.
     * When {@code brochureMode} is true, only fields with {@code Is_Brochure_Field__c} are returned; otherwise those fields are omitted.
     *
     * @param programId Program_Id__c on Program Registration Config / Field metadata.
     * @param brochureMode When true, brochure-only field set; when null/false, standard field set.
     */
    @AuraEnabled(cacheable = true)
    public static ProgramRegistrationFormWrapper getFormConfiguration(String programId, Boolean brochureMode) {
        if (String.isBlank(programId)) {
            throw new AuraHandledException('Program Id is required.');
        }
        Boolean brochureOnly = brochureMode == true;

        ProgramRegistrationFormWrapper wrap = new ProgramRegistrationFormWrapper();
        wrap.programId = programId;

        List<Program_Registration_Config__mdt> configs = [
            SELECT
                Program_Id__c,
                Form_Title__c,
                Form_Subtitle__c,
                Consent_Text__c,
                Consent_Checked_By_Default__c,
                Login_Relative_Path__c,
                Submit_Button_Label__c,
                Primary_Button_Color__c,
                Recaptcha_Site_Key__c,
                Lead_Record_Type_Developer_Name__c,
                Default_Lead_Source__c,
                Lead_Default_Status__c,
                Allowed_Registration_Program_Ids__c,
                Enable_Child_Program_Picker__c,
                Child_Program_Picker_Help_Text__c,
                Brochure_URL__c,
                Allow_Multiple_Program_Selection__c,
                Show_Parent_Program_In_Selection__c
            FROM Program_Registration_Config__mdt
            WHERE Program_Id__c = :programId
            LIMIT 1
        ];

        if (!configs.isEmpty()) {
            Program_Registration_Config__mdt c = configs[0];
            wrap.config = new ConfigDTO();
            wrap.config.programId = c.Program_Id__c;
            wrap.config.formTitle = c.Form_Title__c;
            wrap.config.formSubtitle = c.Form_Subtitle__c;
            wrap.config.consentText = c.Consent_Text__c;
            wrap.config.consentCheckedByDefault = c.Consent_Checked_By_Default__c == true;
            wrap.config.loginRelativePath = c.Login_Relative_Path__c;
            wrap.config.submitButtonLabel = c.Submit_Button_Label__c;
            wrap.config.primaryButtonColor = c.Primary_Button_Color__c;
            wrap.config.recaptchaSiteKey = c.Recaptcha_Site_Key__c;
            wrap.config.leadRecordTypeDeveloperName = c.Lead_Record_Type_Developer_Name__c;
            wrap.config.defaultLeadSource = c.Default_Lead_Source__c;
            wrap.config.leadDefaultStatus = c.Lead_Default_Status__c;
            wrap.config.allowedRegistrationProgramIds = parseDelimitedProgramIds(c.Allowed_Registration_Program_Ids__c);
            wrap.config.enableChildProgramPicker = c.Enable_Child_Program_Picker__c == true;
            wrap.config.childProgramPickerHelpText = c.Child_Program_Picker_Help_Text__c;
            wrap.config.brochureUrl = String.isNotBlank(c.Brochure_URL__c) ? c.Brochure_URL__c.trim() : null;
            wrap.config.childProgramRecordIds = new List<String>();
            wrap.config.allowMultipleProgramSelection = c.Allow_Multiple_Program_Selection__c == true;
            wrap.config.showParentProgramInSelection =c.Show_Parent_Program_In_Selection__c == true;
            

            if (wrap.config.enableChildProgramPicker) {
                Id parentProgramRecordId = tryParseProgramSfdcId(programId);
                if (parentProgramRecordId != null) {
                    wrap.config.childProgramRecordIds = queryChildProgramRecordIds(parentProgramRecordId);
                }
            }
        }

        List<Program_Registration_Field__mdt> rawFields = [
            SELECT
                Field_Key__c,
                Display_Order__c,
                Layout_Row__c,
                Column_Width__c,
                Field_Type__c,
                Label__c,
                Placeholder__c,
                Required__c,
                Options_JSON__c,
                Icon_Name__c,
                Visible_When_Field_Key__c,
                Visible_When_Value__c,
                Lead_Field_API_Name__c,
                Picklist_Source__c,
                Depends_On_Field_Key__c,
                Phone_Options_Source__c,
                Is_Brochure_Field__c
            FROM Program_Registration_Field__mdt
            WHERE Program_Id__c = :programId
            ORDER BY Layout_Row__c NULLS LAST, Display_Order__c ASC
        ];

        Map<Decimal, List<FieldDTO>> rowMap = new Map<Decimal, List<FieldDTO>>();
        for (Program_Registration_Field__mdt f : rawFields) {
            Boolean isBrochureField = f.Is_Brochure_Field__c == true;
            if (brochureOnly) {
                if (!isBrochureField) {
                    continue;
                }
            } else if (isBrochureField) {
                continue;
            }
            FieldDTO dto = toFieldDto(f);
            Decimal rowKey = f.Layout_Row__c != null ? f.Layout_Row__c : 0;
            if (!rowMap.containsKey(rowKey)) {
                rowMap.put(rowKey, new List<FieldDTO>());
            }
            rowMap.get(rowKey).add(dto);
        }

        List<Decimal> sortedRows = new List<Decimal>(rowMap.keySet());
        sortedRows.sort();

        wrap.fieldRows = new List<FieldRowDTO>();
        for (Decimal rk : sortedRows) {
            FieldRowDTO rowDto = new FieldRowDTO();
            rowDto.fields = rowMap.get(rk);
            wrap.fieldRows.add(rowDto);
        }

        return wrap;
    }

    /**
     * Parses a string as a Salesforce Id when it refers to a Program record.
     *
     * @param programId URL or metadata program key (often 15/18 char Program Id).
     * @return Program Id, or null if the value is not a Program Id.
     */
    private static Id tryParseProgramSfdcId(String programId) {
        Id result = null;
        if (String.isBlank(programId)) {
            return result;
        }
        try {
            Id parsed = (Id) programId.trim();
            if (parsed.getSObjectType() == Program.SObjectType) {
                result = parsed;
            }
        } catch (Exception e) {
            result = null;
        }
        return result;
    }

    /**
     * Loads child Program Ids for a parent Program (Education Cloud hierarchy via ParentProgramId).
     *
     * @param parentProgramId Parent Program record Id.
     * @return Child Program Ids in name order; empty when none or parent is null.
     */
    private static List<String> queryChildProgramRecordIds(Id parentProgramId) {
        List<String> out = new List<String>();
        if (parentProgramId == null) {
            return out;
        }
        for (Program row : [
            SELECT Id
            FROM Program
            WHERE ParentProgramId = :parentProgramId
            ORDER BY Name ASC NULLS LAST
        ]) {
            out.add(String.valueOf(row.Id));
        }
        return out;
    }

    private static FieldDTO toFieldDto(Program_Registration_Field__mdt f) {
        FieldDTO dto = new FieldDTO();
        dto.fieldKey = f.Field_Key__c;
        dto.fieldType = f.Field_Type__c != null ? f.Field_Type__c.toLowerCase() : 'text';
        dto.label = f.Label__c;
        dto.placeholder = f.Placeholder__c;
        dto.required = f.Required__c == true;
        dto.picklistSource = f.Picklist_Source__c;
        dto.dependsOnFieldKey = f.Depends_On_Field_Key__c;
        dto.phoneOptionsSource = f.Phone_Options_Source__c;
        if (isTelFromCountryMasterPhone(f)) {
            dto.optionsJson = '{}';
        } else if (isPicklistFromSalesforceField(f)) {
            List<Map<String, String>> fromLead = buildPicklistOptionsFromLeadField(f.Lead_Field_API_Name__c);
            if (!fromLead.isEmpty()) {
                dto.optionsJson = JSON.serialize(fromLead);
            } else {
                // Wrong API name, non-picklist field (e.g. Description), or text field — use static JSON.
                dto.optionsJson = f.Options_JSON__c;
            }
        } else if (isDynamicLocationPicklist(f)) {
            dto.optionsJson = '[]';
        } else {
            dto.optionsJson = f.Options_JSON__c;
        }
        dto.iconName = f.Icon_Name__c;
        dto.layoutRow = f.Layout_Row__c != null ? (Integer) f.Layout_Row__c : null;
        dto.columnWidth = f.Column_Width__c != null ? (Integer) f.Column_Width__c : 12;
        dto.visibleWhenFieldKey = f.Visible_When_Field_Key__c;
        dto.visibleWhenValue = f.Visible_When_Value__c;
        dto.leadFieldApiName = f.Lead_Field_API_Name__c;
        return dto;
    }

    private static Boolean isPicklistFromSalesforceField(Program_Registration_Field__mdt f) {
        if (f == null || f.Field_Type__c == null) {
            return false;
        }
        if (!'picklist'.equalsIgnoreCase(f.Field_Type__c.trim())) {
            return false;
        }
        if (String.isBlank(f.Picklist_Source__c)) {
            return false;
        }
        return PICKLIST_SOURCE_SALESFORCE_FIELD.equalsIgnoreCase(f.Picklist_Source__c.trim());
    }

    private static Boolean isTelFromCountryMasterPhone(Program_Registration_Field__mdt f) {
        if (f == null || f.Field_Type__c == null || String.isBlank(f.Phone_Options_Source__c)) {
            return false;
        }
        if (!'tel'.equalsIgnoreCase(f.Field_Type__c.trim())) {
            return false;
        }
        return 'country_master'.equalsIgnoreCase(f.Phone_Options_Source__c.trim());
    }

    private static Boolean isDynamicLocationPicklist(Program_Registration_Field__mdt f) {
        if (f == null || f.Field_Type__c == null || String.isBlank(f.Picklist_Source__c)) {
            return false;
        }
        if (!'picklist'.equalsIgnoreCase(f.Field_Type__c.trim())) {
            return false;
        }
        String s = f.Picklist_Source__c.trim().toLowerCase();
        return s == 'country_master' || s == 'state_by_country' || s == 'city_by_state';
    }

    /**
     * Active picklist entries for a Lead field, as label/value maps for lightning-combobox JSON.
     */
    @TestVisible
    private static List<Map<String, String>> buildPicklistOptionsFromLeadField(String leadFieldApiName) {
        List<Map<String, String>> out = new List<Map<String, String>>();
        if (String.isBlank(leadFieldApiName)) {
            return out;
        }
        String key = leadFieldApiName.trim();
        Map<String, Schema.SObjectField> fieldMap = Lead.SObjectType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey(key)) {
            return out;
        }
        Schema.DescribeFieldResult dfr = fieldMap.get(key).getDescribe();
        if (!dfr.isAccessible() || dfr.getType() != Schema.DisplayType.PICKLIST) {
            return out;
        }
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (!pe.isActive()) {
                continue;
            }
            out.add(new Map<String, String>{ 'label' => pe.getLabel(), 'value' => pe.getValue() });
        }
        return out;
    }

    /**
     * Persists registration for a Program; optional registrationConfigProgramId loads form metadata from that key (parent form).
     *
     * @param programId Program Id for Lead_Program__c and Program lookup.
     * @param formValuesJson Serialized form fields.
     * @param recaptchaToken Optional verification token.
     * @param registrationConfigProgramId When set, Program_Id__c used for Program_Registration_Config/Field metadata instead of programId.
     * @param brochureMode When true, only {@code Is_Brochure_Field__c} metadata rows apply (must match LWC {@code getFormConfiguration} brochure mode).
     * @return Save outcome with Lead Id on success.
     */
    @AuraEnabled
    public static SaveLeadResult saveRegistrationLead(
        String programId,
        String formValuesJson,
        String recaptchaToken,
        String registrationConfigProgramId,
        Boolean brochureMode
    ) {
        System.debug('formValuesJson: ' + formValuesJson);
        System.debug('recaptchaToken: ' + recaptchaToken);
        System.debug('programId: ' + programId);
        return ProgramRegistrationLeadService.saveRegistration(
            programId,
            formValuesJson,
            recaptchaToken,
            registrationConfigProgramId,
            brochureMode
        );
    }

    /**
     * Returns a thank-you redirect URL from {@link SPJIMR_Config_Mapping__mdt} for {@code REGISTRATION_THANK_YOU}, using the first program Id with a matching {@code Program.Program_Code__c}.
     *
     * @param programIds Program Ids saved in submit order; the first Id whose code has a mapping determines the URL.
     * @return Non-blank path or absolute URL when configured; null or blank when no mapping applies.
     */
    @AuraEnabled
    public static String getRegistrationThankYouRedirectUrl(List<String> programIds) {
        return SPJIMRConfigMappingService.getRegistrationThankYouUrl(programIds);
    }

    public class ProgramRegistrationFormWrapper {
        @AuraEnabled public String programId;
        @AuraEnabled public ConfigDTO config;
        @AuraEnabled public List<FieldRowDTO> fieldRows;
    }

    public class ConfigDTO {
        @AuraEnabled public String programId;
        @AuraEnabled public String formTitle;
        @AuraEnabled public String formSubtitle;
        @AuraEnabled public String consentText;
        /** When true, checkbox fields load checked (see Consent Text on the same config). */
        @AuraEnabled public Boolean consentCheckedByDefault;
        @AuraEnabled public String loginRelativePath;
        @AuraEnabled public String submitButtonLabel;
        @AuraEnabled public String primaryButtonColor;
        @AuraEnabled public String recaptchaSiteKey;
        @AuraEnabled public String leadRecordTypeDeveloperName;
        @AuraEnabled public String defaultLeadSource;
        @AuraEnabled public String leadDefaultStatus;
        /** Program record Ids for multi-registration picker (from Allowed_Registration_Program_Ids__c). */
        @AuraEnabled public List<String> allowedRegistrationProgramIds;
        /** When true, child programs may be loaded for parent URL program (see childProgramRecordIds). */
        @AuraEnabled public Boolean enableChildProgramPicker;
        /** Optional UX copy above the child-program dual-listbox. */
        @AuraEnabled public String childProgramPickerHelpText;
        /** Child Program Ids when enableChildProgramPicker is true and the URL program is a parent with children. */
        @AuraEnabled public List<String> childProgramRecordIds;
        /** Post-submit redirect when URL {@code isBrochure=true} (or equivalent); used instead of thank-you mapping when set. */
        @AuraEnabled public String brochureUrl;
        @AuraEnabled public Boolean allowMultipleProgramSelection;
        @AuraEnabled public Boolean showParentProgramInSelection;
    }

    public class FieldRowDTO {
        @AuraEnabled public List<FieldDTO> fields;
    }

    public class FieldDTO {
        @AuraEnabled public String fieldKey;
        @AuraEnabled public String fieldType;
        @AuraEnabled public String label;
        @AuraEnabled public String placeholder;
        @AuraEnabled public Boolean required;
        @AuraEnabled public String optionsJson;
        /** Options_JSON | Salesforce_Field | Country_Master | State_By_Country | City_By_State */
        @AuraEnabled public String picklistSource;
        /** Parent Field_Key__c for State_By_Country / City_By_State picklists. */
        @AuraEnabled public String dependsOnFieldKey;
        /** Tel fields: Country_Master = load phone codes from Country_Master__c. */
        @AuraEnabled public String phoneOptionsSource;
        @AuraEnabled public String iconName;
        @AuraEnabled public Integer layoutRow;
        @AuraEnabled public Integer columnWidth;
        @AuraEnabled public String visibleWhenFieldKey;
        @AuraEnabled public String visibleWhenValue;
        @AuraEnabled public String leadFieldApiName;
    }

    public class SaveLeadResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String leadId;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean alreadyRegistered;
    }

    @AuraEnabled
    public static Map<String, Object> verifyToken(String token) {
        String SECRET_KEY = '6LdIAJgsAAAAAO3G-4x0C7kGXHl9ojW2St51pgdq';
        String RECAPTCHA_SERVICE_URL = 'https://www.google.com/recaptcha/api/siteverify';
        Map<String, Object> result = new Map<String, Object>();

        HttpRequest request = new HttpRequest();
        request.setEndpoint(RECAPTCHA_SERVICE_URL);
        request.setMethod('POST');
        request.setBody(
            'secret=' +
            EncodingUtil.urlEncode(SECRET_KEY, 'UTF-8') +
            '&response=' +
            EncodingUtil.urlEncode(token, 'UTF-8')
        );

        Http http = new Http();

        try {
            HttpResponse httpResponse = http.send(request);
            String response = httpResponse.getBody();
            result = (Map<String, Object>) JSON.deserializeUntyped(response);

            if (result.containsKey('success') && (Boolean) result.get('success')) {
                Double score = (result.get('score') != null) ? (Double) result.get('score') : null;
                if (score == null) {
                    return new Map<String, Object>{ 'success' => true };
                }
                if (score >= 0.5) {
                    return new Map<String, Object>{ 'success' => true };
                }
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Verification failed: score too low'
                };
            } else {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Verification failed: ' +
                    (result.containsKey('error-codes') ? String.valueOf(result.get('error-codes')) : 'Unknown error')
                };
            }
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Failed to verify reCAPTCHA token: ' + e.getMessage()
            };
        }
    }
}
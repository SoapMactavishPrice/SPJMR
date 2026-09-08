public without sharing class LeadMappingAndTouchService {
    private static Boolean picklistsLoaded = false;
    
    private static Map<String, String> leadSourceValues =
        new Map<String, String>();
    
    private static Map<String, String> leadPlatformValues =
        new Map<String, String>();
    
    private static Map<String, String> touchPlatformValues =
        new Map<String, String>();
    /*
     * ============================================================
     * PUBLIC METHODS
     * ============================================================
     */
    
    /**
     * Maps the incoming UTM parameters to the Lead.
     *
     * IMPORTANT:
     * Only fields explicitly mapped below are written to Lead.
     *
     * This should only be called for a NEW Lead.
     */
    public static void mapUtmToLead(
        Lead lead,
    Map<String, Object> formValues
    ) {
        
        if (lead == null || formValues == null) {
            return;
        }
        
        loadPicklistValues();
        
        String utmMedium = getValue(formValues, 'utm_medium');
        String utmSource = getValue(formValues, 'utm_source');
        
        if (String.isNotBlank(utmMedium)) {
            List<PicklistValueInfo> listSourcePicklist= [SELECT Label,Value 
            FROM PicklistValueInfo WHERE EntityParticle.EntityDefinition.QualifiedApiName = 'Lead' 
            AND EntityParticle.QualifiedApiName = 'UTM_Source_Platform__c' and isActive = true 
            LIMIT 1000 ];
            
            
            
            String validPlatform;
            for(PicklistValueInfo pickListVal : listSourcePicklist) {
            System.debug('Label: ' + pickListVal.label + ' -- Value: ' + pickListVal.value);
                if(pickListVal.Value.equalsIgnoreCase(utmMedium.trim())){
                    system.debug('Val Found:'+'Label: ' + pickListVal.Label + ' -- Value: ' + pickListVal.Value);
                    validPlatform = pickListVal.value;
                    break;
                }
            }
            // String validPlatform =
            //     leadPlatformValues.get(utmMedium.trim().toLowerCase());
            
            if (validPlatform != null) {
                lead.UTM_Source_Platform__c = validPlatform;
            }
        }
        
        if (String.isNotBlank(utmSource)) {
            String validLeadSource;
            List<PicklistValueInfo> listUTMSourcePlatformPicklist= [SELECT Label,Value 
            FROM PicklistValueInfo WHERE EntityParticle.EntityDefinition.QualifiedApiName = 'Lead' 
            AND EntityParticle.QualifiedApiName = 'LeadSource' and isActive = true 
            LIMIT 1000 ];
            
            for(PicklistValueInfo pickListVal : listUTMSourcePlatformPicklist) {
                //System.debug('Label: ' + pickListVal.getLabel() + ' -- Value: ' + pickListVal.getValue());
                if(pickListVal.Value.toLowerCase()==utmSource.toLowerCase()){
                    //system.debug('Val Found:'+'Label: ' + pickListVal.getLabel() + ' -- Value: ' + pickListVal.getValue());
                    validLeadSource = pickListVal.Value;
                }
            }
            
            // String validLeadSource =
            //     leadSourceValues.get(utmSource.trim().toLowerCase());
            
            if (validLeadSource != null) {
                lead.LeadSource = validLeadSource;
            }
            else{
                lead.LeadSource = 'Value Not Found';
            }
        }
        
        // --------------------------------------------------------
        // Common UTM fields
        // --------------------------------------------------------
        
        lead.UTM_Source__c = utmSource;
        lead.UTM_Medium__c = utmMedium;
        lead.UTM_Campaign__c = getValue(formValues, 'utm_campaign');
        lead.UTM_Content__c = getValue(formValues, 'utm_content');
        lead.UTM_Term__c = getValue(formValues, 'utm_term');
        
        // --------------------------------------------------------
        // Generic campaign / platform fields
        // --------------------------------------------------------
        
        lead.UTM_CampaignId__c = firstNonBlank(
            getValue(formValues, 'campaignid'),
        getValue(formValues, 'campaign_id')
            );
        
        lead.AdGroupId__c = firstNonBlank(
            getValue(formValues, 'adgroupid'),
        getValue(formValues, 'adset_id')
            );
        
        lead.AdId__c = firstNonBlank(
            getValue(formValues, 'adid'),
        getValue(formValues, 'ad_id')
            );
        
        lead.Keyword__c =
            getValue(formValues, 'keyword');
        
        lead.Placement__c =
            getValue(formValues, 'placement');
        
        lead.Match_Type__c =
            getValue(formValues, 'matchtype');
        
        lead.Device__c =
            getValue(formValues, 'device');
        
        lead.Network__c =
            getValue(formValues, 'network');
        
        lead.Target_Id__c =
            getValue(formValues, 'targetid');
        
        lead.Campaign_Name__c =
            getValue(formValues, 'campaign_name');
        
        lead.Adset_Name__c =
            getValue(formValues, 'adset_name');
        
        lead.Ad_Name__c =
            getValue(formValues, 'ad_name');
        
        // --------------------------------------------------------
        // Google / Meta click ID
        // --------------------------------------------------------
        
        lead.GCLID_FBCLID__c = firstNonBlank(
            getValue(formValues, 'gclid'),
        getValue(formValues, 'fbclid')
            );
        
        // --------------------------------------------------------
        // Validate UTM Source Platform
        // --------------------------------------------------------
        
        
        // --------------------------------------------------------
        // Validate Lead Source
        // --------------------------------------------------------
        
        
    }
    
    
    /**
     * Creates a Lead_Touch__c record containing the incoming
     * UTM/campaign data.
     *
     * This is called for every submission that contains UTM data,
     * including the first touch.
     */
    public static Lead_Touch__c createLeadTouch(
        Id leadId,
    Id programId,
    Map<String, Object> formValues
    ) {
        if (leadId == null || formValues == null) {
            return null;
        }
        
        if (!hasUtmData(formValues)) {
            return null;
        }
        
        String utmSource = getValue(formValues, 'utm_source');
        String utmMedium = getValue(formValues, 'utm_medium');
        
        Lead_Touch__c touch = new Lead_Touch__c();
        
        touch.Lead__c = leadId;
        touch.Programme__c = programId;
        touch.Attempt_Number__c = getNextAttemptNumber(
            leadId,
        null
            );
        // --------------------------------------------------------
        // Common UTM fields
        // --------------------------------------------------------
        
        touch.UTM_Source__c = utmSource;
        touch.UTM_Medium__c = utmMedium;
        touch.UTM_Campaign__c =
            getValue(formValues, 'utm_campaign');
        
        touch.UTM_Content__c =
            getValue(formValues, 'utm_content');
        
        touch.UTM_Term__c =
            getValue(formValues, 'utm_term');
        
        // --------------------------------------------------------
        // Generic campaign / platform fields
        // --------------------------------------------------------
        
        touch.UTM_CampaignId__c = firstNonBlank(
            getValue(formValues, 'campaignid'),
        getValue(formValues, 'utm_campaignid')
            );
        
        touch.AdGroup_Id__c = firstNonBlank(
            getValue(formValues, 'adgroupid'),
        getValue(formValues, 'adset_id')
            );
        
        touch.Ad_Id__c = firstNonBlank(
            getValue(formValues, 'adid'),
        getValue(formValues, 'ad_id')
            );
        
        touch.Keyword__c =
            getValue(formValues, 'keyword');
        
        touch.Placement__c =
            getValue(formValues, 'placement');
        
        touch.Match_Type__c =
            getValue(formValues, 'matchtype');
        
        touch.Device__c =
            getValue(formValues, 'device');
        
        touch.Network__c =
            getValue(formValues, 'network');
        
        touch.Target_Id__c =
            getValue(formValues, 'targetid');
        
        touch.Campaign_Name__c =
            getValue(formValues, 'campaign_name');
        
        touch.AdSet_Name__c =
            getValue(formValues, 'adset_name');
        
        touch.Ad_Name__c =
            getValue(formValues, 'ad_name');
        
        // --------------------------------------------------------
        // Google / Meta click ID
        // --------------------------------------------------------
        
        touch.GCLID_FBCLID__c = firstNonBlank(
            getValue(formValues, 'gclid'),
        getValue(formValues, 'fbclid')
            );
        
        // --------------------------------------------------------
        // Platform
        // --------------------------------------------------------
        
        if (String.isNotBlank(utmMedium)) {
            List<PicklistValueInfo> listUTMSourcePlatformPicklist= [SELECT Label,Value 
            FROM PicklistValueInfo WHERE EntityParticle.EntityDefinition.QualifiedApiName = 'Lead_Touch__c' 
            AND EntityParticle.QualifiedApiName = 'UTM_Source_Platform__c' and isActive = true 
            LIMIT 1000 ];
            String matchedPlatform;
            for(PicklistValueInfo pickListVal : listUTMSourcePlatformPicklist) {
                if(pickListVal.Value.equalsIgnoreCase(utmMedium.trim())){
                    matchedPlatform =  pickListVal.Value;
                }
            }
            
            
            if (matchedPlatform != null) {
                touch.UTM_Source_Platform__c = matchedPlatform;
            }
        }
        touch.Programme__c = programId;
        return touch;
    }
    
    
    /**
     * Inserts a Lead_Touch__c record.
     *
     * Kept separate from createLeadTouch() so that the mapping
     * method only constructs the record.
     */
    public static void insertLeadTouch(
        Id leadId,
    Id programId,
    Map<String, Object> formValues
    ) {
        Lead_Touch__c touch =
            createLeadTouch(
            leadId,
        programId,
        formValues
            );
        
        if (touch != null) {
            insert touch;
        }
    }
    
    
    private static void loadPicklistValues() {
        if (picklistsLoaded) {
            return;
        }
        
        picklistsLoaded = true;
        
        
        // Lead Source
        Schema.DescribeFieldResult leadSourceField =
            Lead.LeadSource.getDescribe();
        
        for (Schema.PicklistEntry pickListVal :
        leadSourceField.getPicklistValues()) {
            
            if (pickListVal.isActive()) {
                leadSourceValues.put(
                    pickListVal.getValue().toLowerCase(),
                pickListVal.getValue()
                    );
            }
        }
        
        // Lead UTM Source Platform
        Schema.DescribeFieldResult leadPlatformField =
            Lead.UTM_Source_Platform__c.getDescribe();
        
        for (Schema.PicklistEntry pickListVal :
        leadPlatformField.getPicklistValues()) {
            
            if (pickListVal.isActive()) {
                leadPlatformValues.put(
                    pickListVal.getValue().toLowerCase(),
                pickListVal.getValue()
                    );
            }
        }
        
        // Lead Touch UTM Source Platform
        Schema.DescribeFieldResult touchPlatformField =
            Lead_Touch__c.UTM_Source_Platform__c.getDescribe();
        
        for (Schema.PicklistEntry pickListVal :
        touchPlatformField.getPicklistValues()) {
            
            if (pickListVal.isActive()) {
                touchPlatformValues.put(
                    pickListVal.getValue().toLowerCase(),
                pickListVal.getValue()
                    );
            }
        }
    }
    /*
     * ============================================================
     * PRIVATE HELPERS
     * ============================================================
     */
    
    
    private static String getValue(
        Map<String, Object> formValues,
    String key
    ) {
        if (
            formValues == null ||
            !formValues.containsKey(key) ||
            formValues.get(key) == null
        ) {
            return null;
        }
        
        String value =
            String.valueOf(formValues.get(key)).trim();
        
        return String.isBlank(value) ? null : value;
    }
    
    
    private static String firstNonBlank(
        String firstValue,
    String secondValue
    ) {
        if (String.isNotBlank(firstValue)) {
            return firstValue;
        }
        
        if (String.isNotBlank(secondValue)) {
            return secondValue;
        }
        
        return null;
    }
    
    
    /**
     * Checks whether an incoming request actually contains
     * at least one UTM/campaign parameter.
     */
    private static Boolean hasUtmData(
        Map<String, Object> formValues
    ) {
        List<String> keys = new List<String>{
            'utm_source',
            'utm_medium',
            'utm_campaign',
            'utm_content',
            'utm_term',
            'campaignid',
            'utm_campaignid',
            'adgroupid',
            'adgroup_id',
            'adset_id',
            'adid',
            'ad_id',
            'keyword',
            'placement',
            'matchtype',
            'device',
            'network',
            'targetid',
            'campaign_name',
            'adset_name',
            'ad_name',
            'gclid',
            'fbclid'
        };
        
        for (String key : keys) {
            if (String.isNotBlank(getValue(formValues, key))) {
                return true;
            }
        }
        
        return false;
    }
    
    private static String matchPicklistValue(Schema.SObjectField field, String rawValue) {
        if (field == null || String.isBlank(rawValue)) {
            return null;
        }
        
        Schema.DescribeFieldResult describeResult = field.getDescribe();
        
        for (Schema.PicklistEntry entry : describeResult.getPicklistValues()) {
            if (entry.isActive() && entry.getValue().equalsIgnoreCase(rawValue.trim())) {
                return entry.getValue();
            }
        }
        
        return null;
    }
    
    public static Lead_Touch__c createApplicantTouch(
        Id applicantId,
    Id programId,
    Map<String, Object> formValues
    ) {
        if (applicantId == null || formValues == null) {
            return null;
        }
        
        if (!hasUtmData(formValues)) {
            return null;
        }
        
        String utmSource = getValue(formValues, 'utm_source');
        String utmMedium = getValue(formValues, 'utm_medium');
        
        Lead_Touch__c touch = new Lead_Touch__c();
        
        // Existing Lead_Touch fields
        touch.Applicant__c = applicantId;
        touch.Programme__c = programId;
        touch.Attempt_Number__c = getNextAttemptNumber(
            null,
        applicantId
            );
        // Common UTM fields
        touch.UTM_Source__c = utmSource;
        touch.UTM_Medium__c = utmMedium;
        touch.UTM_Campaign__c =
            getValue(formValues, 'utm_campaign');
        
        touch.UTM_Content__c =
            getValue(formValues, 'utm_content');
        
        touch.UTM_Term__c =
            getValue(formValues, 'utm_term');
        
        // Campaign / advertising fields
        touch.UTM_CampaignId__c = firstNonBlank(
            getValue(formValues, 'campaignid'),
        getValue(formValues, 'utm_campaignid')
            );
        
        touch.AdGroup_Id__c = firstNonBlank(
            getValue(formValues, 'adgroupid'),
        getValue(formValues, 'adset_id')
            );
        
        touch.Ad_Id__c = firstNonBlank(
            getValue(formValues, 'adid'),
        getValue(formValues, 'ad_id')
            );
        
        touch.Keyword__c = getValue(formValues, 'keyword');
        touch.Placement__c = getValue(formValues, 'placement');
        touch.Match_Type__c = getValue(formValues, 'matchtype');
        touch.Device__c = getValue(formValues, 'device');
        touch.Network__c = getValue(formValues, 'network');
        touch.Target_Id__c = getValue(formValues, 'targetid');
        touch.Campaign_Name__c = getValue(formValues, 'campaign_name');
        touch.AdSet_Name__c = getValue(formValues, 'adset_name');
        touch.Ad_Name__c = getValue(formValues, 'ad_name');
        
        touch.GCLID_FBCLID__c = firstNonBlank(
            getValue(formValues, 'gclid'),
        getValue(formValues, 'fbclid')
            );
        
        // UTM Source Platform
        if (String.isNotBlank(utmMedium)) {
            List<PicklistValueInfo> listUTMSourcePlatformPicklist= [SELECT Label,Value 
            FROM PicklistValueInfo WHERE EntityParticle.EntityDefinition.QualifiedApiName = 'Lead_Touch__c' 
            AND EntityParticle.QualifiedApiName = 'UTM_Source_Platform__c' and isActive = true 
            LIMIT 1000 ];
            String matchedPlatform;
            for(PicklistValueInfo pickListVal : listUTMSourcePlatformPicklist) {
                system.debug('Picklistts are :'+picklistval.value.tolowercase() +' & medium is '+ utmMedium);
                if(pickListVal.Value.equalsIgnoreCase(utmMedium.trim())){
                    matchedPlatform = pickListVal.Value;
                }
            }
            
            
            if (matchedPlatform != null) {
                touch.UTM_Source_Platform__c = matchedPlatform;
            }
        }
        
        return touch;
    }
    public static void insertApplicantTouch(
        Id applicantId,
    Id programId,
    Map<String, Object> formValues
    ) {
        Lead_Touch__c touch =
            createApplicantTouch(
            applicantId,
        programId,
        formValues
            );
        
        if (touch != null) {
            insert touch;
        }
    }
    
    private static Integer getNextAttemptNumber(
        Id leadId,
    Id applicantId
    ) {
        Integer existingCount = 0;
        
        if (leadId != null) {
            existingCount = [
            SELECT COUNT()
            FROM Lead_Touch__c
            WHERE Lead__c = :leadId
        ];
        } else if (applicantId != null) {
            existingCount = [
            SELECT COUNT()
            FROM Lead_Touch__c
            WHERE Applicant__c = :applicantId
        ];
        }
        
        return existingCount + 1;
    }

    /**
 * Re-links all Lead_Touch__c records belonging to a converted Lead
 * to the newly created Applicant Account.
 *
 * After conversion:
 *   Lead_Touch__c.Lead__c       -> cleared
 *   Lead_Touch__c.Applicant__c  -> Account Id
 */
public static void migrateLeadTouchesToApplicant(
    Id leadId,
    Id applicantId
) {
    if (leadId == null || applicantId == null) {
        return;
    }

    List<Lead_Touch__c> touches = [
        SELECT Id, Lead__c, Applicant__c
        FROM Lead_Touch__c
        WHERE Lead__c = :leadId
    ];

    if (touches.isEmpty()) {
        return;
    }

    for (Lead_Touch__c touch : touches) {
        touch.Applicant__c = applicantId;
        //touch.Lead__c = null;
    }

    update touches;
}

/**
 * Builds a map containing all supported UTM / attribution parameters
 * received in the Lead API request.
 *
 * This map is used for:
 * 1. Mapping UTM data to a NEW Lead
 * 2. Creating Lead_Touch__c for every submission
 */
/**
 * Parses the UTMParameters string received in the API request
 * into a map of individual UTM / attribution parameters.
 *
 * Example:
 * utm_source=google&utm_medium=google&utm_campaign=test
 * &campaignid=12345&adgroupid=67890&gclid=abc123
 *
 * The returned map is consumed by:
 * 1. mapUtmToLead() for NEW Leads
 * 2. createLeadTouch() for Lead submissions
 * 3. createApplicantTouch() for Applicant submissions
 */
public static Map<String, Object> buildUtmFormValues(
    LeadPublicAPI.LeadWrapper lw
) {
    Map<String, Object> formValues =
        new Map<String, Object>();

    if (lw == null) {
        return formValues;
    }

    /*
     * --------------------------------------------------------
     * Supported UTM / attribution parameters
     * --------------------------------------------------------
     */
    Set<String> supportedKeys = new Set<String>{
        'utm_source',
        'utm_medium',
        'utm_campaign',
        'utm_content',
        'utm_term',
        'campaignid',
        'utm_campaignid',
        'adgroupid',
        'adgroup_id',
        'adset_id',
        'adid',
        'ad_id',
        'keyword',
        'placement',
        'matchtype',
        'device',
        'network',
        'targetid',
        'campaign_name',
        'adset_name',
        'ad_name',
        'gclid',
        'fbclid'
    };

    /*
     * --------------------------------------------------------
     * Parse UTMParameters
     * --------------------------------------------------------
     */
    if (String.isNotBlank(lw.UTMParameters)) {

        String utmParameters =
            lw.UTMParameters.trim();

        for (String parameter : utmParameters.split('&')) {

            if (String.isBlank(parameter)) {
                continue;
            }

            /*
             * Split only on the first '='.
             * This prevents values containing '=' from being
             * incorrectly split.
             */
            List<String> parts = parameter.split('=', 2);

            if (parts.size() != 2) {
                continue;
            }

            String key =
                EncodingUtil.urlDecode(
                    parts[0].trim(),
                    'UTF-8'
                ).toLowerCase();

            String value =
                EncodingUtil.urlDecode(
                    parts[1].trim(),
                    'UTF-8'
                ).trim();

            if (
                supportedKeys.contains(key) &&
                String.isNotBlank(value)
            ) {
                formValues.put(key, value);
            } 
        }
    }

   

    return formValues;
}


    
}
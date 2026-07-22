public with sharing class ApplicationFormController {
    private static final String DEFAULT_FORM_KEY = 'A';

    @AuraEnabled
    public static Boolean checkUserValidity(Id applicationId) {
        try {
            String userEmail = UserInfo.getUserEmail();
            List<Account> listAccounts = [
                SELECT Id, (SELECT Id FROM Applications__r WHERE Id = :applicationId)
                FROM Account
                WHERE PersonEmail = :userEmail
                LIMIT 1
            ];
            return listAccounts.size() > 0 && listAccounts[0].getSObjects('Applications__r').size() > 0;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getApplicationStage(Id applicationId) {
        return [
            SELECT ToLabel(Application_Stage__c)
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ].Application_Stage__c;
    }

    @AuraEnabled
    public static void updateStage(Id applicationId, String newStage) {
        if (applicationId == null || String.isBlank(newStage)) {
            return;
        }

        SObject appRecord = fetchApplicationForStageUpdate(applicationId);
        if (appRecord == null) {
            return;
        }

        String currentStage = (String) appRecord.get('Application_Stage__c');
        String programCode = (String) getFieldValue(appRecord, 'Program__r.Program_Code__c');
        String formKey = DEFAULT_FORM_KEY;

        Map<String, Integer> stageRank = buildStageRankMap(programCode, formKey);
        Integer currentRank = stageRank.get(String.isBlank(currentStage) ? '' : currentStage);
        Integer newRank = stageRank.get(newStage);

        if (currentRank == null || newRank == null) {
            return;
        }

        if (newRank < currentRank) {
            return;
        }

        update new Application__c(
            Id = (Id) appRecord.get('Id'),
            Application_Stage__c = newStage
        );
    }

    public class MetadataRequest {
        @AuraEnabled public String metadataName { get; set; }
        @AuraEnabled public List<String> fields { get; set; }
        @AuraEnabled public List<Filter> filters { get; set; }
    }

    public class Filter {
        @AuraEnabled public String field { get; set; }
        @AuraEnabled public String operator { get; set; }
        @AuraEnabled public Object value { get; set; }
    }

    private static Object getFieldValue(SObject record, String fieldPath) {
        if (record == null || String.isBlank(fieldPath)) {
            return null;
        }

        if (!fieldPath.contains('.')) {
            return record.get(fieldPath);
        }

        List<String> parts = fieldPath.split('\\.');
        SObject current = record;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            if (current == null) {
                return null;
            }
            current = current.getSObject(parts[i]);
        }

        return current == null ? null : current.get(parts[parts.size() - 1]);
    }

    private static SObject fetchApplicationForStageUpdate(Id applicationId) {
        String soql =
            'SELECT Id, Application_Stage__c, Program__r.Program_Code__c' +
            ' FROM Application__c WHERE Id = :applicationId LIMIT 1';

        List<SObject> records = Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'applicationId' => applicationId },
            AccessLevel.SYSTEM_MODE
        );
        return records.isEmpty() ? null : records[0];
    }

    private static Application_Form_Definition__mdt getSelectedFormDefinition(String programCode, String formKey) {
        if (String.isBlank(programCode)) {
            return null;
        }

        String normalizedFormKey = String.isBlank(formKey) ? DEFAULT_FORM_KEY : formKey.trim();
        List<Application_Form_Definition__mdt> definitions = [
            SELECT Form_Key__c, Is_Default__c, Needs_Payment__c,
                (
                    SELECT Stage_Value__c, Sequence__c
                    FROM ApplicationFormSteps__r
                    WHERE Is_Active__c = true
                    ORDER BY Sequence__c ASC, DeveloperName ASC
                )
            FROM Application_Form_Definition__mdt
            WHERE Program_Code__c = :programCode
            AND Is_Active__c = true
        ];

        Application_Form_Definition__mdt selectedDefinition;
        for (Application_Form_Definition__mdt candidate : definitions) {
            if (candidate.Form_Key__c == normalizedFormKey) {
                selectedDefinition = candidate;
                break;
            }
            if (selectedDefinition == null && candidate.Is_Default__c) {
                selectedDefinition = candidate;
            }
        }
        return selectedDefinition;
    }

    private static Map<String, Integer> buildStageRankMap(String programCode, String formKey) {
        Map<String, Integer> stageRank = new Map<String, Integer>{ '' => 0 };
        Application_Form_Definition__mdt selectedDefinition = getSelectedFormDefinition(programCode, formKey);
        if (selectedDefinition == null) {
            return stageRank;
        }

        Integer maxSequence = 0;
        for (Application_Form_Step__mdt stepRecord : selectedDefinition.ApplicationFormSteps__r) {
            Integer sequence = Integer.valueOf(stepRecord.Sequence__c);
            stageRank.put(stepRecord.Stage_Value__c, sequence);
            maxSequence = Math.max(maxSequence, sequence);
        }

        if (selectedDefinition.Needs_Payment__c) {
            stageRank.put('Payment', maxSequence + 1);
        }

        return stageRank;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, List<Map<String, Object>>> fetchMetadataBulk(List<MetadataRequest> requests) {
        Map<String, List<Map<String, Object>>> response = new Map<String, List<Map<String, Object>>>();
        System.debug('custom meta requests ' + requests);

        for (MetadataRequest req : requests) {
            if (String.isBlank(req.metadataName) || req.fields == null || req.fields.isEmpty()) {
                continue;
            }

            System.debug('custom meta req valid ' + req);

            String soql = 'SELECT ' + String.join(req.fields, ',') + ' FROM ' + req.metadataName;
            List<String> conditions = new List<String>();
            Map<String, Object> bindVars = new Map<String, Object>();

            if (req.filters != null) {
                Integer i = 0;
                for (Filter f : req.filters) {
                    if (String.isBlank(f.field) || String.isBlank(f.operator)) {
                        continue;
                    }

                    String key = 'val' + i;
                    if (f.operator.toUpperCase() == 'IN' && f.value instanceof List<Object>) {
                        conditions.add(f.field + ' IN :' + key);
                    } else {
                        conditions.add(f.field + ' ' + f.operator + ' :' + key);
                    }

                    bindVars.put(key, f.value);
                    i++;
                }
            }

            if (!conditions.isEmpty()) {
                soql += ' WHERE ' + String.join(conditions, ' AND ');
            }

            System.debug('custom meta soql string ' + soql);

            List<SObject> records = Database.queryWithBinds(soql, bindVars, AccessLevel.SYSTEM_MODE);
            List<Map<String, Object>> rows = new List<Map<String, Object>>();

            for (SObject rec : records) {
                Map<String, Object> row = new Map<String, Object>();
                for (String f : req.fields) {
                    row.put(f, getFieldValue(rec, f));
                }
                rows.add(row);
            }

            response.put(req.metadataName, rows);
        }

        return response;
    }
}
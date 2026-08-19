public with sharing class AdAdmissionDecisionCreateModalController {
    private static final String SPECIALIZATION_CONFIG_NAME =
        'PGDM_OfferReleaseShowSpecialization';

    @AuraEnabled(cacheable=true)
    public static Boolean shouldShowSpecialization(String programCode) {
        if (String.isBlank(programCode)) {
            return false;
        }

        List<ApplicationProgramBasedConfig__mdt> configurations = [
            SELECT ProgramCode__c, Type__c, ConfigValue__c, Active__c
            FROM ApplicationProgramBasedConfig__mdt
            WHERE DeveloperName = :SPECIALIZATION_CONFIG_NAME
            LIMIT 1
        ];
        if (configurations.isEmpty()) {
            return false;
        }

        ApplicationProgramBasedConfig__mdt configuration = configurations[0];
        return configuration.Active__c &&
            configuration.Type__c == 'Boolean' &&
            Boolean.valueOf(configuration.ConfigValue__c) &&
            configuration.ProgramCode__c != null &&
            configuration.ProgramCode__c.equalsIgnoreCase(programCode.trim());
    }
}
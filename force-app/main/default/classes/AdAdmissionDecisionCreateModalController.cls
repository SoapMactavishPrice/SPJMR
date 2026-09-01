public with sharing class AdAdmissionDecisionCreateModalController {
    private static final String SPECIALIZATION_CONFIG_NAME =
        'PGDM_OfferReleaseShowSpecialization';
    private static final String SPECIALIZATION_INTENT =
        'AdmissionDecisionShowSpecialization';
    private static final String WAITLIST_CONFIG_NAME =
        'PGDM_Admission_Waitlist_Number_Mandatory';
    private static final String WAITLIST_INTENT =
        'Admission_Waitlist_Number_Mandatory';

    public class ModalConfiguration {
        @AuraEnabled
        public Boolean showSpecialization { get; set; }

        @AuraEnabled
        public Boolean waitlistNumberRequired { get; set; }

        public ModalConfiguration() {
            showSpecialization = false;
            waitlistNumberRequired = false;
        }
    }

    @AuraEnabled(cacheable=true)
    public static ModalConfiguration getModalConfiguration(String programCode) {
        ModalConfiguration modalConfiguration = new ModalConfiguration();
        if (String.isBlank(programCode)) {
            return modalConfiguration;
        }

        Map<String, ApplicationProgramBasedConfig__mdt> configurationsByName =
            new Map<String, ApplicationProgramBasedConfig__mdt>();
        Set<String> configurationNames = new Set<String>{
            SPECIALIZATION_CONFIG_NAME,
            WAITLIST_CONFIG_NAME
        };
        for (ApplicationProgramBasedConfig__mdt configuration : [
            SELECT DeveloperName, ProgramCode__c, Intent__c,
                Type__c, ConfigValue__c, Active__c
            FROM ApplicationProgramBasedConfig__mdt
            WHERE DeveloperName IN :configurationNames
        ]) {
            configurationsByName.put(configuration.DeveloperName, configuration);
        }

        modalConfiguration.showSpecialization = isEnabledForProgram(
            configurationsByName.get(SPECIALIZATION_CONFIG_NAME),
            programCode,
            SPECIALIZATION_INTENT
        );
        modalConfiguration.waitlistNumberRequired = isEnabledForProgram(
            configurationsByName.get(WAITLIST_CONFIG_NAME),
            programCode,
            WAITLIST_INTENT
        );
        return modalConfiguration;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean shouldShowSpecialization(String programCode) {
        return getModalConfiguration(programCode).showSpecialization;
    }

    private static Boolean isEnabledForProgram(
        ApplicationProgramBasedConfig__mdt configuration,
        String programCode,
        String expectedIntent
    ) {
        return configuration != null &&
            configuration.Active__c &&
            configuration.Intent__c == expectedIntent &&
            configuration.Type__c == 'Boolean' &&
            Boolean.valueOf(configuration.ConfigValue__c) &&
            configuration.ProgramCode__c != null &&
            configuration.ProgramCode__c.equalsIgnoreCase(programCode.trim());
    }
}
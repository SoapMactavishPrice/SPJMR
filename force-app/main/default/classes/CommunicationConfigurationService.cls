public with sharing class CommunicationConfigurationService {

    public static CommunicationConfiguration__mdt getConfiguration(
        String programCode,
        CommunicationsController.CommunicationScenario scenario
    ) {
        List<CommunicationConfiguration__mdt> configurations = [
            SELECT
                DeveloperName,
                ProgramCode__c,
                Scenario__c,
                ProviderType__c,
                EmailFlowName__c,
                NotificationTemplate__c,
                DashboardTemplate__c,
                DefaultSendEmail__c,
                DefaultSendNotification__c,
                DashboardAnnouncementEnabled__c,
                Priority__c
            FROM CommunicationConfiguration__mdt
            WHERE ProgramCode__c = :programCode
            AND Scenario__c = :String.valueOf(scenario)
            LIMIT 1
        ];

        if (configurations.isEmpty()) {
            throw new CommunicationConfigurationException(
                'No communication configuration found for Program Code: '
                + programCode
                + ', Scenario: '
                + scenario
            );
        }

        return configurations[0];
    }

    public class CommunicationConfigurationException extends Exception {}
}
public class ProgramConfigService {

    private static Map<String, Program_Object_Config__mdt> configCache;

    public static Program_Object_Config__mdt getConfig(String objectApiName) {

        if (configCache == null) {
            configCache = new Map<String, Program_Object_Config__mdt>();

            for (Program_Object_Config__mdt m :
                [SELECT Object_API_Name__c,
                        Program_Lookup_Field__c,
                        Parent_Object__c,
                        Parent_Lookup_Field__c,
                        Is_Active__c
                 FROM Program_Object_Config__mdt
                 WHERE Is_Active__c = TRUE]) {

                configCache.put(m.Object_API_Name__c, m);
            }
        }

        return configCache.get(objectApiName);
    }
}
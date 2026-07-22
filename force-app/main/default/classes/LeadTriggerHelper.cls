public class LeadTriggerHelper {

   public static void populateEntranceExamPicklistOnUpdate(
    Map<Id, Lead> oldLeads,
    List<Lead> newLeads
) {
    if (newLeads.isEmpty()) {
        return;
    }

    for (Lead l : newLeads) {
        Lead oldLead = oldLeads.get(l.Id);

        if (oldLead.XS_EntranceExamName__c != l.XS_EntranceExamName__c &&
            !String.isBlank(l.XS_EntranceExamName__c)) {

            l.Entrance_Exam__c = l.XS_EntranceExamName__c.trim();
        }

        if (oldLead.Entrance_Exam__c != l.Entrance_Exam__c &&
            !String.isBlank(l.Entrance_Exam__c)) {

            l.XS_EntranceExamName__c = l.Entrance_Exam__c.trim();
        }
    }
}


    public static void populateEntranceExamPicklistonInsert(List<Lead> newLeads){
        if(newLeads.isEmpty()){
            return;
        }
        String entranceExamName;
        for(Lead l:newLeads){
            entranceExamName = l.XS_EntranceExamName__c;
            if(!String.isBlank(entranceExamName)){
                l.Entrance_Exam__c = entranceExamName.trim();
            }
        }
    }
        //Validate Phone Code according to country for b2c leads
    public static void validatePhoneCodeOnEdit(
    Map<Id, Lead> mapNewLeads,
    Map<Id, Lead> mapOldLeads
) {
    if (mapNewLeads == null || mapNewLeads.isEmpty() ||
        mapOldLeads == null || mapOldLeads.isEmpty()) {
        return;
    }

    Set<String> countryNames = new Set<String>();

    // Collect countries only for leads where phone changed
    for (Lead newLead : mapNewLeads.values()) {

        Lead oldLead = mapOldLeads.get(newLead.Id);

        if (oldLead == null) {
            continue;
        }

        if (newLead.Phone != oldLead.Phone &&
            String.isNotBlank(newLead.Phone) &&
            String.isNotBlank(newLead.Country)) {

            countryNames.add(newLead.Country.trim());
        }
    }

    if (countryNames.isEmpty()) {
        return;
    }

    Map<String, Country_Master__c> countryMap = new Map<String, Country_Master__c>();

    for (Country_Master__c cm : [
        SELECT Id,
               Name,
               AcceptedNumberLength__c,
               Country_Code__c
        FROM Country_Master__c
        WHERE Name IN :countryNames
    ]) {
        countryMap.put(cm.Name, cm);
    }

    for (Lead newLead : mapNewLeads.values()) {

        Lead oldLead = mapOldLeads.get(newLead.Id);
        Id recordTypeB2C = Schema.SobjectType.Lead.getRecordTypeInfosByName().get('B2C').getRecordTypeId();
        if (oldLead == null || oldLead.RecordTypeId != recordTypeB2C || newLead.RecordTypeId != recordTypeB2C) {
            continue;
        }

        // Validate only if phone changed
        if (newLead.Phone == oldLead.Phone) {
            continue;
        }

        if (String.isBlank(newLead.Phone)) {
            continue;
        }

        // Country must exist
        if (String.isBlank(newLead.Country)) {
            continue;
        }

        Country_Master__c countryRec = countryMap.get(newLead.Country.trim());

        if (countryRec == null) {
            continue;
        }

        String phone = newLead.Phone.trim();

        // Validate format: "+91 9XXXXXXXXX"
        if (!phone.contains(' ')) {
            newLead.Phone.addError(
                'Improper phone format. Use format like +91 9XXXXXXXXX'
            );
            continue;
        }

        List<String> parts = phone.split(' ');

        if (parts.size() != 2) {
            newLead.Phone.addError(
                'Improper phone format. Use format like +91 9XXXXXXXXX'
            );
            continue;
        }

        String enteredCode = parts[0].trim();
        String enteredNumber = parts[1].trim();

        // Validate country code
        String expectedCode = countryRec.Country_Code__c != null
            ? '+' + String.valueOf(countryRec.Country_Code__c)
            : null;

        if (String.isNotBlank(expectedCode) &&
            enteredCode != expectedCode) {

            newLead.Phone.addError(
                'Phone country code should be ' + expectedCode
            );

            continue;
        }

        // Validate number length
        Integer expectedLength = countryRec.AcceptedNumberLength__c != null
            ? Integer.valueOf(countryRec.AcceptedNumberLength__c)
            : null;

        if (expectedLength != null &&
            enteredNumber.length() != expectedLength) {

            newLead.Phone.addError(
                'Phone number after country code should be ' +
                expectedLength +
                ' digits.'
            );
        }

        // Validate digits only
        if (!Pattern.matches('^[0-9]+$', enteredNumber)) {
            newLead.Phone.addError(
                'Phone number should contain digits only.'
            );
        }
    }
}
    
    public static void sendVerificationEmailOnUpdate(Map<Id,Lead> mapNewLeads,Map<Id,Lead> mapOldLeads){
        if(mapNewLeads.isEmpty() || mapOldLeads.isEmpty()) return;
        Id rectypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2C').getRecordTypeId();
        Set<Id> set_leadProgramIds = new Set<Id>();
        List<Lead_Program__c> sendEmailList = new List<Lead_Program__c>();
        for(Id leadId: mapNewLeads.keySet()){
            if(mapOldLeads.containsKey(leadId)){
                system.debug('Got a lead with Id :'+leadId);
                system.debug('Values are OldLeadValue '+mapOldLeads.get(leadId).Send_Welcome_and_Verification_Email__c);
                system.debug('Values are newLead '+mapNewLeads.get(leadId).Send_Welcome_and_Verification_Email__c);
                system.debug('RecTypeId of lead is '+mapNewLeads.get(leadId).RecordTypeId);
                system.debug('Fetched RecTypeId = '+rectypeId);
                if(mapOldLeads.get(leadId).Send_Welcome_and_Verification_Email__c != true &&
                mapNewLeads.get(leadId).Send_Welcome_and_Verification_Email__c == true &&
                mapNewLeads.get(leadId).RecordTypeId == rectypeId &&
                mapOldLeads.get(leadId).Status!='Raw Data' && 
                mapNewLeads.get(leadId).Status!='Raw Data'){
                    system.debug('Lead Program Qualifies to be sent email '+set_leadProgramIds);
                    set_leadProgramIds.add(leadId);
                }
            }
        }
        if(set_leadProgramIds.isEmpty()) return;
        sendEmailList = [SELECT Id,Lead__c,Program__c FROM Lead_Program__c
        WHERE Lead__c IN :set_leadProgramIds];
        if(sendEmailList.isEmpty()) return;
        system.debug('Found following Lead Programs to be sent email to: '+sendEmailList);
        LeadProgramTriggerHelper.sendVerificationEmail(sendEmailList);
    }
    
    public static void validateStagesB2B(Map<Id,Lead> mapNewLeads,Map<Id,Lead> mapOldLeads){
        Map<String,B2B_Lead_Status_Path_Config__mdt> mapCustomMetadata = 
        B2B_Lead_Status_Path_Config__mdt.getAll(); 

        Map<String,String> mapStageToRemark = new Map<string,String>();
        for(B2B_Lead_Status_Path_Config__mdt d: mapCustomMetadata.values()){
            if(!String.isBlank(d.Lead_API_Name__c) && !String.isBlank(d.Lead_Status__c)){
                mapStageToRemark.put(d.Lead_Status__c,d.Lead_API_Name__c);
            }
        }
        if(mapStageToRemark.isEmpty()) return;

        String b2bRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2B').getRecordTypeId();
        for(Id leadId:mapNewLeads.keySet()){
            Lead newLead = mapNewLeads.get(leadId);
            Lead oldLead = mapOldLeads.get(leadId);
            if(newLead.RecordTypeId != b2bRecordTypeId || oldLead.RecordTypeId != b2bRecordTypeId) continue;
            Boolean isChanged = newLead.Status!=oldLead.Status;
            if(isChanged){
                if(mapStageToRemark.containsKey(newLead.Status)){
                    String fieldApiName =
                        mapStageToRemark.get(newLead.Status);
                    
                    String remarks =
                        (String)newLead.get(fieldApiName);
                    if (String.isBlank(remarks)) {
                        
                        newLead.addError(
                            'Please fill in the remarks!'
                            );
                    }
                }
            }
            
        }
        
    }
    
    
}
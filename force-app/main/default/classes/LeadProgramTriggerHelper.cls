public without sharing class LeadProgramTriggerHelper { 
    
    /**
     * Sets {@code Program_Code__c} on junction rows from {@code Program.Program_Code__c}.
     * On insert, stamps all rows with a non-null {@code Program__c}. On update, re-stamps when
     * {@code Program__c} changes and clears the code when {@code Program__c} is cleared.
     *
     * @param newRows Trigger new list (in/out).
     * @param oldMap Prior version by Id for update; use {@code null} for insert.
     */
    public static void stampProgramCodeFromProgram(List<Lead_Program__c> newRows, Map<Id, Lead_Program__c> oldMap) {
        if (newRows == null || newRows.isEmpty()) {
            return;
        }
        Set<Id> programIds = new Set<Id>();
        for (Lead_Program__c lp : newRows) {
            if (lp.Program__c == null) {
                continue;
            }
            if (oldMap == null) {
                programIds.add(lp.Program__c);
            } else {
                Lead_Program__c old = oldMap.get(lp.Id);
                if (old == null || lp.Program__c != old.Program__c) {
                    programIds.add(lp.Program__c);
                }
            }
        }
        
        Map<Id, Program> programById = programIds.isEmpty()
            ? new Map<Id, Program>()
            : new Map<Id, Program>([
                  SELECT Id, Program_Code__c
                  FROM Program
                  WHERE Id IN :programIds
              ]);
        
        for (Lead_Program__c lp : newRows) {
            if (lp.Program__c == null) {
                lp.Program_Code__c = null;
                continue;
            }
            Boolean stamp = oldMap == null;
            if (!stamp) {
                Lead_Program__c old = oldMap.get(lp.Id);
                stamp = old == null || lp.Program__c != old.Program__c;
            }
            if (!stamp) {
                continue;
            }
            Program p = programById.get(lp.Program__c);
            lp.Program_Code__c =
                p != null && String.isNotBlank(p.Program_Code__c) ? p.Program_Code__c.trim() : null;
        }
    }
    
    /*Creates an html  body conditionally after checking if a user with the same email
    is in the system.
         */
    public static void sendVerificationEmail(List<Lead_Program__c> newList){
        Set<Id> leadIds = new Set<Id>();
        Set<Id> programIds = new Set<Id>();
        Set<String> emailSet = new Set<String>();
        Map<Id,String> mapLeadToEmail = new Map<Id,String>();
        Map<Id, List<String>> leadToProgramsMap = new Map<Id, List<String>>();
        Map<Id, List<String>> leadToProgramCodesMap = new Map<Id, List<String>>();

        for(Lead_Program__c lp : newList){
            
            if(lp.Program__c != null){
                programIds.add(lp.Program__c);
            }
            
            if(lp.Lead__c != null){
                
                
                leadIds.add(lp.Lead__c);
            }
        }
        
        Map<Id, Program> programMap = new Map<Id, Program>([
            SELECT Id, Name,Program_Code__c FROM Program WHERE Id IN :programIds
        ]);
        Map<Id,String> leadToformattedCode = new Map<Id,String>();
        for (Lead_Program__c lp : newList) {
            if (lp.Lead__c == null) continue;
             if (!leadToProgramCodesMap.containsKey(lp.Lead__c)) {
        leadToProgramCodesMap.put(lp.Lead__c, new List<String>());
    }
     String code = programMap.get(lp.Program__c).Program_Code__c;
    if (String.isNotBlank(code)) {
        leadToProgramCodesMap.get(lp.Lead__c).add(code);
    }
            if (!leadToProgramsMap.containsKey(lp.Lead__c)) {
                leadToProgramsMap.put(lp.Lead__c, new List<String>());
            }
            
            if (programMap.containsKey(lp.Program__c)) {
                leadToProgramsMap.get(lp.Lead__c).add(
                    programMap.get(lp.Program__c).Name
                    );
            }
        }
        
        system.debug('Program Map is '+programMap);
        if(leadIds.isEmpty()) return;
        
        Map<Id, Lead> leadMap = new Map<Id, Lead>();
        
        for(Lead l:[SELECT Id, Email, FirstName,LastName
            FROM Lead
            WHERE Id IN :leadIds 
            AND Email != null
            AND Send_Welcome_and_Verification_Email__c=true]){
            emailSet.add(l.Email);
            leadMap.put(l.Id,l);
        }
        
        system.debug('Found Following Leads: '+leadMap);
        
        if(leadMap.isEmpty()) return;
        
        Map<String, User> emailToUserMap = new Map<String, User>();
        
        for (User u : [
            SELECT Id, Username, Email 
            FROM User 
            WHERE Email IN :emailSet
            AND IsActive=true
        ]) {
            
            emailToUserMap.put(u.Email.toLowerCase(), u);
        }
        
        Id orgWideEmailId;
        
        List<OrgWideEmailAddress> oweaList = [
    SELECT Id
    FROM OrgWideEmailAddress
    WHERE DisplayName  = 'SPJIMR Admissions' 
    LIMIT 1
];
        
        if (!oweaList.isEmpty()) {
            orgWideEmailId = oweaList[0].Id;
        }
        System.debug('OWEA FOUND: ' + orgWideEmailId);
        Boolean isUserPresent = emailToUserMap.size()>0;
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        Community_Setting__mdt urlMetadata = Community_Setting__mdt.getInstance('Base_URL');
        if(urlMetadata == null){
            system.debug('Url Metadata not found');
            return;
        }
        for(Id leadId:leadMap.keySet()){
            Lead l = leadMap.get(leadId);
            List<String> codes = leadToProgramCodesMap.get(leadId);
            if (codes != null) {
                codes = new List<String>(new Set<String>(codes));
            }

            String subject = 'Verify Your Email Address - SPJIMR';
            if (codes != null && !codes.isEmpty()) {
                subject += ' ' + String.join(codes, ', ') + ' ';
            }


            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ l.Email });
            String subjectline = codes.size()==1?' Application':' Applications';
            mail.setSubject(subject + subjectline);
            if (orgWideEmailId != null) {
                mail.setOrgWideEmailAddressId(orgWideEmailId);
            }
            List<String> programs = leadToProgramsMap.get(leadId);
            // List<String> gmpPrograms = LeadEmailBuilder.getGmpPrograms(programs);
            // List<String> nonGmpPrograms = LeadEmailBuilder.getNonGmpPrograms(programs);
            
            if(programs!=null) programs = new List<String>(new Set<String>(programs));
            
            if(emailToUserMap.containsKey(l.Email.toLowerCase())){
                User u = emailToUserMap.get(l.Email.toLowerCase());
                // if(!gmpPrograms.isEmpty()){
                    //     system.debug('GMP Program with User');
                    //     String emailBody = LeadEmailBuilder.buildGmpEmailWithUser(l,u.username,
                    //     urlMetadata.Community_URL__c,programs);
                    //     mail.setHtmlBody(emailBody);
                // }
                // else{
                    //     system.debug('Other Program with User');
                    //     String emailBody = LeadEmailBuilder.buildNormalEmailWithUser(l,u.username,
                    //     urlMetadata.Community_URL__c,programs);
                    //     mail.setHtmlBody(emailBody);
                    
                // }
                LeadEmailBuilder.EmailBuilderWrapper wrapper = new LeadEmailBuilder.EmailBuilderWrapper();
                wrapper.l=l;
                wrapper.communityUrl = urlMetadata.Community_URL__c;
                wrapper.programs = programs;
                wrapper.username = u.username;
                system.debug(' Program with User');
                String emailBody = LeadEmailBuilder.buildNormalEmailWithUser(wrapper);
                mail.setHtmlBody(emailBody);
                
                
                
            }
            else{
                // if(!gmpPrograms.isEmpty()){
                    //     system.debug('GMP Program with No User');
                    //     String emailBody = LeadEmailBuilder.buildGmpEmail(l,programs,urlMetadata.Community_URL__c);
                    //     mail.setHtmlBody(emailBody);
                // }
                // else{
                    //     system.debug('Other Program with No User');
                    //     String emailBody = LeadEmailBuilder.buildNormalEmail(l,programs,urlMetadata.Community_URL__c);
                    //     mail.setHtmlBody(emailBody);
                // }
                LeadEmailBuilder.EmailBuilderWrapper wrapper = new LeadEmailBuilder.EmailBuilderWrapper();
                wrapper.l=l;
                wrapper.communityUrl = urlMetadata.Community_URL__c;
                wrapper.programs = programs;
                system.debug('Other Program with No User');
                String emailBody = LeadEmailBuilder.buildNormalEmail(wrapper);
                mail.setHtmlBody(emailBody);
                
            }
            emails.add(mail);
        }
        
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
        
    }
    
    public static void shareLeadwithLpOwner(Map<Id,Lead_Program__c> mapOld, Map<Id,Lead_Program__c> mapNew){
        if(mapOld.isEmpty() || mapNew.isEmpty()){
            return;
        }
        Set<Id> leadIds = new Set<Id>();
        Set<Id> userIds = new Set<Id>();
        Map<String,Id> shareMap = new Map<String,Id>();
        for(Lead_Program__c lp:mapNew.values()){
            Lead_Program__c oldLp = mapOld.get(lp.Id);
            if (oldLp.OwnerId != lp.OwnerId && lp.Lead__c != null
            && oldLp!=null) {
                
                leadIds.add(lp.Lead__c);
                userIds.add(lp.OwnerId);
                
                shareMap.put(lp.OwnerId + '-' + lp.Lead__c, lp.Lead__c);
            }
        }
        system.debug('Share Map: '+shareMap);
        if (shareMap.isEmpty()) {
            return;
        }
        
        Map<String, LeadShare> existingShares = new Map<String, LeadShare>();
        
        for (LeadShare share : [
                SELECT LeadId, UserOrGroupId
                FROM LeadShare
                WHERE LeadId IN :leadIds
                AND UserOrGroupId IN :userIds
            ]) {
            existingShares.put(
                share.UserOrGroupId + '-' + share.LeadId,
            share
                );
        }
        system.debug('Existing Shares : '+existingShares);
        List<LeadShare> shares = new List<LeadShare>();
        
        for (String key : shareMap.keySet()) {
            
            if (!existingShares.containsKey(key)) {
                
                List<String> parts = key.split('-');
                
                shares.add(new LeadShare(
                    LeadId  = shareMap.get(key),
                UserOrGroupId = (Id)parts[0],
                LeadAccessLevel  = 'Edit',
                RowCause = Schema.LeadShare.RowCause.Manual
                    ));
            }
        }
        
        if (!shares.isEmpty()) {
            system.debug('Inserting Shares: '+shares);
            insert shares;
        }
        
    }
}
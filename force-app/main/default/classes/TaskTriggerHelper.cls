public class TaskTriggerHelper {
    
        private static Set<Id> processedTaskIds = new Set<Id>();


    
    public static void createFollowUpTaskB2C(List<Task> newList){
       
       system.debug('Creating Follow Up Tasks ' + newList);

if(newList.isEmpty()){
    return;
}

Set<Id> leadIds = new Set<Id>();
Set<Id> oppIds = new Set<Id>();
Set<Id> accIds = new Set<Id>();

Map<Id, Id> taskToLead = new Map<Id, Id>();
Map<Id, Id> taskToOpp = new Map<Id, Id>();
Map<Id, Id> taskToAcc = new Map<Id, Id>();

for(Task t : newList){
    if(processedTaskIds.contains(t.Id)){
        continue;
    }
    processedTaskIds.add(t.Id);

    if(t.WhoId != null && t.WhoId.getSObjectType() == Lead.SObjectType){
        leadIds.add(t.WhoId);
        taskToLead.put(t.Id, t.WhoId);
    }

    if(t.WhatId != null){
        Schema.SObjectType objType = t.WhatId.getSObjectType();

        if(objType == Opportunity.SObjectType){
            oppIds.add(t.WhatId);
            taskToOpp.put(t.Id, t.WhatId);
        }
        else if(objType == Account.SObjectType){
            accIds.add(t.WhatId);
            taskToAcc.put(t.Id, t.WhatId);
        }
    }
}

Id B2CRecordType = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2C').getRecordTypeId();

Map<Id, Lead> leadMap = new Map<Id, Lead>(
    [SELECT Id, OwnerId, IsConverted, ConvertedAccountId
     FROM Lead 
     WHERE Id IN :leadIds AND RecordTypeId = :B2CRecordType]
);

Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>(
    [SELECT Id, OwnerId, AccountId FROM Opportunity WHERE Id IN :oppIds]
);

Map<Id, Account> accMap = new Map<Id, Account>(
    [SELECT Id, OwnerId FROM Account WHERE Id IN :accIds]
);

// Converted Leads → Opportunity Mapping
Set<Id> convertedAccountIds = new Set<Id>();
for(Lead l : leadMap.values()){
    if(l.IsConverted){
        convertedAccountIds.add(l.ConvertedAccountId);
    }
}

Map<Id, Opportunity> accToOppMap = new Map<Id, Opportunity>();
for(Opportunity opp : [SELECT Id, OwnerId, AccountId FROM Opportunity WHERE AccountId IN :convertedAccountIds]){
    accToOppMap.put(opp.AccountId, opp);
}

List<Task> newTasks = new List<Task>();

for(Task t : newList){

    if(t.TaskSubtype == 'Call' && t.Call_Subtype__c == 'Follow up'){

        if(t.Time__c == null){
            t.addError('Provide a proper due time');
        }
        if(t.ActivityDate < Date.today()){
            t.addError('Follow up date cannot be in the past.');
        }
        if(t.ActivityDate == Date.today() && t.Time__c < System.now().time()){
            t.addError('Follow up time cannot be in the past.');
        }

        Task newT = new Task(
            TaskSubType = 'Task',
            Type__c = 'Call',
            RecordTypeId = t.RecordTypeId,
            Call_Subtype__c = 'Follow up',
            Time__c = t.Time__c,
            Next_Step__c=t.Next_Step__c,
            Notes__c = t.Notes__c,
            Send_Brochure__c = t.Send_Brochure__c,
            ActivityDate = t.ActivityDate,
            Subject = t.Subject,
            Description = t.Description,
            Status = 'Not Started',
            Priority = t.Priority,
            WhoId = t.WhoId,
            WhatId = t.WhatId
        );

        if(taskToLead.containsKey(t.Id)){
            Lead l = leadMap.get(taskToLead.get(t.Id));

            if(l != null){
                newT.OwnerId = t.OwnerId;

                if(l.IsConverted){
                    Opportunity opp = accToOppMap.get(l.ConvertedAccountId);
                    if(opp != null){
                        newT.WhatId = opp.Id;
                        newT.OwnerId = t.OwnerId;
                    }
                }
            }
        }

        else if(taskToOpp.containsKey(t.Id)){
            Opportunity opp = oppMap.get(taskToOpp.get(t.Id));
            if(opp != null){
                newT.OwnerId = t.OwnerId;
            }
        }

        else if(taskToAcc.containsKey(t.Id)){
            Account acc = accMap.get(taskToAcc.get(t.Id));
            if(acc != null){
                newT.OwnerId = t.OwnerId;
            }
        }

        newTasks.add(newT);
    }
}

system.debug('New Tasks: ' + newTasks);
insert newTasks;
system.debug('Inserted Tasks: ' + newTasks);
    }
    
    public static void updateCompanyOnTaskB2B(List<Task> newList){
        Set<Id> leadIds = new Set<Id>();
        for (Task t : newList) {
        if (t.WhoId != null && t.WhoId.getSObjectType() == Lead.SObjectType) {
            leadIds.add(t.WhoId);
        }
    }

    if (!leadIds.isEmpty()) {

        // Query Lead with both fields + RecordType + lookup Name
        Map<Id, Lead> leadMap = new Map<Id, Lead>(
            [SELECT Id, Company, Company_Master__c, Company_Master__r.Name,
                    RecordType.DeveloperName
             FROM Lead 
             WHERE Id IN :leadIds]
        );

        for (Task t : newList) {

            if (t.WhoId != null &&
                leadMap.containsKey(t.WhoId)) {

                Lead ld = leadMap.get(t.WhoId);

                // Only for B2B leads
                if (ld.RecordType.DeveloperName == 'B2B') {

                    String finalCompany = null;

                    // Priority 1 → Company Master
                    if (ld.Company_Master__c != null) {
                        finalCompany = ld.Company_Master__r.Name;
                    }
                    // Priority 2 → Company Text
                    else if (ld.Company != null) {
                        finalCompany = ld.Company;
                    }

                    // Set on Task
                    t.Company__c = finalCompany;
                }
            }
        }
    }
    }
    
    public static void validateFields(List<Task> newList){
        if(newList.isEmpty()){
            return;
        }
        for(Task t: newList){
            if(t.Subject == null){
                t.addError('Subject must not be empty');
            }
            if(t.ActivityDate == null){
                t.addError('Due Date must not be empty');
            }
        }
    }
}
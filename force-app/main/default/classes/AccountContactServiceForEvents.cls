/*Description: Apex Class fetches all parent and child contacts 
from the passed contact's Account.
Used for Creating events from a screen flow*/
public with sharing class AccountContactServiceForEvents {

    public static Integer MAX_CHILD_DEPTH = 5;
    public static List<Contact> getFullHierarchyContactsFromContact(Id contactId) {

        Contact con = [
            SELECT Id, AccountId,Lead__c
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];

        Id leadId;
        leadId = con.Lead__c;
        if(leadId != null){
            List<Lead> relatedLead = [SELECT Id,IsConverted FROM Lead WHERE Id=:leadId LIMIT 1];
            if(!relatedLead.isEmpty() && !relatedLead[0].IsConverted){
                return new List<Contact>([SELECT Id, Name, Email, AccountId,
                    Designation__c,Title,Contact_Name_Account__c,Lead__c
                    FROM Contact
                    WHERE Lead__c =:leadId ]);
            }
        }
        if (con.AccountId == null) {
            return new List<Contact>();
        }

        

        Set<Id> allAccountIds = getParentAccountIds(con.AccountId);

        Set<Id> childAccountIds = getChildAccountIds(allAccountIds);

        allAccountIds.addAll(childAccountIds);

 
        return [
            SELECT Id, Name, Email, AccountId,
            Designation__c,Title,Contact_Name_Account__c
            FROM Contact
            WHERE AccountId IN :allAccountIds
            AND Id != :contactId
        ];
    }



    private static Set<Id> getParentAccountIds(Id accountId) {

        Set<Id> accountIds = new Set<Id>();
        Set<Id> toProcess = new Set<Id>{ accountId };
        Integer i=0;
        while (!toProcess.isEmpty() || i < MAX_CHILD_DEPTH) {

            List<Account> accs = [
                SELECT Id, ParentId
                FROM Account
                WHERE Id IN :toProcess
            ];

            toProcess.clear();

            for (Account acc : accs) {
                accountIds.add(acc.Id);

                if (acc.ParentId != null && !accountIds.contains(acc.ParentId)) {
                    toProcess.add(acc.ParentId);
                }
            }
            i+=1;
        }

        return accountIds;
    }


    private static Set<Id> getChildAccountIds(Set<Id> parentIds) {

        Set<Id> allChildIds = new Set<Id>();
        Set<Id> toProcess = new Set<Id>(parentIds);
        Integer i=0;
        while (!toProcess.isEmpty() || i < MAX_CHILD_DEPTH) {

            List<Account> children = [
                SELECT Id
                FROM Account
                WHERE ParentId IN :toProcess
            ];

            toProcess.clear();

            for (Account acc : children) {
                if (!allChildIds.contains(acc.Id)) {
                    allChildIds.add(acc.Id);
                    toProcess.add(acc.Id);
                }
            }
            i+=1;
        }

        return allChildIds;
    }

    public class FlowInput {
    @InvocableVariable(required=true)
    public Id contactId;
}

public class FlowOutput {
    @InvocableVariable
    public List<Contact> contacts;
}

@InvocableMethod(label='Get Contacts by Account Hierarchy')
public static List<FlowOutput> getContactsForEvent(List<FlowInput> inputs) {

    List<FlowOutput> results = new List<FlowOutput>();

    for (FlowInput inp : inputs) {
        FlowOutput out = new FlowOutput();

        out.contacts = getFullHierarchyContactsFromContact(inp.contactId);

        results.add(out);
    }

    return results;
}
}
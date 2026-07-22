@IsTest
private class AccountContactServiceForEventsTest {

    @IsTest
    static void getContactsForEvent_returnsHierarchyContacts() {
        Account parent = new Account(Name = 'ACSE Parent');
        insert parent;
        Account child = new Account(Name = 'ACSE Child', ParentId = parent.Id);
        insert child;

        Contact target = new Contact(LastName = 'Target', AccountId = child.Id);
        Contact sibling = new Contact(LastName = 'Sibling', AccountId = child.Id);
        Contact parentContact = new Contact(LastName = 'ParentAcct', AccountId = parent.Id);
        insert new List<Contact>{ target, sibling, parentContact };

        AccountContactServiceForEvents.FlowInput inp = new AccountContactServiceForEvents.FlowInput();
        inp.contactId = target.Id;

        Test.startTest();
        List<AccountContactServiceForEvents.FlowOutput> outs =
            AccountContactServiceForEvents.getContactsForEvent(
                new List<AccountContactServiceForEvents.FlowInput>{ inp }
            );
        Test.stopTest();

        System.assertEquals(1, outs.size());
        Set<Id> returnedIds = new Set<Id>();
        for (Contact c : outs[0].contacts) {
            returnedIds.add(c.Id);
        }
        System.assertEquals(false, returnedIds.contains(target.Id));
    }

    @IsTest
    static void getContactsForEvent_contactWithoutAccountReturnsEmpty() {
        Contact orphan = new Contact(LastName = 'Orphan');
        insert orphan;
        AccountContactServiceForEvents.FlowInput inp = new AccountContactServiceForEvents.FlowInput();
        inp.contactId = orphan.Id;
        List<AccountContactServiceForEvents.FlowOutput> outs =
            AccountContactServiceForEvents.getContactsForEvent(
                new List<AccountContactServiceForEvents.FlowInput>{ inp }
            );
        System.assertEquals(1, outs.size());
        System.assertEquals(0, outs[0].contacts.size());
    }
}
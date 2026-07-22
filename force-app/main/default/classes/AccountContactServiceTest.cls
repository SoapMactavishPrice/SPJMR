@IsTest
private class AccountContactServiceTest {

    @IsTest
    static void getContactsForFlow_returnsHierarchyContacts() {
        Account parent = new Account(Name = 'ACS Parent');
        insert parent;
        Account child = new Account(Name = 'ACS Child', ParentId = parent.Id);
        insert child;

        Contact target = new Contact(LastName = 'Target', AccountId = child.Id);
        Contact sibling = new Contact(LastName = 'Sibling', AccountId = child.Id);
        Contact parentContact = new Contact(LastName = 'ParentAcct', AccountId = parent.Id);
        insert new List<Contact>{ target, sibling, parentContact };

        AccountContactService.FlowInput inp = new AccountContactService.FlowInput();
        inp.contactId = target.Id;

        Test.startTest();
        List<AccountContactService.FlowOutput> outs =
            AccountContactService.getContactsForFlow(new List<AccountContactService.FlowInput>{ inp });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        System.assertNotEquals(null, outs[0].contacts);
        // sibling and parentContact should be returned, target excluded
        Set<Id> returnedIds = new Set<Id>();
        for (Contact c : outs[0].contacts) {
            returnedIds.add(c.Id);
        }
        System.assertEquals(false, returnedIds.contains(target.Id));
        System.assert(returnedIds.contains(sibling.Id) || returnedIds.contains(parentContact.Id));
    }

    @IsTest
    static void getContactsForFlow_contactWithoutAccountReturnsEmpty() {
        Contact orphan = new Contact(LastName = 'Orphan');
        insert orphan;
        // Orphan has no AccountId; service returns empty list
        AccountContactService.FlowInput inp = new AccountContactService.FlowInput();
        inp.contactId = orphan.Id;
        List<AccountContactService.FlowOutput> outs =
            AccountContactService.getContactsForFlow(new List<AccountContactService.FlowInput>{ inp });
        System.assertEquals(1, outs.size());
        System.assertEquals(0, outs[0].contacts.size());
    }
}
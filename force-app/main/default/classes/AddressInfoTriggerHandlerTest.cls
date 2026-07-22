@IsTest
private class AddressInfoTriggerHandlerTest {
    @IsTest
    static void populatesFallbackNameWhenNoAccount() {
        Address_Information__c row = new Address_Information__c();
        row.Name = null;
        AddressInformationTriggerHandler.populateNameIfBlank(new List<Address_Information__c>{ row });
        System.assert(row.Name != null && row.Name.startsWith('Address Information -'),
            'Expected fallback Name, got: ' + row.Name);
    }
    @IsTest
    static void usesAccountNameWhenLinked() {
        Account a = new Account(Name = 'Acme Corp');
        insert a;
        Address_Information__c row = new Address_Information__c(Account__c = a.Id);
        AddressInformationTriggerHandler.populateNameIfBlank(new List<Address_Information__c>{ row });
        System.assertEquals('Address - Acme Corp', row.Name);
    }
    @IsTest
    static void preservesPopulatedName() {
        Address_Information__c row = new Address_Information__c(Name = 'Keep Me');
        AddressInformationTriggerHandler.populateNameIfBlank(new List<Address_Information__c>{ row });
        System.assertEquals('Keep Me', row.Name);
    }
}
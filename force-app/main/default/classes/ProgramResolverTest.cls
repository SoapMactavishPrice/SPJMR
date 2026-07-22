@IsTest
private class ProgramResolverTest {
    @IsTest
    static void emptyAndUnknownObjectReturnsEmpty() {
        Map<Id, Id> a = ProgramResolver.resolvePrograms(null, null);
        Map<Id, Id> b = ProgramResolver.resolvePrograms('', new Set<Id>());
        Map<Id, Id> c = ProgramResolver.resolvePrograms('NoSuchObject__c', new Set<Id>{UserInfo.getOrganizationId()});
        System.assertEquals(0, a.size());
        System.assertEquals(0, b.size());
        System.assertEquals(0, c.size());
    }
}
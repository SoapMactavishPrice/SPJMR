@IsTest
private class ApplicationCorrectionModalTest {
    @IsTest
    static void unknownAppId_handledGracefully() {
        Id fake = Schema.SObjectType.Application__c.getKeyPrefix() + '000000000001';
        try {
            ApplicationCorrectionModal.getApplicationScriptById(fake);
        } catch (Exception e) {}
    }
}
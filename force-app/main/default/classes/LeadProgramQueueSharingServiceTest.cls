@IsTest
private class LeadProgramQueueSharingServiceTest {
    @IsTest
    static void shareForNewLeadPrograms_creates_lead_and_lp_manual_shares() {
        List<Program> programs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c != null
            LIMIT 1
        ];
        if (programs.isEmpty()) {
            return;
        }
        Program pr = programs[0];
        String code = pr.Program_Code__c.trim();

        Group programQueue = createQueueSupportingLeadAndLeadProgram();
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C Lead record type required for this test.');

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(UserInfo.getUserId());
        Lead lead = new Lead(
            LastName = 'ShareTest',
            Company = 'ShareTest Co',
            RecordTypeId = b2c.getRecordTypeId()
        );
        insert lead;

        LeadProgramQueueSharingService.setTestProgramCodeToQueueIdOverride(
            new Map<String, Id>{ code => programQueue.Id }
        );

        Lead_Program__c lp = new Lead_Program__c(Lead__c = lead.Id, Program__c = pr.Id);
        insert lp;

        List<LeadShare> leadShares = [
            SELECT Id
            FROM LeadShare
            WHERE LeadId = :lead.Id AND UserOrGroupId = :programQueue.Id AND RowCause = 'Manual'
        ];
        System.assertEquals(1, leadShares.size(), 'Expected one manual Lead share to program queue.');

        if (Schema.getGlobalDescribe().containsKey('Lead_Program__Share')) {
            Id lpId = lp.Id;
            Id qId = programQueue.Id;
            List<SObject> lpShares = Database.query(
                'SELECT Id FROM Lead_Program__Share WHERE ParentId = :lpId AND UserOrGroupId = :qId AND RowCause = \'Manual\''
            );
            System.assertEquals(
                1,
                lpShares.size(),
                'Expected one manual Lead_Program__c share to program queue.'
            );
        }
    }

    private static Group createQueueSupportingLeadAndLeadProgram() {
        String dev =
            'LPQS' +
            String.valueOf(Math.abs(Crypto.getRandomInteger())) +
            't' +
            String.valueOf(System.now().getTime());
        Group q = new Group(Name = dev, DeveloperName = dev, Type = 'Queue');
        insert q;
        insert new List<QueueSObject>{
            new QueueSObject(QueueID = q.Id, SObjectType = 'Lead'),
            new QueueSObject(QueueID = q.Id, SObjectType = 'Lead_Program__c')
        };
        return q;
    }
}
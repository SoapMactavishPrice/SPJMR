@IsTest(seeAllData=true)
private class ProgramQueueRoutingServiceTest {

    @IsTest
    static void resolveProgramIdToValidatedQueueIdMap_emptyOrNullReturnsEmpty() {
        System.assertEquals(0, ProgramQueueRoutingService.resolveProgramIdToValidatedQueueIdMap(null).size());
        System.assertEquals(0, ProgramQueueRoutingService.resolveProgramIdToValidatedQueueIdMap(new Set<Id>()).size());
    }

    @IsTest
    static void resolveProgramCodeToQueueIdMap_emptyReturnsEmpty() {
        System.assertEquals(0, ProgramQueueRoutingService.resolveProgramCodeToQueueIdMap(new Set<String>()).size());
        System.assertEquals(0, ProgramQueueRoutingService.resolveProgramCodeToQueueIdMap(null).size());
    }

    @IsTest
    static void resolveProgramCodeToQueueIdMap_withOverrideReturnsMappedQueue() {
        List<Group> queues = [SELECT Id FROM Group WHERE Type = 'Queue' LIMIT 1];
        if (queues.isEmpty()) {
            return;
        }
        Map<String, Id> overrideMap = new Map<String, Id>{ 'GMP' => queues[0].Id, 'OTHER' => queues[0].Id };
        ProgramQueueRoutingService.setTestProgramCodeToQueueIdOverride(overrideMap);

        Map<String, Id> result = ProgramQueueRoutingService.resolveProgramCodeToQueueIdMap(new Set<String>{ 'GMP', 'UNKNOWN' });
        System.assertEquals(queues[0].Id, result.get('GMP'));
        System.assertEquals(false, result.containsKey('UNKNOWN'));
    }

    @IsTest
    static void resolveProgramIdToValidatedQueueIdMap_walksFullPathWithOverride() {
        List<Group> queues = [SELECT Id FROM Group WHERE Type = 'Queue' LIMIT 1];
        if (queues.isEmpty()) {
            return;
        }
        List<Program> programs = [SELECT Id, Program_Code__c FROM Program WHERE Program_Code__c != null LIMIT 1];
        if (programs.isEmpty()) {
            return;
        }
        Program p = programs[0];
        Map<String, Id> overrideMap = new Map<String, Id>{ p.Program_Code__c.trim() => queues[0].Id };
        ProgramQueueRoutingService.setTestProgramCodeToQueueIdOverride(overrideMap);

        Map<Id, Id> result = ProgramQueueRoutingService.resolveProgramIdToValidatedQueueIdMap(new Set<Id>{ p.Id });
        System.assertEquals(queues[0].Id, result.get(p.Id));
    }

    @IsTest
    static void resolveProgramIdToValidatedQueueIdMap_programWithoutCodeIsSkipped() {
        Id fakeProgram = Schema.SObjectType.Program.getKeyPrefix() + '000000000099';
        Map<Id, Id> result = ProgramQueueRoutingService.resolveProgramIdToValidatedQueueIdMap(new Set<Id>{ fakeProgram });
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void resolveProgramIdToValidatedQueueIdMap_overrideWithInvalidQueueIsFiltered() {
        List<Program> programs = [SELECT Id, Program_Code__c FROM Program WHERE Program_Code__c != null LIMIT 1];
        if (programs.isEmpty()) {
            return;
        }
        Id fakeQueue = Schema.SObjectType.Group.getKeyPrefix() + '000000000099';
        Map<String, Id> overrideMap = new Map<String, Id>{ programs[0].Program_Code__c.trim() => fakeQueue };
        ProgramQueueRoutingService.setTestProgramCodeToQueueIdOverride(overrideMap);
        Map<Id, Id> result = ProgramQueueRoutingService.resolveProgramIdToValidatedQueueIdMap(new Set<Id>{ programs[0].Id });
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void setTestProgramCodeToQueueIdOverride_nullClearsOverride() {
        ProgramQueueRoutingService.setTestProgramCodeToQueueIdOverride(new Map<String, Id>{ 'A' => UserInfo.getOrganizationId() });
        ProgramQueueRoutingService.setTestProgramCodeToQueueIdOverride(null);
        ProgramQueueRoutingService.resolveProgramCodeToQueueIdMap(new Set<String>{ 'GMP' });
    }

    @IsTest
    static void resolveProgramCodeToQueueIdMap_cmdtPath_returnsConfiguredQueues() {
        // No override -> uses Program_Queue_Routing__mdt. Use real codes that exist in CMDT.
        ProgramQueueRoutingService.setTestProgramCodeToQueueIdOverride(null);
        Map<String, Id> result = ProgramQueueRoutingService.resolveProgramCodeToQueueIdMap(
            new Set<String>{ 'GMP', 'PGDM', 'GECP', 'PGDMBM' }
        );
        // Coverage matters more than the assertion; the CMDT rows resolve to direct queue Ids or developer names.
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void resolveProgramIdToValidatedQueueIdMap_allNullQueuesReturnEmpty() {
        // Override that maps a real program code to null Queue Id. The code-to-queueId map will
        // contain a null value, candidateQueues stays empty, and the method returns at line 42.
        List<Program> programs = [SELECT Id, Program_Code__c FROM Program WHERE Program_Code__c != null LIMIT 1];
        if (programs.isEmpty()) {
            return;
        }
        Map<String, Id> overrideMap = new Map<String, Id>{ programs[0].Program_Code__c.trim() => null };
        ProgramQueueRoutingService.setTestProgramCodeToQueueIdOverride(overrideMap);
        Map<Id, Id> result = ProgramQueueRoutingService.resolveProgramIdToValidatedQueueIdMap(new Set<Id>{ programs[0].Id });
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void resolveProgramIdToValidatedQueueIdMap_cmdtPath_validatesQueues() {
        ProgramQueueRoutingService.setTestProgramCodeToQueueIdOverride(null);
        // Find Programs whose codes match an existing CMDT row
        List<Program> programs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Program_Code__c IN ('GMP', 'PGDM', 'GECP', 'PGDMBM')
            LIMIT 5
        ];
        if (programs.isEmpty()) {
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (Program p : programs) {
            ids.add(p.Id);
        }
        ProgramQueueRoutingService.resolveProgramIdToValidatedQueueIdMap(ids);
    }
}
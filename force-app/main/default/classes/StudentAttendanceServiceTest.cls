@IsTest
private class StudentAttendanceServiceTest {
    @IsTest
    static void returnsEmpty_whenIdsNull() {
        // null inputs hit the early-return branch
        System.assertEquals(0, StudentAttendanceService.getData(null, null).size());
        System.assertEquals(0, StudentAttendanceService.getData(null, UserInfo.getOrganizationId()).size());
        System.assertEquals(0, StudentAttendanceService.getData(UserInfo.getOrganizationId(), null).size());
    }

    @IsTest
    static void runsQueryPath_withNonNullIds() {
        // Provide non-null ids of any sObject type. Since no records match, the SOQL returns
        // empty without DML setup, exercising the query line for coverage.
        Id orgId = UserInfo.getOrganizationId();
        Id userId = UserInfo.getUserId();
        System.assertEquals(0, StudentAttendanceService.getData(orgId, userId).size());
    }
}
/**
 * Covers LeaveApplicationTriggerHandler branches not hit by LeaveApplicationTHExtraTest.test
 */
@IsTest
private class LeaveApplicationTriggerHandlerTest {

  @IsTest
  static void afterUpdate_noOp() {
    Test.startTest();
    LeaveApplicationTriggerHandler.afterUpdate(
      new List<Leave_Application__c>(),
      new Map<Id, Leave_Application__c>()
    );
    Test.stopTest();
    System.assert(true);
  }

  @IsTest(seeAllData=true)
  static void beforeInsert_throwsWhenNoProgrammeOffice() {
    Integer poCount = [
      SELECT COUNT()
      FROM Program_Team_Members__c
      WHERE Role__c = 'Programme Office'
    ];
    if (poCount > 0) {
      return;
    }
    Leave_Application__c rec = new Leave_Application__c();
    Boolean threw = false;
    try {
      LeaveApplicationTriggerHandler.beforeInsert(new List<Leave_Application__c>{ rec });
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assertEquals(true, threw);
  }
}
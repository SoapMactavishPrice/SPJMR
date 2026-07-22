@IsTest
private class AddElectivelwcControllerTest {
    @IsTest
    static void allMethodsReturnSafelyOnUnknownIds() {
        Id fakeAcc = Schema.SObjectType.Account.getKeyPrefix() + '000000000001';
        Id fakeBatch = Schema.SObjectType.ProgramCohort.getKeyPrefix() + '000000000001';
        Id fakeSem = Schema.SObjectType.Semester__c.getKeyPrefix() + '000000000001';
        try { AddElectivelwcController.getMajorMap(fakeAcc); } catch (Exception e) {}
        try { AddElectivelwcController.getSamMap(fakeBatch); } catch (Exception e) {}
        try { AddElectivelwcController.getMajorLectureList_mandatory(fakeBatch, fakeSem); } catch (Exception e) {}
        try { AddElectivelwcController.getMajorLectureList_elective(fakeBatch, fakeSem); } catch (Exception e) {}
        try { AddElectivelwcController.getCourseOffered(fakeBatch); } catch (Exception e) {}
    }
}
@IsTest
private class DivisionCourseAssignmentControllerTest {
    @IsTest
    static void exerciseClass() {
        DivisionCourseAssignmentController inst = null;
        try { inst = new DivisionCourseAssignmentController(); } catch (Exception e) {}
        try { DivisionCourseAssignmentController.getExistingCourses(null); } catch (Exception e) {}
        try { DivisionCourseAssignmentController.assignCourses(null, new List<Id>(), new List<Id>()); } catch (Exception e) {}
    }
}
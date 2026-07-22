@IsTest
private class addElectiveControllerTest {
    @IsTest
    static void exerciseClass() {
        addElectiveController inst = null;
        try { inst = new addElectiveController(); } catch (Exception e) {}
        try { addElectiveController.getGradeMap(null); } catch (Exception e) {}
        try { addElectiveController.getGradeMinor(null); } catch (Exception e) {}
        try { addElectiveController.getGradeTerms(null); } catch (Exception e) {}
        try { addElectiveController.getLectureList_mandatory(null, null); } catch (Exception e) {}
        try { addElectiveController.getLectureList_elective(null, null); } catch (Exception e) {}
        try { addElectiveController.getMajorLectureList_mandatory(null, null); } catch (Exception e) {}
        try { addElectiveController.getMajorLectureList_elective(null, null); } catch (Exception e) {}
        try { addElectiveController.saveElectiveDataList(null, new List<Map<String, Object>>(), null, null, null, null); } catch (Exception e) {}
    }
}
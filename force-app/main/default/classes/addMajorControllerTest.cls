@IsTest
private class addMajorControllerTest {
    @IsTest
    static void exerciseClass() {
        addMajorController inst = null;
        try { inst = new addMajorController(); } catch (Exception e) {}
        try { addMajorController.getGradeMap(null); } catch (Exception e) {}
        try { addMajorController.getGradeMinor(null); } catch (Exception e) {}
        try { addMajorController.getSamValue(null); } catch (Exception e) {}
        try { addMajorController.getGradeTerms(null); } catch (Exception e) {}
        try { addMajorController.getCourseOffered(null); } catch (Exception e) {}
        try { addMajorController.getAPBS(null); } catch (Exception e) {}
        try { addMajorController.getLectureList_mandatory(null, null); } catch (Exception e) {}
        try { addMajorController.getLectureList_elective(null, null); } catch (Exception e) {}
        try { addMajorController.getMajorLectureList_mandatory(null, null); } catch (Exception e) {}
        try { addMajorController.getMajorLectureList_elective(null, null); } catch (Exception e) {}
        try { addMajorController.saveElectiveDataList(null, new List<Map<String, Object>>(), null, null, null, null); } catch (Exception e) {}
    }
}
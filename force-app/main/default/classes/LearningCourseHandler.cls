public class LearningCourseHandler {

    public static void validateUniqueCourseNumber(
        List<LearningCourse> newList,
        Map<Id, LearningCourse> oldMap
    ) {

        Set<String> courseNumbers = new Set<String>();

        // Collect course numbers
        for (LearningCourse c : newList) {
            if (c.CourseNumber != null) {
                courseNumbers.add(c.CourseNumber);
            }
        }

        if (courseNumbers.isEmpty()) return;

        // Query existing records
        Map<String, LearningCourse> existingMap = new Map<String, LearningCourse>();

        for (LearningCourse c : [
            SELECT Id, CourseNumber 
            FROM LearningCourse 
            WHERE CourseNumber IN :courseNumbers
        ]) {
            existingMap.put(c.CourseNumber, c);
        }

        // Validate duplicates
        for (LearningCourse c : newList) {

            if (c.CourseNumber == null) continue;
        
            if (existingMap.containsKey(c.CourseNumber)) {
        
                LearningCourse existing = existingMap.get(c.CourseNumber);
        
                if (c.Id == null || c.Id != existing.Id) {
                    
                    // 🔥 CHANGE HERE
                    c.CourseNumber.addError('Course code must be unique.');
                }
            }
        }
    }
}
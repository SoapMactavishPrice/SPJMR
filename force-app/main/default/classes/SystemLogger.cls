public class SystemLogger {

    /**
     * Logs an error into System_Error_Log__c
     * @param className   - Name of the class
     * @param methodName  - Name of the method
     * @param ex          - Exception object
     * @param recordId    - (Optional) Related record Id
     * @param severity    - (Optional) Error severity
     */
    public static void logError(String className, String methodName, Exception ex, Id recordId) {
        try {
            System_Log__c log = new System_Log__c();
            log.Class_Name__c   = className;
            log.Method_Name__c  = methodName;
            log.Error_Message__c = ex.getMessage()+'-'+ex.getStackTraceString();
            log.Record_Id__c    = (recordId != null) ? recordId : null;
            insert log;
        } catch (Exception e) {
            // If logging fails, at least show debug
            System.debug('Logging Failed: ' + e.getMessage());
        }
    }

    /**
     * Logs custom message (not only exceptions)
     */
    public static void logMessage(String className, String methodName, String message) {
        try {
            System_Log__c log = new System_Log__c();
            log.Class_Name__c   = className;
            log.Method_Name__c  = methodName;
            log.Error_Message__c = message;

            insert log;
        } catch (Exception e) {
            System.debug('Logging Failed: ' + e.getMessage());
        }
    }
}
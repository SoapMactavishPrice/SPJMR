@IsTest
private class SystemLoggerTest {
    @IsTest
    static void logErrorWithExceptionAndRecordId() {
        try {
            throw new System.IllegalArgumentException('boom');
        } catch (Exception ex) {
            SystemLogger.logError('ClassA', 'methodA', ex, UserInfo.getUserId());
            SystemLogger.logError('ClassA', 'methodA', ex, null);
        }
    }
    @IsTest
    static void logMessagePath() {
        SystemLogger.logMessage('ClassB', 'methodB', 'hello world');
    }
}
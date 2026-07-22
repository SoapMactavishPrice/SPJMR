global class AttendanceSyncScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {

        System.debug('===== Scheduled Job Triggered =====');

        AttendanceSyncBatch batch = new AttendanceSyncBatch();
        Database.executeBatch(batch, 200);
    }
}
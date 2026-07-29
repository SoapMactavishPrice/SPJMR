/**
 * @class   DaySyncController
 * @purpose Controller for the DaySync Visualforce page, which backs the "Sync"
 *          list-view button on Attendance_Log__c.
 *
 *          The user picks a single PAST date (within the last MAX_LOOKBACK_DAYS)
 *          and clicks Submit. This fires BiometricAttendanceBatch for that whole
 *          IST day with chainMarking = true, so the fetched punches are pulled
 *          from ESSL, stored as Attendance_Log__c, and then marked
 *          Present/Absent on Session_Enrollment__c for that date.
 *
 *          Cancel is handled client-side (navigates back to the list); Submit
 *          is disabled client-side while the date is empty. Server-side
 *          validation is authoritative: the date must be non-null, strictly in
 *          the past (IST), and no older than MAX_LOOKBACK_DAYS.
 */
public with sharing class DaySyncController {

    private static final String  IST_TZ            = 'Asia/Kolkata';
    private static final Integer IST_OFFSET_MIN    = 330; // IST = UTC + 5:30
    private static final Integer MAX_LOOKBACK_DAYS = 90;
    private static final Integer BATCH_SCOPE       = 200;

    /** Bound to the date input on the page. */
    public Date    selectedDate  { get; set; }
    public String  resultMessage { get; private set; }
    public Boolean isSuccess     { get; private set; }

    public DaySyncController() {
        this.isSuccess = false;
    }

    /**
     * Earliest selectable date (yyyy-MM-dd), for the input's `min` attribute.
     * @return MAX_LOOKBACK_DAYS before today (IST)
     */
    public String getMinDateStr() {
        return String.valueOf(todayIst().addDays(-MAX_LOOKBACK_DAYS));
    }

    /**
     * Latest selectable date (yyyy-MM-dd), for the input's `max` attribute.
     * @return yesterday (IST) — today and future are not selectable
     */
    public String getMaxDateStr() {
        return String.valueOf(todayIst().addDays(-1));
    }

    /**
     * Page action for the Submit button. Validates the date, then fires the
     * fetch-and-mark batch for that whole IST day.
     * @return null (the page re-renders in place)
     */
    public PageReference submit() {
        try {
            validate(selectedDate);
            guardNoRunningJob();

            Datetime dayStart = istMidnightAsUtc(selectedDate);
            Datetime dayEnd   = istMidnightAsUtc(selectedDate.addDays(1));

            Id jobId = Database.executeBatch(
                new BiometricAttendanceBatch(dayStart, dayEnd, true), BATCH_SCOPE);

            this.isSuccess     = true;
            this.resultMessage = 'Sync started for ' + selectedDate.format()
                + '. Punches for that day are being fetched from the biometric '
                + 'device and attendance is being marked in the background. '
                + '(Job Id: ' + jobId + ')';
        } catch (SyncException se) {
            this.isSuccess     = false;
            this.resultMessage = se.getMessage();
        } catch (Exception e) {
            this.isSuccess     = false;
            this.resultMessage = 'Could not start Sync: ' + e.getMessage();
        }
        return null;
    }

    /**
     * Rejects a null, today/future, or too-old date.
     * @param d the user-selected date (IST calendar date)
     */
    private void validate(Date d) {
        if (d == null) {
            throw new SyncException('Please select a date.');
        }
        Date today = todayIst();
        if (d >= today) {
            throw new SyncException(
                'Please select a past date. Today and future dates are not allowed.');
        }
        if (d < today.addDays(-MAX_LOOKBACK_DAYS)) {
            throw new SyncException(
                'Date is too far back. Please pick a date within the last '
                + MAX_LOOKBACK_DAYS + ' days.');
        }
    }

    /** Blocks stacking a manual sync on top of an in-flight fetch or backfill. */
    private void guardNoRunningJob() {
        Integer running = [
            SELECT COUNT()
            FROM   AsyncApexJob
            WHERE  ApexClass.Name IN ('BiometricAttendanceBatch', 'AttendanceBackfillBatch')
              AND  Status IN ('Queued', 'Processing', 'Preparing', 'Holding')
        ];
        if (running > 0) {
            throw new SyncException(
                'A sync is already running. Please wait for it to finish.');
        }
    }

    /** Today's calendar date in IST. */
    private static Date todayIst() {
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', IST_TZ));
    }

    /**
     * The UTC instant of 00:00 IST on the given date, matching how
     * BiometricAttendanceScheduler constructs its windows.
     * @param d IST calendar date
     * @return the equivalent UTC Datetime
     */
    private static Datetime istMidnightAsUtc(Date d) {
        return Datetime.newInstanceGmt(d.year(), d.month(), d.day(), 0, 0, 0)
                       .addMinutes(-IST_OFFSET_MIN);
    }

    /** Thrown for user-facing validation / guard failures. */
    public class SyncException extends Exception {}
}
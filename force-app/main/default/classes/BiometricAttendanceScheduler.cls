/**
 * @class   BiometricAttendanceScheduler
 * @purpose Anchors and launches BiometricAttendanceBatch, which pulls raw punches
 *          from the eSSL device API into Attendance_Log__c.
 *
 *          Eight jobs per day, all 7 days of the week (cron is evaluated in the
 *          scheduling user's timezone, IST for this org):
 *            Biometric_Sync_08H .. _20H   '0 0 <h> ? * *'   every 2h, 08:00-20:00
 *            Biometric_Sync_23H39M_Final  '0 39 23 ? * *'   the final sweep
 *
 *          DAYTIME runs pass an ANCHOR time, giving a rolling 2-hour window
 *          [anchor - 2h, anchor]. The anchor is snapped to the nearest SCHEDULED
 *          hour rather than Datetime.now(), so a job that fires late still asks
 *          the device for the same window — execution drift cannot open a gap.
 *
 *          The FINAL SWEEP passes an explicit, much wider window so any punch the
 *          device reported late still lands. See FINAL_WINDOW_DAYS_BACK.
 *
 * @suppress ApexCRUDViolation — the CronTrigger reads below are platform job
 *           metadata used purely to schedule and inspect this job, not user data.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class BiometricAttendanceScheduler implements Schedulable {

    private static final String  IST_TZ          = 'Asia/Kolkata';
    private static final Integer IST_OFFSET_MIN  = 330; // IST = UTC + 5:30, no DST

    private static final List<Integer> SCHEDULED_HOURS =
        new List<Integer>{ 8, 10, 12, 14, 16, 18, 20 };

    private static final Integer LAST_DAYTIME_HOUR = 20;
    private static final Integer FINAL_HOUR        = 23;
    private static final Integer FINAL_MINUTE      = 39;

    private static final Integer FINAL_WINDOW_START_HOUR = 6;

    // How many days back the 23:39 final sweep starts from.
    // 0 = today 06:00 IST (old behaviour)
    // 1 = PREVIOUS day 06:00 IST, so the sweep re-pulls ~42 hours and picks up
    //     any punch the device reported late, after the previous day's sweep ran.
    // private static final Integer FINAL_WINDOW_DAYS_BACK = 0; // old: same-day 06:00
    private static final Integer FINAL_WINDOW_DAYS_BACK = 1;

    private static final Integer BATCH_SCOPE       = 200;

    private static final String JOB_PREFIX = 'Biometric_Sync_';

    /** True on the 23:39 job, which uses the wide explicit window. */
    public Boolean isFinalSweep = false;

    /** Default constructor — a daytime (anchored 2-hour window) run. */
    @SuppressWarnings('PMD.EmptyStatementBlock')
    public BiometricAttendanceScheduler() {}

    /**
     * Builds a scheduler instance for a specific job type.
     * @param isFinalSweep true for the 23:39 job, false for a daytime run
     */
    public BiometricAttendanceScheduler(Boolean isFinalSweep) {
        this.isFinalSweep = isFinalSweep;
    }

    /**
     * Scheduler entry point. Launches the fetch batch over the window this job
     * is responsible for.
     * @param ctx the schedulable context (unused)
     */
    public void execute(SchedulableContext ctx) {
        if (isFinalSweep) {
            Datetime windowEnd   = Datetime.now();
            // Datetime windowStart = istHourAsUtc(todayIst(), LAST_DAYTIME_HOUR); // old: 20:00 IST
            // Datetime windowStart = istHourAsUtc(todayIst(), FINAL_WINDOW_START_HOUR); // old: today 06:00 IST
            Datetime windowStart = istHourAsUtc(
                todayIst().addDays(-FINAL_WINDOW_DAYS_BACK), FINAL_WINDOW_START_HOUR); // previous day 06:00 IST
            // Safety net: if the cron somehow fires before the window start IST, or
            // drifts across midnight, fall back to a 2-hour window so we never request
            // a non-positive or future-spanning range.
            if (windowEnd <= windowStart) {
                windowStart = windowEnd.addHours(-2);
            }
            Database.executeBatch(
                new BiometricAttendanceBatch(windowStart, windowEnd), BATCH_SCOPE);
            return;
        }

        Database.executeBatch(
            new BiometricAttendanceBatch(resolveAnchorTime()), BATCH_SCOPE);
    }

    /**
     * Snaps "now" to the nearest SCHEDULED_HOURS entry so the requested window is
     * identical whether the job fires on time, early or late.
     * @return the anchor instant, always on the hour
     */
    @TestVisible
    private static Datetime resolveAnchorTime() {
        Datetime now         = Datetime.now();
        Integer  currentHour = now.hour();

        Integer closestHour = SCHEDULED_HOURS[0];
        Integer minDiff     = Math.abs(currentHour - closestHour);

        for (Integer h : SCHEDULED_HOURS) {
            Integer diff = Math.abs(currentHour - h);
            if (diff < minDiff) {
                minDiff     = diff;
                closestHour = h;
            }
        }

        return Datetime.newInstance(
            now.year(), now.month(), now.day(), closestHour, 0, 0
        );
    }

    /**
     * Today's calendar date in IST.
     * @return the IST calendar date
     */
    private static Date todayIst() {
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', IST_TZ));
    }

    /**
     * The UTC instant of a given IST wall-clock hour on a given date.
     * @param  d    the IST calendar date
     * @param  hour the IST hour
     * @return the equivalent UTC Datetime
     */
    private static Datetime istHourAsUtc(Date d, Integer hour) {
        return Datetime.newInstanceGmt(d.year(), d.month(), d.day(), hour, 0, 0)
                       .addMinutes(-IST_OFFSET_MIN);
    }

    /**
     * Registers all 8 jobs, replacing any that already exist.
     * @return the job names that were scheduled
     */
    public static List<String> scheduleAll() {
        abortAll();
        List<String> scheduled = new List<String>();

        for (Integer hour : SCHEDULED_HOURS) {
            String hh      = String.valueOf(hour).leftPad(2, '0');
            String jobName = JOB_PREFIX + hh + 'H';
            System.schedule(jobName, '0 0 ' + hour + ' ? * *',
                            new BiometricAttendanceScheduler(false));
            scheduled.add(jobName);
        }

        String finalJob = JOB_PREFIX + String.valueOf(FINAL_HOUR).leftPad(2, '0')
                          + 'H' + FINAL_MINUTE + 'M_Final';
        System.schedule(finalJob, '0 ' + FINAL_MINUTE + ' ' + FINAL_HOUR + ' ? * *',
                        new BiometricAttendanceScheduler(true));
        scheduled.add(finalJob);

        return scheduled;
    }

    /**
     * Aborts every scheduled job belonging to this scheduler. Required before the
     * class can be modified — Salesforce blocks edits while jobs are pending.
     * @return the job names that were aborted
     */
    public static List<String> abortAll() {
        List<String> aborted = new List<String>();
        for (CronTrigger ct : [
            SELECT Id, CronJobDetail.Name FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :(JOB_PREFIX + '%')
        ]) {
            System.abortJob(ct.Id);
            aborted.add(ct.CronJobDetail.Name);
        }
        return aborted;
    }

    /**
     * Reports the current schedule. Returns the rows rather than logging them so
     * the caller (anonymous Apex, a test) can inspect them.
     * @return one "name | State | Next | Last" line per scheduled job
     */
    public static List<String> checkSchedule() {
        List<String> lines = new List<String>();
        for (CronTrigger ct : [
            SELECT CronJobDetail.Name, State, NextFireTime, PreviousFireTime
            FROM   CronTrigger
            WHERE  CronJobDetail.Name LIKE :(JOB_PREFIX + '%')
            ORDER BY NextFireTime ASC
        ]) {
            lines.add(ct.CronJobDetail.Name
                + ' | State: ' + ct.State
                + ' | Next: '  + ct.NextFireTime
                + ' | Last: '  + ct.PreviousFireTime);
        }
        return lines;
    }
}
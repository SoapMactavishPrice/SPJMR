/**
 * @class   BiometricAttendanceScheduler
 * @purpose Triggers BiometricAttendanceBatch (Transaction Log sync from ESSL)
 *          at fixed times.
 *
 *          Two modes:
 *            DAYTIME  — fires every 2 hours from 08:00 to 20:00 IST. Each
 *                       run uses an anchored 2-hour window so it is immune
 *                       to early/late execution drift.
 *            FINAL    — fires once at 23:39 IST. Pulls everything from the
 *                       last daytime sync (20:00 IST) up to now() so no late
 *                       evening punch is missed. Window is dynamic, not 2h.
 *
 * Schedule: 08:00, 10:00, 12:00, 14:00, 16:00, 18:00, 20:00  +  23:39 final.
 *           All 7 days (Monday to Sunday).
 */
public class BiometricAttendanceScheduler implements Schedulable {

    private static final String  IST_TZ          = 'Asia/Kolkata';
    private static final Integer IST_OFFSET_MIN  = 330; // IST = UTC + 5:30, no DST

    private static final List<Integer> SCHEDULED_HOURS =
        new List<Integer>{ 8, 10, 12, 14, 16, 18, 20 };

    private static final Integer LAST_DAYTIME_HOUR = 20;
    private static final Integer FINAL_HOUR        = 23;
    private static final Integer FINAL_MINUTE      = 39;

    // Records are returned from BiometricAttendanceBatch.start() and inserted in
    // chunks of this size, keeping each insert within DML row limits.
    private static final Integer BATCH_SCOPE       = 200;

    // Serialised with the scheduled instance so daytime and final jobs behave differently.
    public Boolean isFinalSweep = false;

    public BiometricAttendanceScheduler() {}
    public BiometricAttendanceScheduler(Boolean isFinalSweep) {
        this.isFinalSweep = isFinalSweep;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXECUTE
    // ─────────────────────────────────────────────────────────────────────────
    public void execute(SchedulableContext ctx) {
        if (isFinalSweep) {
            Datetime windowEnd   = Datetime.now();
            Datetime windowStart = istHourAsUtc(todayIst(), LAST_DAYTIME_HOUR);
            // Safety net: if the cron somehow fires before 20:00 IST, or drifts
            // across midnight, fall back to a 2-hour window so we never request
            // a non-positive or future-spanning range.
            if (windowEnd <= windowStart) {
                windowStart = windowEnd.addHours(-2);
            }
            System.debug('BiometricAttendanceScheduler | FINAL | Window: '
                + windowStart + '  →  ' + windowEnd);
            Database.executeBatch(
                new BiometricAttendanceBatch(windowStart, windowEnd), BATCH_SCOPE);
            return;
        }

        Datetime anchor = resolveAnchorTime();
        System.debug('BiometricAttendanceScheduler | DAYTIME | Anchor: '
            + anchor + '  Actual: ' + Datetime.now());
        Database.executeBatch(new BiometricAttendanceBatch(anchor), BATCH_SCOPE);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Resolves the intended anchor regardless of execution drift.
    //   Fires at 8:07 AM  → anchor = 8:00 AM  ✅
    //   Fires at 7:59 AM  → anchor = 8:00 AM  ✅
    //   Fires at 9:55 AM  → anchor = 10:00 AM ✅
    // ─────────────────────────────────────────────────────────────────────────
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

    // ── IST helpers ──────────────────────────────────────────────────────────
    private static Date todayIst() {
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', IST_TZ));
    }

    // UTC instant corresponding to the given IST clock hour on the given IST date.
    private static Datetime istHourAsUtc(Date d, Integer hour) {
        return Datetime.newInstanceGmt(d.year(), d.month(), d.day(), hour, 0, 0)
                       .addMinutes(-IST_OFFSET_MIN);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCHEDULE MANAGEMENT
    // ─────────────────────────────────────────────────────────────────────────

    public static void scheduleAll() {
        abortAll();

        for (Integer hour : SCHEDULED_HOURS) {
            String hh      = String.valueOf(hour).leftPad(2, '0');
            String jobName = 'Biometric_Sync_' + hh + 'H';
            String cron    = '0 0 ' + hour + ' ? * *';
            System.schedule(jobName, cron, new BiometricAttendanceScheduler(false));
            System.debug('Scheduled → ' + jobName + '  Cron: ' + cron);
        }

        String finalJob  = 'Biometric_Sync_'
                           + String.valueOf(FINAL_HOUR).leftPad(2, '0')
                           + 'H' + FINAL_MINUTE + 'M_Final';
        String finalCron = '0 ' + FINAL_MINUTE + ' ' + FINAL_HOUR + ' ? * *';
        System.schedule(finalJob, finalCron, new BiometricAttendanceScheduler(true));
        System.debug('Scheduled → ' + finalJob + '  Cron: ' + finalCron);

        System.debug('BiometricAttendanceScheduler: '
            + (SCHEDULED_HOURS.size() + 1)
            + ' jobs scheduled (all 7 days, incl. Sunday).');
    }

    public static void abortAll() {
        for (CronTrigger ct : [
            SELECT Id, CronJobDetail.Name FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Biometric_Sync_%'
        ]) {
            System.abortJob(ct.Id);
            System.debug('Aborted: ' + ct.CronJobDetail.Name);
        }
    }

    public static void checkSchedule() {
        for (CronTrigger ct : [
            SELECT CronJobDetail.Name, State, NextFireTime, PreviousFireTime
            FROM   CronTrigger
            WHERE  CronJobDetail.Name LIKE 'Biometric_Sync_%'
            ORDER BY NextFireTime ASC
        ]) {
            System.debug(ct.CronJobDetail.Name
                + ' | State: ' + ct.State
                + ' | Next: '  + ct.NextFireTime
                + ' | Last: '  + ct.PreviousFireTime);
        }
    }
}
public class DaySyncSessionResult implements Comparable {

    private static final String IST_TZ = 'Asia/Kolkata';

    private static final String VAL_PRESENT    = 'Present';
    private static final String VAL_ABSENT     = 'Absent';
    private static final String VAL_NOT_MARKED = 'Not Marked';

    public Id sessionId { get; private set; }

    public String sessionName { get; private set; }

    public Datetime startTime { get; private set; }

    public Datetime endTime { get; private set; }

    public Integer total { get; private set; }

    public Integer changed { get; private set; }

    public Integer newPresent { get; private set; }

    public Integer newAbsent { get; private set; }

    public Integer beforePresent { get; private set; }

    public Integer beforeAbsent { get; private set; }

    public Integer beforeNotMarked { get; private set; }

    public Integer beforeOther { get; private set; }

    public Integer afterPresent { get; private set; }

    public Integer afterAbsent { get; private set; }

    public Integer afterNotMarked { get; private set; }

    public Integer afterOther { get; private set; }

    public DaySyncSessionResult(Id sessionId, Session__c session) {
        this.sessionId   = sessionId;
        this.sessionName = session == null ? '(unnamed session)' : session.Name;
        this.startTime   = session == null ? null : session.Start_Time__c;
        this.endTime     = session == null ? null : session.End_Time__c;

        this.total      = 0;
        this.changed    = 0;
        this.newPresent = 0;
        this.newAbsent  = 0;

        this.beforePresent   = 0;
        this.beforeAbsent    = 0;
        this.beforeNotMarked = 0;
        this.beforeOther     = 0;

        this.afterPresent   = 0;
        this.afterAbsent    = 0;
        this.afterNotMarked = 0;
        this.afterOther     = 0;
    }

    public void add(String rawBefore, String rawAfter) {
        String beforeVal = norm(rawBefore);
        String afterVal  = norm(rawAfter);

        this.total++;
        bumpBefore(beforeVal);
        bumpAfter(afterVal);

        if (beforeVal == afterVal) {
            return;
        }
        this.changed++;
        if (VAL_PRESENT.equals(afterVal)) {
            this.newPresent++;
        } else if (VAL_ABSENT.equals(afterVal)) {
            this.newAbsent++;
        }
    }

    private static String norm(String val) {
        return String.isBlank(val) ? VAL_NOT_MARKED : val;
    }


    private void bumpBefore(String val) {
        if (VAL_PRESENT.equals(val)) {
            this.beforePresent++;
        } else if (VAL_ABSENT.equals(val)) {
            this.beforeAbsent++;
        } else if (VAL_NOT_MARKED.equals(val)) {
            this.beforeNotMarked++;
        } else {
            this.beforeOther++;
        }
    }


    private void bumpAfter(String val) {
        if (VAL_PRESENT.equals(val)) {
            this.afterPresent++;
        } else if (VAL_ABSENT.equals(val)) {
            this.afterAbsent++;
        } else if (VAL_NOT_MARKED.equals(val)) {
            this.afterNotMarked++;
        } else {
            this.afterOther++;
        }
    }
    public String getTimeRange() {
        if (startTime == null) {
            return '—';
        }
        String fromStr = startTime.format('hh:mm a', IST_TZ);
        String toStr   = endTime == null ? '?' : endTime.format('hh:mm a', IST_TZ);
        return fromStr + ' – ' + toStr;
    }

    public String getDateStr() {
        return startTime == null ? '' : startTime.format('dd MMM yyyy', IST_TZ);
    }


    public String getPresentDelta() {
        Integer diff = afterPresent - beforePresent;
        return diff > 0 ? '+' + diff : String.valueOf(diff);
    }

    public Boolean getIsUnchanged() {
        return changed == 0;
    }

    public Integer compareTo(Object other) {
        DaySyncSessionResult that = (DaySyncSessionResult) other;
        if (this.startTime == null || that.startTime == null) {
            return nullOrder(that);
        }
        if (this.startTime < that.startTime) {
            return -1;
        }
        return this.startTime > that.startTime ? 1 : 0;
    }


    private Integer nullOrder(DaySyncSessionResult that) {
        if (this.startTime == null && that.startTime == null) {
            return 0;
        }
        return this.startTime == null ? 1 : -1;
    }
}
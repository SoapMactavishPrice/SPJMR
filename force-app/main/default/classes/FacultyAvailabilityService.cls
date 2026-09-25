/**
 * @description Read-only availability source for the Academic Scheduler's on-grid overlay: given a
 *          set of faculty and a date range, reports WHEN each faculty is busy in Google Calendar
 *          and nothing else. Uses Google's freeBusy API, which returns bare busy intervals with no
 *          event details, so the privacy promise (AC4) is kept by the API rather than by stripping
 *          fields on our side — the DTOs deliberately have no title/description/attendee member.
 *
 *          One token, one callout per 50 calendars: the impersonation subject is the configured
 *          Google_Calendar_Config__mdt user (as GoogleCalendarHelper reports it), not each faculty,
 *          so selecting every faculty on the grid still costs a single callout.
 *
 * @note    Parallel to FacultyCalendarConflictService, never a replacement: the Save/Publish
 *          conflict check keeps its own events.list path untouched (AC8).
 * @note    Fail-open, matching the rest of the integration: any auth/HTTP/parse failure returns the
 *          faculty rows with empty busy lists rather than throwing, so the scheduler still works
 *          when Google is unreachable.
 * @note    A calendar Google reports an error for (unreadable, external, outside the domain) comes
 *          back as free — an empty busy list, by explicit decision. There is no "unknown" state.
 */
// ApexSuggestUsingNamedCred suppressed: reuses the existing service-account JWT auth
// (GoogleAuthService) that the rest of the calendar integration uses.
// ApexCRUDViolation suppressed: the Account read is a name/email lookup for an internal callout
// payload only; no faculty email is ever returned to the caller and nothing is written.
@SuppressWarnings('PMD.ApexSuggestUsingNamedCred,PMD.ApexCRUDViolation')
public with sharing class FacultyAvailabilityService {

    private static final String CONFIG_NAME = 'Default';
    private static final String FREEBUSY_URL = 'https://www.googleapis.com/calendar/v3/freeBusy';
    /** Google accepts at most 50 calendars in one freeBusy request. */
    private static final Integer MAX_CALENDARS_PER_CALL = 50;
    /** Same cap the Save/Publish check uses, well under the 100-callout governor limit. */
    private static final Integer CALLOUT_CAP = 45;

    /**
     * @description One faculty's busy periods over the requested range. Carries no email — the
     *          faculty's address is used only to build the Google request and never leaves Apex.
     */
    public class FacultyAvailability {
        /** @description The faculty Account id the grid asked about. */
        @AuraEnabled public String facultyId { get; set; }
        /** @description The faculty's name, for the overlay label. */
        @AuraEnabled public String facultyName { get; set; }
        /** @description When this faculty is busy; empty means free as far as we can tell. */
        @AuraEnabled public List<BusyBlock> busy { get; set; }
    }

    /**
     * @description One busy interval. Intentionally has no summary/title/description member so a
     *          calendar detail cannot be leaked even by mistake.
     */
    public class BusyBlock {
        /** @description When the busy period starts. */
        @AuraEnabled public Datetime startTime { get; set; }
        /** @description When the busy period ends. */
        @AuraEnabled public Datetime endTime { get; set; }
    }

    /**
     * @description The three values every freeBusy request in a run shares: the token and the
     *          window. Kept together so the chunk loop stays readable.
     */
    private class FreeBusyCall {
        private final String token;
        private final String timeMin;
        private final String timeMax;

        /**
         * @description Builds the call context.
         * @param token A valid OAuth access token for the impersonation subject.
         * @param windowStart Start of the requested range in the running user's timezone.
         * @param windowEnd Exclusive end of the requested range in the running user's timezone.
         */
        private FreeBusyCall(String token, Datetime windowStart, Datetime windowEnd) {
            this.token = token;
            this.timeMin = toRfc3339(windowStart);
            this.timeMax = toRfc3339(windowEnd);
        }
    }

    /**
     * @description Returns each requested faculty's busy intervals between the start of rangeStart
     *          and the end of rangeEnd, both read in the running user's timezone because the grid
     *          is drawn in local time. Performs one Google callout per 50 faculty.
     * @param facultyIds Faculty Account ids as sent by the grid; blank, malformed and unresolved
     *          ids are ignored, duplicates collapse to one row.
     * @param rangeStart First day of the grid window, inclusive.
     * @param rangeEnd Last day of the grid window, inclusive.
     * @return One row per resolved faculty, each with its busy blocks (empty when free, when the
     *          faculty has no email, when Google reports that calendar as unreadable, or on any
     *          handled failure). Empty list for no input, an inverted range, or when the Google
     *          Calendar integration is switched off.
     */
    @AuraEnabled(cacheable=false)
    public static List<FacultyAvailability> getAvailability(
        List<String> facultyIds, Date rangeStart, Date rangeEnd
    ) {
        List<FacultyAvailability> rows = new List<FacultyAvailability>();
        if (!isUsableRequest(facultyIds, rangeStart, rangeEnd)) {
            return rows;
        }

        Map<String, List<FacultyAvailability>> rowsByEmail = new Map<String, List<FacultyAvailability>>();
        rows = buildRows(facultyIds, rowsByEmail);
        if (rows.isEmpty() || rowsByEmail.isEmpty()) {
            return rows; // nothing resolved, or nobody has an email — every row is free
        }

        try {
            String token = GoogleAuthService.getAccessToken(GoogleCalendarHelper.getUserEmail(CONFIG_NAME));
            if (String.isNotBlank(token)) {
                readBusy(
                    new FreeBusyCall(
                        token, startOfDayLocal(rangeStart), startOfDayLocal(rangeEnd.addDays(1))
                    ),
                    rowsByEmail
                );
            }
        } catch (Exception e) {
            return rows; // fail-open: the grid shows no busy blocks rather than erroring
        }
        return rows;
    }

    /**
     * @description Whether this request is worth a Google callout: some faculty, a range that runs
     *          forwards, and the calendar integration switched on.
     * @param facultyIds The ids from the caller.
     * @param rangeStart First day of the grid window.
     * @param rangeEnd Last day of the grid window.
     * @return True when the request should be served.
     */
    private static Boolean isUsableRequest(List<String> facultyIds, Date rangeStart, Date rangeEnd) {
        if (facultyIds == null || facultyIds.isEmpty() || rangeStart == null || rangeEnd == null) {
            return false;
        }
        return rangeEnd >= rangeStart && GoogleCalendarHelper.isActive();
    }

    /**
     * @description Resolves the requested ids to faculty rows in one query and indexes those rows
     *          by lower-cased email so a freeBusy response can be applied back to them.
     * @param facultyIds The raw ids from the caller.
     * @param rowsByEmail Out-parameter: lower-cased email to the rows that use it (two faculty
     *          records sharing an address both receive the same busy blocks).
     * @return The rows, in the order the ids were requested, one per resolved faculty.
     */
    private static List<FacultyAvailability> buildRows(
        List<String> facultyIds, Map<String, List<FacultyAvailability>> rowsByEmail
    ) {
        List<FacultyAvailability> rows = new List<FacultyAvailability>();
        List<Id> lookupIds = validIds(facultyIds);
        if (lookupIds.isEmpty()) {
            return rows;
        }
        // sfge ApexFlsViolation suppressed: a read of the faculty's own name and address purely to
        // address the Google request. No field value is written and the email is never returned.
        /* sfge-disable-next-line ApexFlsViolation */
        Map<Id, Account> facultyById = new Map<Id, Account>([
            SELECT Id, Name, PersonEmail FROM Account WHERE Id IN :lookupIds
        ]);
        for (Id facultyId : lookupIds) {
            Account faculty = facultyById.get(facultyId);
            if (faculty == null) {
                continue;
            }
            FacultyAvailability row = new FacultyAvailability();
            row.facultyId = String.valueOf(faculty.Id);
            row.facultyName = faculty.Name;
            row.busy = new List<BusyBlock>();
            rows.add(row);
            String email = faculty.PersonEmail;
            if (String.isBlank(email)) {
                continue; // still gets a row, just permanently free — the grid needs the row
            }
            String key = email.toLowerCase().trim();
            if (!rowsByEmail.containsKey(key)) {
                rowsByEmail.put(key, new List<FacultyAvailability>());
            }
            rowsByEmail.get(key).add(row);
        }
        return rows;
    }

    /**
     * @description Keeps only the well-formed, distinct ids from the caller's list, in the order
     *          they were requested.
     * @param facultyIds The raw ids from the caller.
     * @return The usable Account ids.
     */
    private static List<Id> validIds(List<String> facultyIds) {
        List<Id> result = new List<Id>();
        Set<Id> seen = new Set<Id>();
        for (String raw : facultyIds) {
            if (String.isBlank(raw)) {
                continue;
            }
            try {
                Id facultyId = Id.valueOf(raw.trim());
                if (seen.add(facultyId)) {
                    result.add(facultyId);
                }
            } catch (Exception e) {
                continue; // a malformed id is simply not a faculty we can report on
            }
        }
        return result;
    }

    /**
     * @description Calls freeBusy in chunks of 50 calendars and fills each row's busy list.
     *          Stops cleanly once the callout cap is reached; the faculty not yet read stay free.
     *          Each chunk is isolated: a gateway serving a 200 with an HTML body would otherwise
     *          throw out of the loop and report every later faculty as free, which is the wrong
     *          direction to fail for a double-booking guard.
     * @param call The token and time window shared by every request in this run.
     * @param rowsByEmail Lower-cased email to the rows awaiting busy blocks.
     */
    private static void readBusy(
        FreeBusyCall call, Map<String, List<FacultyAvailability>> rowsByEmail
    ) {
        List<String> emails = new List<String>(rowsByEmail.keySet());
        Integer callouts = 0;
        for (Integer chunkStart = 0; chunkStart < emails.size(); chunkStart += MAX_CALENDARS_PER_CALL) {
            if (callouts >= CALLOUT_CAP) {
                break;
            }
            Integer chunkEnd = Math.min(chunkStart + MAX_CALENDARS_PER_CALL, emails.size());
            List<String> chunk = new List<String>();
            for (Integer i = chunkStart; i < chunkEnd; i++) {
                chunk.add(emails[i]);
            }
            callouts++;
            try {
                applyChunk(chunk, call, rowsByEmail);
            } catch (Exception e) {
                continue; // this chunk's faculty stay free; the remaining chunks are still read
            }
        }
    }

    /**
     * @description Sends one freeBusy request for up to 50 calendars and copies the returned busy
     *          intervals onto the matching rows. A non-200 or unparseable body leaves those rows
     *          free (fail-open).
     * @param emails The calendars for this request.
     * @param call The token and time window shared by every request in this run.
     * @param rowsByEmail Lower-cased email to the rows awaiting busy blocks.
     */
    private static void applyChunk(
        List<String> emails, FreeBusyCall call, Map<String, List<FacultyAvailability>> rowsByEmail
    ) {
        HttpResponse res = new Http().send(buildRequest(emails, call));
        if (res.getStatusCode() != 200) {
            return;
        }
        Object rawCalendars = ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('calendars');
        if (!(rawCalendars instanceof Map<String, Object>)) {
            return;
        }
        Map<String, Object> calendars = (Map<String, Object>) rawCalendars;
        for (String calendarId : calendars.keySet()) {
            List<FacultyAvailability> targets = rowsByEmail.get(calendarId.toLowerCase().trim());
            if (targets == null) {
                continue;
            }
            List<BusyBlock> blocks = busyBlocks(calendars.get(calendarId));
            for (FacultyAvailability row : targets) {
                row.busy.addAll(blocks);
            }
        }
    }

    /**
     * @description Pure parser: turns one calendars[<id>] node into busy blocks. A node carrying an
     *          errors entry is reported as free, which is how non-domain addresses (gmail/yopmail
     *          test data) behave — deliberately not an error state.
     * @param node The calendars[<id>] value from a freeBusy response.
     * @return The busy blocks, empty when the calendar is free, errored or malformed.
     */
    @TestVisible
    private static List<BusyBlock> busyBlocks(Object node) {
        List<BusyBlock> result = new List<BusyBlock>();
        if (!(node instanceof Map<String, Object>)) {
            return result;
        }
        Map<String, Object> calendar = (Map<String, Object>) node;
        Object errors = calendar.get('errors');
        if (errors instanceof List<Object> && !((List<Object>) errors).isEmpty()) {
            return result; // unreadable calendar → reported as free
        }
        Object rawBusy = calendar.get('busy');
        if (!(rawBusy instanceof List<Object>)) {
            return result;
        }
        for (Object o : (List<Object>) rawBusy) {
            BusyBlock block = toBusyBlock(o);
            if (block != null) {
                result.add(block);
            }
        }
        return result;
    }

    /**
     * @description Turns one freeBusy busy[] entry into a block, rejecting anything unusable.
     * @param raw One element of a calendar's busy array.
     * @return The block, or null when the entry is malformed, unparseable or not a real interval.
     */
    private static BusyBlock toBusyBlock(Object raw) {
        if (!(raw instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> interval = (Map<String, Object>) raw;
        Object rawStart = interval.get('start');
        Object rawEnd = interval.get('end');
        if (!(rawStart instanceof String) || !(rawEnd instanceof String)) {
            return null; // a number or object where a timestamp belongs is not an interval
        }
        Datetime st = parseRfc3339((String) rawStart);
        Datetime en = parseRfc3339((String) rawEnd);
        if (st == null || en == null || en <= st) {
            return null;
        }
        BusyBlock block = new BusyBlock();
        block.startTime = st;
        block.endTime = en;
        return block;
    }

    /**
     * @description Builds the freeBusy POST for one chunk of calendars.
     * @param emails The calendar ids for this request.
     * @param call The token and time window shared by every request in this run.
     * @return The prepared HttpRequest.
     */
    private static HttpRequest buildRequest(List<String> emails, FreeBusyCall call) {
        List<Map<String, Object>> items = new List<Map<String, Object>>();
        for (String email : emails) {
            items.add(new Map<String, Object>{ 'id' => email });
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(FREEBUSY_URL);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + call.token);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, Object>{
            'timeMin' => call.timeMin,
            'timeMax' => call.timeMax,
            'items'   => items
        }));
        return req;
    }

    /**
     * @description Midnight of the given day in the running user's timezone — the same local
     *          wall-clock reading TimetableSessionController uses when it turns the grid's date and
     *          times into instants (Datetime.newInstance / Datetime.valueOf are both local).
     * @param day The calendar day.
     * @return The instant at which that local day starts.
     */
    private static Datetime startOfDayLocal(Date day) {
        return Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0));
    }

    /**
     * @description Renders an instant as RFC 3339 in the running user's timezone, e.g.
     *          2026-09-28T00:00:00+05:30, which is what Google expects for timeMin/timeMax.
     * @param instant The instant to render.
     * @return The RFC 3339 string with an explicit offset.
     */
    @TestVisible
    private static String toRfc3339(Datetime instant) {
        TimeZone tz = UserInfo.getTimeZone();
        return instant.format('yyyy-MM-dd\'T\'HH:mm:ss', tz.getID()) + offsetSuffix(tz.getOffset(instant));
    }

    /**
     * @description Formats a timezone offset as the RFC 3339 tail (+05:30 / -08:00 / +00:00).
     * @param offsetMillis The offset from UTC in milliseconds.
     * @return The offset tail.
     */
    private static String offsetSuffix(Integer offsetMillis) {
        Integer totalMinutes = (offsetMillis == null ? 0 : offsetMillis) / 60000;
        String sign = totalMinutes < 0 ? '-' : '+';
        Integer absMinutes = Math.abs(totalMinutes);
        return sign
            + String.valueOf(absMinutes / 60).leftPad(2, '0')
            + ':'
            + String.valueOf(Math.mod(absMinutes, 60)).leftPad(2, '0');
    }

    /**
     * @description Parses an RFC 3339 timestamp (e.g. 2026-09-28T02:00:00+05:30) to a UTC instant.
     *          Same parser shape as FacultyCalendarConflictService — copied rather than shared so
     *          the Save/Publish check is not touched (AC8).
     * @param value The RFC 3339 string.
     * @return The instant, or null when blank / malformed.
     */
    private static Datetime parseRfc3339(String value) {
        if (String.isBlank(value) || value.length() < 19) {
            return null;
        }
        try {
            Integer year = Integer.valueOf(value.substring(0, 4));
            Integer month = Integer.valueOf(value.substring(5, 7));
            Integer day = Integer.valueOf(value.substring(8, 10));
            Integer hour = Integer.valueOf(value.substring(11, 13));
            Integer minute = Integer.valueOf(value.substring(14, 16));
            Integer second = Integer.valueOf(value.substring(17, 19));
            if (!isRealDate(month, day) || !isRealTime(hour, minute, second)) {
                return null; // Apex would roll 25:99 forward into a plausible-looking wrong day
            }
            Datetime wall = Datetime.newInstanceGmt(year, month, day, hour, minute, second);
            return wall.addMinutes(-offsetMinutes(value.substring(19)));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Whether the date components of a timestamp are in range. Datetime.newInstanceGmt
     *          silently rolls out-of-range values forward, so an impossible value would otherwise
     *          become a busy block on the wrong day.
     * @param month The month component.
     * @param day The day component.
     * @return True when both are plausible calendar values.
     */
    private static Boolean isRealDate(Integer month, Integer day) {
        return month >= 1 && month <= 12 && day >= 1 && day <= 31;
    }

    /**
     * @description Whether the clock components of a timestamp are in range.
     * @param hour The hour component.
     * @param minute The minute component.
     * @param second The second component (60 allowed for a leap second).
     * @return True when all three are real clock values.
     */
    private static Boolean isRealTime(Integer hour, Integer minute, Integer second) {
        return hour >= 0 && hour <= 23
            && minute >= 0 && minute <= 59
            && second >= 0 && second <= 60;
    }

    /**
     * @description Parses the timezone offset tail of an RFC 3339 string into minutes.
     * @param tail The part after the seconds, e.g. 'Z', '+05:30', '.000+05:30', '-08:00'.
     * @return The offset in minutes (0 for UTC / 'Z' / absent).
     */
    private static Integer offsetMinutes(String tail) {
        if (String.isBlank(tail)) {
            return 0;
        }
        String t = tail;
        if (t.startsWith('.')) {
            Integer i = 1;
            while (i < t.length() && t.substring(i, i + 1).isNumeric()) {
                i++;
            }
            t = t.substring(i);
        }
        if (String.isBlank(t) || t == 'Z') {
            return 0;
        }
        Integer sign = t.startsWith('-') ? -1 : 1;
        String hhmm = t.substring(1);
        return sign * (Integer.valueOf(hhmm.substring(0, 2)) * 60 + Integer.valueOf(hhmm.substring(3, 5)));
    }
}
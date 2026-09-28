@SuppressWarnings('PMD.ApexSuggestUsingNamedCred,PMD.ApexCRUDViolation')
public with sharing class FacultyAvailabilityService {

    private static final String CONFIG_NAME = 'Default';
    private static final String FREEBUSY_URL = 'https://www.googleapis.com/calendar/v3/freeBusy';

    private static final Integer MAX_CALENDARS_PER_CALL = 50;

    private static final Integer CALLOUT_CAP = 45;

    public class FacultyAvailability {

        @AuraEnabled public String facultyId { get; set; }

        @AuraEnabled public String facultyName { get; set; }

        @AuraEnabled public List<BusyBlock> busy { get; set; }
    }

    public class BusyBlock {

        @AuraEnabled public Datetime startTime { get; set; }

        @AuraEnabled public Datetime endTime { get; set; }
    }

    private class FreeBusyCall {
        private final String token;
        private final String timeMin;
        private final String timeMax;

        private FreeBusyCall(String token, Datetime windowStart, Datetime windowEnd) {
            this.token = token;
            this.timeMin = toRfc3339(windowStart);
            this.timeMax = toRfc3339(windowEnd);
        }
    }

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
            return rows;
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
            return rows;
        }
        return rows;
    }

    private static Boolean isUsableRequest(List<String> facultyIds, Date rangeStart, Date rangeEnd) {
        if (facultyIds == null || facultyIds.isEmpty() || rangeStart == null || rangeEnd == null) {
            return false;
        }
        return rangeEnd >= rangeStart && GoogleCalendarHelper.isActive();
    }

    private static List<FacultyAvailability> buildRows(
        List<String> facultyIds, Map<String, List<FacultyAvailability>> rowsByEmail
    ) {
        List<FacultyAvailability> rows = new List<FacultyAvailability>();
        List<Id> lookupIds = validIds(facultyIds);
        if (lookupIds.isEmpty()) {
            return rows;
        }

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
                continue;
            }
            String key = email.toLowerCase().trim();
            if (!rowsByEmail.containsKey(key)) {
                rowsByEmail.put(key, new List<FacultyAvailability>());
            }
            rowsByEmail.get(key).add(row);
        }
        return rows;
    }

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
                continue;
            }
        }
        return result;
    }

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
                continue;
            }
        }
    }

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

    @TestVisible
    private static List<BusyBlock> busyBlocks(Object node) {
        List<BusyBlock> result = new List<BusyBlock>();
        if (!(node instanceof Map<String, Object>)) {
            return result;
        }
        Map<String, Object> calendar = (Map<String, Object>) node;
        Object errors = calendar.get('errors');
        if (errors instanceof List<Object> && !((List<Object>) errors).isEmpty()) {
            return result;
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

    private static BusyBlock toBusyBlock(Object raw) {
        if (!(raw instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> interval = (Map<String, Object>) raw;
        Object rawStart = interval.get('start');
        Object rawEnd = interval.get('end');
        if (!(rawStart instanceof String) || !(rawEnd instanceof String)) {
            return null;
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

    private static Datetime startOfDayLocal(Date day) {
        return Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0));
    }

    @TestVisible
    private static String toRfc3339(Datetime instant) {
        TimeZone tz = UserInfo.getTimeZone();
        return instant.format('yyyy-MM-dd\'T\'HH:mm:ss', tz.getID()) + offsetSuffix(tz.getOffset(instant));
    }

    private static String offsetSuffix(Integer offsetMillis) {
        Integer totalMinutes = (offsetMillis == null ? 0 : offsetMillis) / 60000;
        String sign = totalMinutes < 0 ? '-' : '+';
        Integer absMinutes = Math.abs(totalMinutes);
        return sign
            + String.valueOf(absMinutes / 60).leftPad(2, '0')
            + ':'
            + String.valueOf(Math.mod(absMinutes, 60)).leftPad(2, '0');
    }

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
                return null;
            }
            Datetime wall = Datetime.newInstanceGmt(year, month, day, hour, minute, second);
            return wall.addMinutes(-offsetMinutes(value.substring(19)));
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean isRealDate(Integer month, Integer day) {
        return month >= 1 && month <= 12 && day >= 1 && day <= 31;
    }

    private static Boolean isRealTime(Integer hour, Integer minute, Integer second) {
        return hour >= 0 && hour <= 23
            && minute >= 0 && minute <= 59
            && second >= 0 && second <= 60;
    }

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
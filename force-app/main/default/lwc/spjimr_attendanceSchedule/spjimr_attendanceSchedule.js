import { LightningElement, track, wire, api } from 'lwc';
import { getFileDownloadUrl } from 'lightning/fileDownload';
import getEnrolledSessions from '@salesforce/apex/StudentScheduleController.getEnrolledSessions';
import getSessionDetails from '@salesforce/apex/StudentScheduleController.getSessionDetails';
import getSessionTypeOptions from '@salesforce/apex/StudentScheduleController.getSessionTypeOptions';
import getUserInfo from '@salesforce/apex/StudentProfileDashboardController.getUserInfo';
import logo from '@salesforce/resourceUrl/Site_Logo';
import navbarIcon from '@salesforce/resourceUrl/Navbar_Icon';
import profileDummy from '@salesforce/resourceUrl/Profile_Dummy';
import programDetailsIcon from '@salesforce/resourceUrl/Program_Details';
import studentDetailsIcon from '@salesforce/resourceUrl/Student_Details';
import attendanceIcon from '@salesforce/resourceUrl/Attendance_Icon';
import examsIcon from '@salesforce/resourceUrl/Exams_Icon';
import academicsIcon from '@salesforce/resourceUrl/Academics_Icon';
import financeIcon from '@salesforce/resourceUrl/Finance_Icon';
import servicesIcon from '@salesforce/resourceUrl/Services_Icon';
import mentorIcon from '@salesforce/resourceUrl/Mentor_Icon';
import hostelIcon from '@salesforce/resourceUrl/Hostel_Icon';
import ticketIcon from '@salesforce/resourceUrl/Ticket_Icon';
import projectIcon from '@salesforce/resourceUrl/Project_Icon';
import logoutIcon from '@salesforce/resourceUrl/Logout_Icon';

// Index by JavaScript Date#getDay() (0 = Sunday … 6 = Saturday)
const DAY_NAMES_BY_GET_DAY = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
// Column headers for month grid (weeks run Monday → Sunday)
const DAY_NAMES_SHORT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const START_HOUR = 0;
const END_HOUR = 23;
// Session box colors (match academicScheduler); used for day/week/month/year views
const SESSION_COLORS = ['blue', 'green', 'purple', 'orange', 'red', 'pink'];

// SE-737U START: Map Division Color picklist values to hex so all colors render in the student schedule
/**
 * Maps Division_Color__c picklist API text (normalized: lowercase, non-alphanumerics stripped)
 * to #RRGGBB. Keep in sync with timetableCalendar.DIVISION_COLOR_HEX.
 */
const DIVISION_COLOR_HEX = {
    softpeachbeige: '#FAE3D6',
    lightsagegreen: '#9EB094',
    mutedbrown: '#B58460',
    brickred: '#BF4E4E',
    mustardyellow: '#C99500',
    teal: '#54B1AC',
    paleolive: '#B2B28D',
    steelblue: '#406EA8',
    lightgray: '#AAAFAA',
    limeyellow: '#C0C600',
    darkmaroon: '#7A3000',
    purple: '#702B99',
    blue: '#406EA8',
    gray: '#AAAFAA',
    grey: '#AAAFAA',
    green: '#9EB094',
    orange: '#F97316',
    red: '#BF4E4E',
    pink: '#EC4899'
};

function normalizeDivisionColorKey(value) {
    if (value == null || value === '') return '';
    return String(value).toLowerCase().replace(/[^a-z0-9]/g, '');
}

function resolveColorHex(rawColor) {
    if (rawColor == null) return '#406EA8';
    const s = String(rawColor).trim();
    if (/^#[0-9A-Fa-f]{6}$/.test(s)) return s.toUpperCase();
    const k = normalizeDivisionColorKey(s);
    return (k && DIVISION_COLOR_HEX[k]) ? DIVISION_COLOR_HEX[k] : '#406EA8';
}
// SE-737U END

export default class Spjimr_attendanceSchedule extends LightningElement {
    @api showLayout = false;
    @api dashboardPageRef = '';

    @track currentView = 'week';
    @track currentDate = new Date();
    @track selectedSessionType = '';
    @track sessionTypeOptions = [{ label: 'All Sessions', value: '' }];
    @track sessions = [];
    @track isLoading = true;
    @track showDetailModal = false;
    @track sessionDetail = null;
    @track detailLoading = false;
    @track selectedSessionId = null;

    // Cache for detailed session info (used to enrich hover card with faculty)
    sessionDetailsCache = {};

    siteLogoIcon = logo;
    @track temp = 'this is hover';
    navbarIconResource = navbarIcon;
    profileDummyIcon = profileDummy;
    @track isSidebarOpen = true;
    @track studentName = 'John Steve';
    @track rollNumber = '';
    @track programName = '';
    @track programCode = '';
    @track currentTerm = 'Term 2';
    @track menuItems = [
        { id: 'studentDetails', label: 'Student Details', cssClass: 'nav-item' },
        { id: 'programDetails', label: 'Program details', cssClass: 'nav-item' },
        { id: 'attendance', label: 'Attendance & Schedule', cssClass: 'nav-item selected' },
        { id: 'exams', label: 'Exams & Evaluation', cssClass: 'nav-item' },
        { id: 'academics', label: 'Academics & Learning', cssClass: 'nav-item' },
        { id: 'finance', label: 'Finance & Ledger', cssClass: 'nav-item' },
        { id: 'services', label: 'Student Services', cssClass: 'nav-item' },
        { id: 'mentorship', label: 'Mentorship & MQR', cssClass: 'nav-item' },
        { id: 'hostel', label: 'Hostel & Campus Logistics', cssClass: 'nav-item' },
        { id: 'reports', label: 'Reports & Certificates', cssClass: 'nav-item' },
        { id: 'project', label: 'Project & Capstone', cssClass: 'nav-item' },
        { id: 'tickets', label: 'Ticket management', cssClass: 'nav-item' },
        { id: 'logout', label: 'Logout', cssClass: 'nav-item' }
    ];

    // Session hover details card (shown on hover for all views)
    @track hoveredEventData = null;
    @track hoverCardStyle = null;
    _hoverCardHideTimeout = null;

    // Mouse hover handlers for events (used in day, week, month, year views)
    handleEventMouseEnter(event) {
        if (this._hoverCardHideTimeout) {
            clearTimeout(this._hoverCardHideTimeout);
            this._hoverCardHideTimeout = null;
        }
        event.stopPropagation();
        const eventElement = event.currentTarget;

        // Remove native browser tooltip to avoid overlap
        if (eventElement.hasAttribute('title')) {
            eventElement.removeAttribute('title');
        }

        const eventId = eventElement.dataset.id;
        if (!eventId) {
            this.hoveredEventData = null;
            this.hoverCardStyle = null;
            return;
        }

        // Find the full session record from the sessions returned by Apex
        const ev = (this.sessions || []).find((s) => s && s.id === eventId);
        if (!ev) {
            this.hoveredEventData = null;
            this.hoverCardStyle = null;
            return;
        }

        // Position the card just below the session with a small gap; keep on screen
        const rect = eventElement.getBoundingClientRect();
        const cardWidth = 340;
        const cardHeight = 320;
        const gap = 8;
        let left = rect.left + rect.width / 2 - cardWidth / 2;
        if (left < 8) left = 8;
        if (left + cardWidth > window.innerWidth - 8) left = window.innerWidth - cardWidth - 8;
        let top = rect.bottom + gap;
        if (top + cardHeight > window.innerHeight - 16) {
            top = Math.max(16, rect.top - cardHeight - gap);
        }
        if (top < 16) top = 16;
        this.hoverCardStyle = `top: ${top}px; left: ${left}px; width: ${cardWidth}px;`;

        // Start building hover data – use session-level values first
        const baseTitle = ev.title || 'Marketing Strategy';
        const baseDate = this.formatSessionDate(ev.sessionDate) || '08 Dec 2025';
        const baseStart = ev.startTime || '9.00AM';
        const baseEnd = ev.endTime || '10.30 AM';
        const baseLocation = ev.location || 'No Room Attached' ;
        const baseDescription =
            (ev.description && String(ev.description).trim()) || 'Not Available';
        const baseUrl = ev.url || 'Not Given';
        // Faculty from session record if available
        let instructor =
            (ev.instructorNames && String(ev.instructorNames).trim()) ||
            (ev.facultyNames && Array.isArray(ev.facultyNames) && ev.facultyNames.length > 0
                ? ev.facultyNames.join(', ')
                : '');

        const cachedDetail = this.sessionDetailsCache[eventId];
        const baseCourseName = ev.courseName;

        // If we have cached details, use them fully so re-hover shows correct url/location/etc.
        if (cachedDetail) {
            instructor = (cachedDetail.instructorNames && String(cachedDetail.instructorNames).trim()) || instructor;
            const title = cachedDetail.title || baseTitle;
            const sessionDateFormatted = cachedDetail.sessionDateFormatted || baseDate;
            const startTime = cachedDetail.startTime || baseStart;
            const endTime = cachedDetail.endTime || baseEnd;
            const location = (cachedDetail.location && String(cachedDetail.location).trim()) || baseLocation;
            const description = (cachedDetail.description && String(cachedDetail.description).trim()) || baseDescription;
            const url = (cachedDetail.url && String(cachedDetail.url).trim()) ? cachedDetail.url : baseUrl;
            const courseName = cachedDetail.courseName || baseCourseName || '';

            this.hoveredEventData = {
                title,
                instructorNames: instructor || 'Mr. Dinesh Patel',
                sessionDateFormatted,
                startTime,
                endTime,
                location,
                description,
                url,
                courseName
            };
        } else {
            // Fallback instructor if still empty (dummy, will be replaced when detail loads)
            if (!instructor) {
                instructor = 'Mr. Dinesh Patel';
            }

            this.hoveredEventData = {
                title: baseTitle,
                instructorNames: instructor,
                sessionDateFormatted: baseDate,
                startTime: baseStart,
                endTime: baseEnd,
                location: baseLocation,
                description: baseDescription,
                url: baseUrl,
                courseName : baseCourseName || ''
            };
        }

        // If we don't yet have cached details, fetch session details once to enrich the cache
        if (!cachedDetail) {
            getSessionDetails({ sessionId: eventId })
                .then((detail) => {
                    if (!detail) return;
                    this.sessionDetailsCache[eventId] = detail;

                    // If the user is still hovering this same event, update the card with real data
                    if (this.hoveredEventData && this.hoveredEventData.title === baseTitle) {
                        const enrichedInstructor = (detail.instructorNames && String(detail.instructorNames).trim()) || instructor;
                        const enrichedDate = detail.sessionDateFormatted || baseDate;
                        const enrichedStart = detail.startTime || baseStart;
                        const enrichedEnd = detail.endTime || baseEnd;
                        const enrichedLocation = detail.location || baseLocation;
                        const enrichedDescription =
                            (detail.description && String(detail.description).trim()) || baseDescription;
                        const enrichedUrl = detail.url || baseUrl;
                        const enrichedCourseName = detail.courseName || baseCourseName; 

                        this.hoveredEventData = {
                            title: baseTitle,
                            instructorNames: enrichedInstructor,
                            sessionDateFormatted: enrichedDate,
                            startTime: enrichedStart,
                            endTime: enrichedEnd,
                            location: enrichedLocation,
                            description: enrichedDescription,
                            url:enrichedUrl,
                            courseName:enrichedCourseName
                        };
                    }
                })
                .catch(() => {
                    // Silently ignore hover enrichment errors
                });
        }
    }

    handleEventMouseLeave(event) {
        event.stopPropagation();
        if (this._hoverCardHideTimeout) clearTimeout(this._hoverCardHideTimeout);
        this._hoverCardHideTimeout = setTimeout(() => {
            this._hoverCardHideTimeout = null;
            this.hoveredEventData = null;
            this.hoverCardStyle = null;
        }, 200);
    }

    handleHoverCardMouseEnter() {
        if (this._hoverCardHideTimeout) {
            clearTimeout(this._hoverCardHideTimeout);
            this._hoverCardHideTimeout = null;
        }
    }

    handleHoverCardMouseLeave() {
        if (this._hoverCardHideTimeout) clearTimeout(this._hoverCardHideTimeout);
        this._hoverCardHideTimeout = null;
        this.hoveredEventData = null;
        this.hoverCardStyle = null;
    }

    get showHoverCard() {
        return this.hoveredEventData != null;
    }

    get hoverCardUrlClickable() {
        const url = this.hoveredEventData && this.hoveredEventData.url;
        if (!url || typeof url !== 'string') return false;
        const u = url.trim();
        return u.startsWith('http://') || u.startsWith('https://');
    }

    // Optional aliases if you prefer mouseover/mouseout in HTML
    handleEventMouseOver(event) {
        this.handleEventMouseEnter(event);
    }

    handleEventMouseOut(event) {
        this.handleEventMouseLeave(event);
    }



    get menuItemsWithIcons() {
        const iconMap = {
            studentDetails: studentDetailsIcon,
            programDetails: programDetailsIcon,
            attendance: attendanceIcon,
            exams: examsIcon,
            academics: academicsIcon,
            finance: financeIcon,
            services: servicesIcon,
            mentorship: mentorIcon,
            hostel: hostelIcon,
            reports: logoutIcon,
            project: projectIcon,
            tickets: ticketIcon,
            logout: logoutIcon
        };
        return this.menuItems.map((item) => ({
            ...item,
            iconUrl: iconMap[item.id] || null
        }));
    }

    get sidebarClass() {
        return this.isSidebarOpen ? 'sidebar sidebar-open' : 'sidebar sidebar-closed';
    }

    get mainContentClass() {
        return this.isSidebarOpen ? 'main-content main-content-with-sidebar' : 'main-content main-content-full';
    }

    get sessionTypeOptionsWithSelected() {
        const current = this.selectedSessionType || '';
        return (this.sessionTypeOptions || []).map((o) => ({
            label: o.label || '',
            value: o.value || '',
            selected: (o.value || '') === current
        }));
    }

    get scheduleFilter() {
        const start = this.getViewStartDate();
        const end = this.getViewEndDate();
        return JSON.stringify({
            startDate: this.toDateStr(start),
            endDate: this.toDateStr(end),
            sessionType: this.selectedSessionType || null
        });
    }
    

    @wire(getEnrolledSessions, { filterJson: '$scheduleFilter' })
    wiredSessions({ data, error }) {
        debugger;
        this.isLoading = false;
        if (data) {
            console.log('data:',data);
            
    this.sessions = Array.isArray(data) ? data : [];
        
        } else if (error) {
            console.log('filterJson::',this.scheduleFilter);
            console.error('getEnrolledSessions error', error);
            this.sessions = [];
        }
    }
    

    connectedCallback() {
        console.log('connectedCallBack of schedule');
        getSessionTypeOptions()
            .then((opts) => {
                this.sessionTypeOptions = (opts || []).map((o) => ({
                    label: o.label || o.value || '',
                    value: o.value || ''
                }));
            })
            .catch(() => {
            });
        if (this.showLayout) {
            
        }
        this.loadUserName();
        this.showLayout=true;
    }

    // SE-737U START: force Division Color background via DOM API to defeat any inline-style sanitization / cached CSS
    renderedCallback() {
        try {
            const nodes = this.template.querySelectorAll('[data-bg-color]');
            nodes.forEach((el) => {
                const hex = el.getAttribute('data-bg-color');
                if (hex) {
                    el.style.setProperty('background-image', 'none', 'important');
                    el.style.setProperty('background-color', hex, 'important');
                    el.style.setProperty('color', '#fff', 'important');
                }
            });
        } catch (e) {
            // ignore
        }
    }
    // SE-737U END

    loadUserName() {
        getUserInfo()
            .then((result) => {
                if (result) {
                    this.studentName = result.fullName || this.studentName;
                    this.rollNumber = result.rollNumber || '';
                    this.programName = result.programName || '';
                    this.programCode = result.programCode || '';
                    this.currentTerm = result.term || '';
                }
            })
            .catch((error) => {
                console.log('error::', error);
            });
    }

    handleToggleSidebar() {
        this.isSidebarOpen = !this.isSidebarOpen;
    }

    handleImageError(event) {
        const img = event.target;
        if (img) img.style.display = 'none';
    }

    handleMenuClick(event) {
        const menuId = event.currentTarget.dataset.id;
        if (menuId === 'logout') {
            this.handleLogout();
            return;
        }
        if (menuId === 'attendance') return;
        const url = this.dashboardPageRef || window.location.pathname.replace(/\/[^/]*$/, '') || '/';
        if (url && url !== window.location.pathname) {
            window.location.assign(url);
        } else {
            this.menuItems = this.menuItems.map((item) => ({
                ...item,
                cssClass: item.id === menuId ? 'nav-item selected' : 'nav-item'
            }));
        }
    }

    handleLogout() {
        sessionStorage.clear();
        localStorage.clear();
        const redirectUrl = encodeURIComponent('/student/login?');
        window.location.replace(`/student/secur/logout.jsp?retURL=${redirectUrl}`);
    }

    getViewStartDate() {
        const d = new Date(this.currentDate);
        d.setHours(0, 0, 0, 0);
        if (this.currentView === 'day') return d;
        if (this.currentView === 'week') {
            // Week runs Monday → Sunday (not Sunday → Saturday)
            const daysFromMonday = (d.getDay() + 6) % 7;
            d.setDate(d.getDate() - daysFromMonday);
            return d;
        }
        if (this.currentView === 'month') {
            d.setDate(1);
            return d;
        }
        if (this.currentView === 'year') {
            d.setMonth(0);
            d.setDate(1);
            return d;
        }
        return d;
    }

    getViewEndDate() {
        const start = this.getViewStartDate();
        const d = new Date(start);
        if (this.currentView === 'day') return d;
        if (this.currentView === 'week') {
            d.setDate(d.getDate() + 6);
            return d;
        }
        if (this.currentView === 'month') {
            d.setMonth(d.getMonth() + 1);
            d.setDate(0);
            return d;
        }
        if (this.currentView === 'year') {
            d.setFullYear(d.getFullYear() + 1);
            d.setDate(0);
            return d;
        }
        return d;
    }

    toDateStr(date) {
        if (!date) return null;
        const d = date instanceof Date ? date : new Date(date);
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${y}-${m}-${day}`;
    }

    get isWeekOrDayView() {
        return this.currentView === 'week' || this.currentView === 'day';
    }
    //SE-1170 Day view taller rows (64px) and show the session time line, while Week view
    // keeps the original 48px rows with no time line. Bound in HTML via class={calendarGridClass}.
    get calendarGridClass() {
    return `calendar-grid ${this.currentView === 'day' ? 'calendar-grid-day' : ''}`.trim();
    }
    //SE-1170
    get isMonthView() {
        return this.currentView === 'month';
    }
    get isYearView() {
        return this.currentView === 'year';
    }

    get dayTabClass() {
        return this.currentView === 'day' ? 'view-tab active' : 'view-tab';
    }
    get weekTabClass() {
        return this.currentView === 'week' ? 'view-tab active' : 'view-tab';
    }
    get monthTabClass() {
        return this.currentView === 'month' ? 'view-tab active' : 'view-tab';
    }
    get yearTabClass() {
        return this.currentView === 'year' ? 'view-tab active' : 'view-tab';
    }

    get formattedDateRange() {
        if (this.currentView === 'day') {
            return this.currentDate.toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric', year: 'numeric' });
        }
        if (this.currentView === 'week') {
            const start = this.getViewStartDate();
            const end = this.getViewEndDate();
            return `${start.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} – ${end.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}`;
        }
        if (this.currentView === 'month') {
            return this.currentDate.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
        }
        if (this.currentView === 'year') {
            return this.currentDate.getFullYear().toString();
        }
        return '';
    }

    get showNoSessions() {
        return !this.isLoading && (!this.sessions || this.sessions.length === 0);
    }

    /**
     * Normalize session color from API (e.g. "Blue" -> "blue") for CSS class session-{color}.
     * Matches timetableCalendar color handling.
     */
    getSessionColor(session) {
        const raw = (session && session.color) ? String(session.color).toLowerCase().trim() : 'blue';
        return SESSION_COLORS.includes(raw) ? raw : 'blue';
    }

    // SE-737U START: Resolve Division Color picklist to hex for inline tile background
    /**
     * Resolve background hex color for a session tile based on Division Color picklist
     * (e.g. "LimeYellow", "Steel Blue") or a legacy token like "blue".
     */
    getSessionColorHex(session) {
        return resolveColorHex(session && session.color);
    }

    getSessionBgStyle(session) {
        const hex = this.getSessionColorHex(session);
        return `background: ${hex} !important; background-image: none !important; color: #fff !important;`;
    }
    // SE-737U END

    get gridStyle() {
        const n = this.currentView === 'day' ? 1 : 7;
        return `--num-days: ${n}`;
    }

    get timeSlots() {
    const slots = [];
    
    for (let h = START_HOUR; h <= END_HOUR; h++) {
        const label = `${h}:00`; // 24-hour format
        slots.push({
            key: String(h),
            label: label
        });
    }

    return slots;
}

    get weekDays() {
        const start = this.getViewStartDate();
        const numDays = this.currentView === 'day' ? 1 : 7;
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const days = [];
        for (let i = 0; i < numDays; i++) {
            const d = new Date(start);
            d.setDate(d.getDate() + i);
            const dateStr = this.toDateStr(d);
            const dayEvents = (this.sessions || []).filter((s) => this.normalizeDate(s.sessionDate) === dateStr);
            const slots = {};
            this.timeSlots.forEach((slot) => {
                slots[slot.key] = [];
            });
            const slotStartGroups = {};
            dayEvents.forEach((ev) => {
                const hour = this.getSessionStartHour(ev);
                if (hour != null) {
                    const slotKey = String(hour);
                    if (!slots[slotKey]) slots[slotKey] = [];
                    const duration = this.getSessionDurationInHours(ev);
                    const startMinutes = this.getSessionStartMinutes(ev);
                    const groupKey = `${slotKey}-${startMinutes}`;
                    if (!slotStartGroups[groupKey]) {
                        slotStartGroups[groupKey] = [];
                    }
                    const queueIndex = slotStartGroups[groupKey].length;
                    slotStartGroups[groupKey].push(ev.id);
                    const facultyText =
                        (ev.instructorNames && String(ev.instructorNames).trim()) ||
                        (Array.isArray(ev.facultyNames) && ev.facultyNames.length > 0
                            ? ev.facultyNames.join(', ')
                            : '');
                    slots[slotKey].push({
                        id: ev.id,
                        title: ev.title,
                        courseName: ev.courseName || ev.title || '',
                        instructorNames: facultyText,
                        courseActivity: ev.courseActivity || '',
                        startTime: ev.startTime,//SE-1170
                        endTime: ev.endTime,    //Se-1170
                        // SE-737U START: drop session-<color> class so inline Division Color hex wins; carry hex for getEventStyle
                        eventClass: 'session-cell hover-container',
                        bgColorHex: this.getSessionColorHex(ev),
                        // SE-737U END
                        duration: duration,
                        startHour: hour,
                        startMinutes: startMinutes,
                        queueKey: groupKey,
                        queueIndex
                    });
                }
            });
            Object.keys(slots).forEach((slotKey) => {
                slots[slotKey] = (slots[slotKey] || []).map((evt) => ({
                    ...evt,
                    queueCount: (slotStartGroups[evt.queueKey] || []).length || 1
                }));
            });
            const isToday = d.getTime() === today.getTime();
            const dow = d.getDay();
            const dayName = DAY_NAMES_BY_GET_DAY[dow];
            days.push({
                key: dateStr,
                name: dayName,
                dateLabel: `${dayName.slice(0, 3)} ${d.getDate()} ${this.getMonthShort(d)}`,
                headerClass: `day-header ${isToday ? 'today' : ''}`,
                slots
            });
        }
        return days;
    }

    get calendarRows() {
        const days = this.weekDays;
        const slots = this.timeSlots;
        return slots.map((slot, rowIndex) => ({
            key: slot.key,
            label: slot.label,
            rowIndex: rowIndex,
            cells: days.map((day) => ({
                dayKey: day.key,
                events: (day.slots[slot.key] || []).map((evt) => {
                    const eventStyle = this.getEventStyle(evt, parseInt(slot.key), rowIndex);
                    const eventObj = { ...evt };
                    if (eventStyle != null) {
                        eventObj.eventStyle = eventStyle;
                    }
                    return eventObj;
                })
            }))
        }));
    }

    getEventStyle(evt, rowHour, rowIndex) {
        // SE-737U START: build Division Color background and append to positioning style
        const bg = evt.bgColorHex
            ? `background: ${evt.bgColorHex} !important; background-image: none !important; color: #fff !important;`
            : '';
        if (!evt.duration || !evt.startHour) {
            return bg || null;
        }
        // SE-737U END
        // Day view: 64px (taller, room for title/time/activity). Week view: 48px (unchanged, original size).
        const cellHeight = this.currentView === 'day' ? 64 : 48; // height of one hour row in pixels — must match .grid-row { height } in CSS
        
        if (evt.startHour !== rowHour) {
            return 'display: none;';
        }
        
        let topOffset = 0;
        if (evt.startMinutes > 0) {
            topOffset = (evt.startMinutes / 60) * cellHeight;
        }
        
        // Height from duration (now supports fractional hours from getSessionDurationInHours)
        let height = evt.duration * cellHeight;
        // Cap so session does not extend past the last grid row (END_HOUR)
        const rowsFromStart = END_HOUR - evt.startHour + 1;
        const maxHeight = rowsFromStart * cellHeight - topOffset;
        height = Math.min(height, Math.max(cellHeight - topOffset, maxHeight));
        
        const queueCount = Math.max(1, evt.queueCount || 1);
        const queueIndex = Math.min(queueCount - 1, Math.max(0, evt.queueIndex || 0));
        const widthPct = 100 / queueCount;
        const leftPct = widthPct * queueIndex;
        // SE-737U START: append Division Color background to inline style
        return `position: absolute; top: ${topOffset}px; height: ${height}px; width: calc(${widthPct}% - 2px); left: ${leftPct}%; z-index: 1; ${bg}`;
        // SE-737U END
    }

    getMonthShort(d) {
        return d.toLocaleDateString('en-US', { month: 'short' });
    }

    normalizeDate(val) {
        if (!val) return null;
        if (typeof val === 'string') return val.split('T')[0];
        if (val instanceof Date) return this.toDateStr(val);
        if (val.year && val.month != null && val.day != null) {
            const m = String(Number(val.month) + 1).padStart(2, '0');
            const day = String(val.day).padStart(2, '0');
            return `${val.year}-${m}-${day}`;
        }
        return null;
    }

    getSessionStartHour(session) {
        const t = session.startTime;
        if (!t) return null;
        const s = String(t);
        // Try to match hour:minute format first (e.g., "9:00 AM" or "9:00AM")
        const timeMatch = s.match(/(\d{1,2}):(\d{1,2})/);
        if (timeMatch) {
            let h = parseInt(timeMatch[1], 10);
            const isPM = s.toLowerCase().includes('pm');
            const isAM = s.toLowerCase().includes('am');
            if (isPM && h < 12) h += 12;
            if (isAM && h === 12) h = 0;
            return h;
        }
        // Fallback to simple hour match (e.g., "9AM" or "9")
        const match = s.match(/(\d{1,2})/);
        if (match) {
            let h = parseInt(match[1], 10);
            if (s.toLowerCase().includes('pm') && h < 12) h += 12;
            if (s.toLowerCase().includes('am') && h === 12) h = 0;
            return h;
        }
        return null;
    }

    getSessionEndHour(session) {
        const t = session.endTime;
        if (!t) return null;
        const s = String(t);
        // Try to match hour:minute format first (e.g., "11:00 AM" or "11:00AM")
        const timeMatch = s.match(/(\d{1,2}):(\d{1,2})/);
        if (timeMatch) {
            let h = parseInt(timeMatch[1], 10);
            const isPM = s.toLowerCase().includes('pm');
            const isAM = s.toLowerCase().includes('am');
            if (isPM && h < 12) h += 12;
            if (isAM && h === 12) h = 0;
            return h;
        }
        // Fallback to simple hour match (e.g., "11AM" or "11")
        const match = s.match(/(\d{1,2})/);
        if (match) {
            let h = parseInt(match[1], 10);
            if (s.toLowerCase().includes('pm') && h < 12) h += 12;
            if (s.toLowerCase().includes('am') && h === 12) h = 0;
            return h;
        }
        return null;
    }

    getSessionDurationInHours(session) {
        const startHour = this.getSessionStartHour(session);
        const endHour = this.getSessionEndHour(session);
        const startMin = this.getSessionStartMinutes(session);
        const endMin = this.getSessionEndMinutes(session);
        if (startHour == null || endHour == null) return 1;
        const startMins = startHour * 60 + (startMin || 0);
        const endMins = endHour * 60 + (endMin || 0);
        const durationMins = Math.max(0, endMins - startMins);
        const durationHours = durationMins / 60;
        return durationHours > 0 ? durationHours : 1;
    }

    getSessionEndMinutes(session) {
        const t = session.endTime;
        if (!t) return 0;
        const s = String(t);
        const minuteMatch = s.match(/:(\d{1,2})/);
        if (minuteMatch) return parseInt(minuteMatch[1], 10) || 0;
        return 0;
    }

    getSessionStartMinutes(session) {
        const t = session.startTime;
        if (!t) return 0;
        const s = String(t);
        const minuteMatch = s.match(/:(\d{1,2})/);
        if (minuteMatch) {
            return parseInt(minuteMatch[1], 10) || 0;
        }
        return 0;
    }

    get dayNamesShort() {
        return DAY_NAMES_SHORT;
    }

    get monthWeeksData() {
        if (this.currentView !== 'month') return [];
        const start = this.getViewStartDate();
        const end = this.getViewEndDate();
        const year = start.getFullYear();
        const month = start.getMonth();
        const first = new Date(year, month, 1);
        const last = new Date(year, month + 1, 0);
        // Pad grid to full weeks Monday → Sunday
        const daysBackToMonday = (first.getDay() + 6) % 7;
        const from = new Date(first);
        from.setDate(from.getDate() - daysBackToMonday);
        const to = new Date(last);
        const daysForwardToSunday = (7 - last.getDay()) % 7;
        to.setDate(to.getDate() + daysForwardToSunday);
        const weeks = [];
        let cur = new Date(from);
        let week = [];
        while (cur <= to) {
            const dateStr = this.toDateStr(cur);
            const dayEvents = (this.sessions || []).filter((s) => this.normalizeDate(s.sessionDate) === dateStr);
            const isCurrentMonth = cur.getMonth() === month;
            const today = new Date();
            today.setHours(0, 0, 0, 0);
            const isToday = cur.getTime() === today.getTime();
            week.push({
                key: dateStr,
                dateNum: cur.getDate(),
                cellClass: `month-cell ${isCurrentMonth ? 'current-month' : 'other-month'} ${isToday ? 'today' : ''}`,
                events: dayEvents.map((e) => ({
                    id: e.id,
                    title: e.title,
                    courseName: e.courseName || e.title || '',
                    // SE-737U START: drop session-<color> class so inline Division Color hex wins
                    eventClass: 'month-event',
                    eventStyle: this.getSessionBgStyle(e),
                    bgColorHex: this.getSessionColorHex(e)
                    // SE-737U END
                }))
            });
            if (week.length === 7) {
                weeks.push({ key: `w-${weeks.length}`, days: week });
                week = [];
            }
            cur.setDate(cur.getDate() + 1);
        }
        if (week.length) weeks.push({ key: `w-${weeks.length}`, days: week });
        return weeks;
    }

    get yearMonths() {
        if (this.currentView !== 'year') return [];
        const year = this.currentDate.getFullYear();
        const result = [];
        for (let m = 0; m < 12; m++) {
            const monthStart = new Date(year, m, 1);
            const monthEnd = new Date(year, m + 1, 0);
            const monthSessions = (this.sessions || []).filter((s) => {
                const ds = this.normalizeDate(s.sessionDate);
                if (!ds) return false;
                const d = new Date(ds);
                return d >= monthStart && d <= monthEnd;
            });
            const label = new Date(year, m).toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
            result.push({
                key: `y-${m}`,
                label,
                sessions: monthSessions.map((s) => ({
                    id: s.id,
                    title: s.title,
                    courseName: s.courseName || s.title || '',
                    dateLabel: this.formatSessionDate(s.sessionDate),
                    timeLabel: [s.startTime, s.endTime].filter(Boolean).join(' – '),
                    // SE-737U START: drop session-<color> class so inline Division Color hex wins
                    eventClass: 'year-session-item',
                    eventStyle: this.getSessionBgStyle(s),
                    bgColorHex: this.getSessionColorHex(s)
                    // SE-737U END
                })),
                empty: monthSessions.length === 0
            });
        }
        return result;
    }

    formatSessionDate(val) {
        const ds = this.normalizeDate(val);
        if (!ds) return '';
        const d = new Date(ds + 'T12:00:00');
        return d.toLocaleDateString('en-US', { day: '2-digit', month: 'short', year: 'numeric' });
    }

    get hasDetailFiles() {
        return this.sessionDetail && this.sessionDetail.files && this.sessionDetail.files.length > 0;
    }

    handleDayView() {
        console.log('day::');
        this.currentView = 'day';
    }
    handleWeekView() {
        this.currentView = 'week';
    }
    handleMonthView() {
        this.currentView = 'month';
    }
    handleYearView() {
        this.currentView = 'year';
    }

    handleSessionTypeChange(event) {
        this.selectedSessionType = event.target.value || '';
    }

    handlePrev() {
        const d = new Date(this.currentDate);
        if (this.currentView === 'day') d.setDate(d.getDate() - 1);
        else if (this.currentView === 'week') d.setDate(d.getDate() - 7);
        else if (this.currentView === 'month') d.setMonth(d.getMonth() - 1);
        else if (this.currentView === 'year') d.setFullYear(d.getFullYear() - 1);
        this.currentDate = d;
    }

    handleNext() {
        const d = new Date(this.currentDate);
        if (this.currentView === 'day') d.setDate(d.getDate() + 1);
        else if (this.currentView === 'week') d.setDate(d.getDate() + 7);
        else if (this.currentView === 'month') d.setMonth(d.getMonth() + 1);
        else if (this.currentView === 'year') d.setFullYear(d.getFullYear() + 1);
        this.currentDate = d;
    }

    handleSessionClick(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        this.selectedSessionId = id;
        this.showDetailModal = true;
        this.detailLoading = true;
        this.sessionDetail = null;
        getSessionDetails({ sessionId: id })
            .then((detail) => {
                console.log('details::', detail);
                console.log(detail.title, '-', detail.instructorNames);
                this.sessionHoverTooltipLine = detail.title, '-', detail.instructorNames;
                this.sessionDetail = detail;
                this.detailLoading = false;
                if (detail && detail.files && detail.files.length > 0) {
                    Promise.all(
                        detail.files.map((f) =>
                            getFileDownloadUrl(f.contentDocumentId).then((url) => ({ ...f, downloadUrl: url }))
                        )
                    ).then((filesWithUrls) => {
                        this.sessionDetail = { ...this.sessionDetail, files: filesWithUrls };
                    }).catch(() => { });
                }
            })
            .catch(() => {
                this.detailLoading = false;
            });
    }

    handleCloseDetailModal() {
        this.showDetailModal = false;
        this.sessionDetail = null;
        this.selectedSessionId = null;
    }

    handleModalContainerClick(event) {
        if (event.target === event.currentTarget) {
            this.handleCloseDetailModal();
        }
    }
}
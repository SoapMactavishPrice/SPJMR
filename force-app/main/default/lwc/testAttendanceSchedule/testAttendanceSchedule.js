import { LightningElement, wire, api, track } from 'lwc';
import { getFileDownloadUrl } from 'lightning/fileDownload';

import getEnrolledSessions from '@salesforce/apex/StudentScheduleController.getEnrolledSessions';
import getSessionDetails from '@salesforce/apex/StudentScheduleController.getSessionDetails';
import getSessionTypeOptions from '@salesforce/apex/StudentScheduleController.getSessionTypeOptions';
import getUserInfo from '@salesforce/apex/StudentProfileDashboardController.getUserInfo';

import logo from '@salesforce/resourceUrl/Site_Logo';
import navbarIcon from '@salesforce/resourceUrl/Navbar_Icon';

const START_HOUR = 6;
const END_HOUR = 22;

export default class TestAttendanceSchedule extends LightningElement {
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

    siteLogoIcon = logo;
    @track temp = 'this is hover';
    navbarIconResource = navbarIcon;
    profileDummyIcon = profileDummy;
    @track isSidebarOpen = true;
    @track studentName = 'John Steve';
    @track rollNumber = '';
    @track programName = '';
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
        this.isLoading = false;
        if (data) {
            console.log('data:', data);

            const data1 = [
                {
                    id: 'a01TEST0001',
                    title: 'Marketing Strategy',
                    sessionDate: '2026-02-01',
                    startTime: '9:00 AM',
                    endTime: '10:30 AM',
                    courseActivity: 'Lecture',
                    courseName: 'Marketing 101',
                    color: 'blue'
                },
                {
                    id: 'a01TEST0002',
                    title: 'Finance Basics',
                    sessionDate: '2026-02-01',
                    startTime: '10:00 AM',
                    endTime: '11:00 AM',
                    courseActivity: 'Workshop',
                    courseName: 'Finance Fundamentals',
                    color: 'red'
                },
                {
                    id: 'a01TEST0003',
                    title: 'Operations Management',
                    sessionDate: '2026-02-02',
                    startTime: '2:00 PM',
                    endTime: '3:30 PM',
                    courseActivity: 'Case Study',
                    courseName: 'Operations',
                    color: 'purple'
                }
            ];
            console.log('data1::', data1);
            this.sessions = Array.isArray(data1) ? data1 : [];

        } else if (error) {
            console.error('getEnrolledSessions error', error);
            this.sessions = [];
        }
    }
//     @track isVisible = false;
// hoveredEventId = null;
// cardStyle = '';

// handleGridHover(event) {
//     console.log('GRID HOVER:', eventId);
//     const cell = event.target.closest('.session-cell');
//     if (!cell) {
//         this.hideTooltip();
//         return;
//     }

//     const eventId = cell.dataset.id;
//     if (!eventId || eventId === this.hoveredEventId) return;

//     this.hoveredEventId = eventId;
//     this.showTooltip();

//     const rect = cell.getBoundingClientRect();
//     this.cardStyle = `
//         position: fixed;
//         top: ${rect.bottom + 8}px;
//         left: ${rect.left}px;
//         z-index: 100000;
//     `;
// }

// handleGridLeave() {
//     this.hideTooltip();
// }

// showTooltip() {
//     this.isVisible = true;
// }

// hideTooltip() {
//     this.isVisible = false;
//     this.hoveredEventId = null;
//     this.cardStyle = '';
// }


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
            this.loadUserName();
        }

    }

    loadUserName() {
        getUserInfo()
            .then((result) => {
                if (result) {
                    this.studentName = result.fullName || this.studentName;
                    this.rollNumber = result.rollNumber || '';
                    this.programName = result.programName || '';
                    this.currentTerm = result.batchName ? `Term ${result.batchName}` : this.currentTerm;
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
            const day = d.getDay();
            d.setDate(d.getDate() - day);
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

    get gridStyle() {
        const n = this.currentView === 'day' ? 1 : 7;
        return `--num-days: ${n}`;
    }

    get timeSlots() {
        const slots = [];
        for (let h = START_HOUR; h <= END_HOUR; h++) {
            const label = h < 12 ? `${h}.00AM` : (h === 12 ? '12.00PM' : `${h - 12}.00PM`);
            slots.push({ key: String(h), label });
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
            dayEvents.forEach((ev) => {
                const hour = this.getSessionStartHour(ev);
                if (hour != null) {
                    const slotKey = String(hour);
                    if (!slots[slotKey]) slots[slotKey] = [];
                    slots[slotKey].push({
                        id: ev.id,
                        title: ev.title,
                        courseActivity: ev.courseActivity || '',
                        eventClass: `session-cell hover-container session-${ev.color || 'blue'}`
                    });
                }
            });
            const isToday = d.getTime() === today.getTime();
            days.push({
                key: dateStr,
                name: DAY_NAMES[d.getDay()],
                dateLabel: `${DAY_NAMES[d.getDay()].slice(0, 3)} ${d.getDate()} ${this.getMonthShort(d)}`,
                headerClass: `day-header ${isToday ? 'today' : ''}`,
                slots
            });
        }
        return days;
    }

    get calendarRows() {
        const days = this.weekDays;
        const slots = this.timeSlots;
        return slots.map((slot) => ({
            key: slot.key,
            label: slot.label,
            cells: days.map((day) => ({
                dayKey: day.key,
                events: day.slots[slot.key] || []
            }))
        }));
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
        const match = s.match(/(\d{1,2})/);
        if (match) {
            let h = parseInt(match[1], 10);
            if (s.toLowerCase().includes('pm') && h < 12) h += 12;
            if (s.toLowerCase().includes('am') && h === 12) h = 0;
            return h;
        }
        return null;
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
        const startDow = first.getDay();
        const from = new Date(first);
        from.setDate(from.getDate() - startDow);
        const to = new Date(last);
        to.setDate(to.getDate() + (6 - last.getDay()));
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
                events: dayEvents.map((e) => ({ id: e.id, title: e.title }))
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
                    dateLabel: this.formatSessionDate(s.sessionDate),
                    timeLabel: [s.startTime, s.endTime].filter(Boolean).join(' – ')
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
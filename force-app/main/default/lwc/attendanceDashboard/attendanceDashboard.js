import { LightningElement, track, api } from 'lwc';
import getData from '@salesforce/apex/StudentAttendanceService.getData';
import getUserInfo from '@salesforce/apex/StudentProfileDashboardController.getUserInfo';

const DONUT_OUTER_PX = 140;
const DONUT_INNER_PX = 90;
const DONUT_FONT_PX = 22;

export default class AttendanceDashboard extends LightningElement {
    @track records = [];
    @track accountId = null;
    @track warningMessage = '';
    @track filter = 'year';
    @track startDate = '';//SE-1174
    @track endDate = '';//SE-1174
    @track noRecordsMessage = '';//SE-1174


    _rawData = []; // cache raw Apex records for tab re-filtering without re-fetching
    _termId = '';
/*SE-1254*/    @track termOptions = [];
    @track selectedTermValue = '';
    @track courseOptions = [];
    @track selectedCourseIds = []; // empty = show all courses
    @track isCourseDropdownOpen = false;

    @api
    get termId() {
        return this._termId;
    }
    set termId(value) {
        const next = value == null || value === '' ? '' : String(value);
        if (next === this._termId) {
            return;
        }
        this._termId = next;
        if (this.accountId) {
            this.fetchData();
        }
    }

    async connectedCallback() {
        await this.loadUserName();
        if (!this.accountId) {
            this.records = [];
            this.warningMessage = '';
            console.warn('AttendanceDashboard: accountId missing, skipping getData call.');
            return;
        }
        await this.fetchData();
    }

    async fetchData() {
        try {
            if (!this.accountId || !this._termId) {
                this._rawData = [];
                this.processAndSetData([], this.filter);
                return;
            }
            const result = await getData({
                accId: this.accountId,
                academicTermId: this._termId
            });
            console.log('Raw Apex result::', result);
            this._rawData = result || [];
            this.processAndSetData(this._rawData, this.filter);
        } catch (error) {
            console.error('Error fetching data', error);
        }
    }

    /**
     * Overall attendance: (sum of weighted session scores) / (total sessions).
     * Weights: Present=1, Late=0.5, Sanctioned Leave=1, Absent=0.
     * Donut uses this getter so it matches the footer "Attendance %" column.
     */
    get overallAttendancePercent() {
        const r = this.totalsRow;
        return this.computeAttendancePercent(r.weightedPoints || 0, r.totalSessions || 0);
    }

    get donutStyle() {
        const value = this.overallAttendancePercent || 0;
        return `background: conic-gradient(#f57c00 0% ${value}%, #e0e0e0 ${value}% 100%);
                width:${DONUT_OUTER_PX}px;height:${DONUT_OUTER_PX}px;`;
    }

    get donutTextStyle() {
        return `width:${DONUT_INNER_PX}px;height:${DONUT_INNER_PX}px;
                font-size:${DONUT_FONT_PX}px;`;
    }

    handleDayClick()   { this.filter = 'day';   this.processAndSetData(this._rawData, this.filter); }
    handleWeekClick()  { this.filter = 'week';  this.processAndSetData(this._rawData, this.filter); }
    handleMonthClick() { this.filter = 'month'; this.processAndSetData(this._rawData, this.filter); }
    handleYearClick()  { this.filter = 'year';  this.processAndSetData(this._rawData, this.filter); }

    get dayClass()   { return this.filter === 'day'   ? 'tab-btn active' : 'tab-btn'; }
    get weekClass()  { return this.filter === 'week'  ? 'tab-btn active' : 'tab-btn'; }
    get monthClass() { return this.filter === 'month' ? 'tab-btn active' : 'tab-btn'; }
    get yearClass()  { return this.filter === 'year'  ? 'tab-btn active' : 'tab-btn'; }

    /*SE-1174*/
   handleStartDateChange(event) { 
        this.startDate = event.target.value;
        const endDateInput = this.template.querySelector('[data-id="endDateInput"]');
        if (endDateInput) {
            endDateInput.setCustomValidity('');
            endDateInput.reportValidity();
        }
    }

    handleEndDateChange(event) {
        this.endDate = event.target.value;
        const endDateInput = this.template.querySelector('[data-id="endDateInput"]');
        if (endDateInput) {
            endDateInput.setCustomValidity('');
            endDateInput.reportValidity();


        }
    }

    handleTermChange(event) {
    this.selectedTermValue = event.detail.value;
    this._termId = this.selectedTermValue;

    this.fetchData();
    }
toggleCourseDropdown(event) {
    event.stopPropagation();
    this.isCourseDropdownOpen = !this.isCourseDropdownOpen;
}

stopPanelClick(event) {
    event.stopPropagation(); // keep panel open when clicking inside it
}

handleAddCourse(event) {
    event.stopPropagation();
    const value = event.currentTarget.dataset.value;
    if (!this.selectedCourseIds.includes(value)) {
        this.selectedCourseIds = [...this.selectedCourseIds, value];
    }
    this.isCourseDropdownOpen = false;
    this.processAndSetData(this._rawData, this.filter);
}

handleRemoveCourse(event) {
    event.stopPropagation();
    const value = event.currentTarget.dataset.value;
    this.selectedCourseIds = this.selectedCourseIds.filter(id => id !== value);
    this.processAndSetData(this._rawData, this.filter);
}

    handleSearchClick() {
         if (!this.startDate || !this.endDate) {
            return;
        }

        const endDateInput = this.template.querySelector('[data-id="endDateInput"]');

        const start = new Date(`${this.startDate}T00:00:00`);
        const end = new Date(`${this.endDate}T00:00:00`);

        if (start > end) {
            if (endDateInput) {
                endDateInput.setCustomValidity('End Date cannot be earlier than Start Date.');
                endDateInput.reportValidity();
            }
            return;
        }

        if (endDateInput) {
            endDateInput.setCustomValidity('');
            endDateInput.reportValidity();
        }
        
        this.noRecordsMessage = '';

        const filteredData = (this._rawData || []).filter((rec) => {
            const sessionDate = rec.Session__r?.Session_Date__c;
            const startTime = rec.Session__r?.Start_Time__c;

            let recordDate = null;
            if (sessionDate) {
                recordDate = new Date(`${sessionDate}T00:00:00`);
            } else if (startTime) {
                const parsed = new Date(startTime);
                if (!Number.isNaN(parsed.getTime())) {
                    recordDate = parsed;
                }
            }

            if (!recordDate) {
                return false;
            }
            return recordDate >= start && recordDate <= end;
        });

        this.buildDateRangeRecords(filteredData);
    }

    handleClearClick() {
        this.startDate = '';
        this.endDate = '';

        const endDateInput = this.template.querySelector('[data-id="endDateInput"]');
        if (endDateInput) {
        endDateInput.setCustomValidity('');
        endDateInput.reportValidity();
        }
        this.noRecordsMessage = '';
        this.processAndSetData(this._rawData, this.filter);
    }

    buildDateRangeRecords(filteredData) {
        if (!filteredData || !filteredData.length) {
            this.records = [];
            this.warningMessage = '';
            this.noRecordsMessage = 'No attendance records were found for the selected date range.';
            return;
        }
        this.noRecordsMessage = '';
        const normalizeAttendance = (raw) => {
            const s = ((raw || '') + '').trim().toLowerCase();
            if (s === 'present' || s === 'p') return 'present';
            if (s === 'absent' || s === 'a') return 'absent';
            if (
                s === 'sanctioned leave' ||
                s === 'sanctioned' ||
                s === 'sl' ||
                s === 'leave' ||
                s === 'l' ||
                s === 'on leave'
            ) {
                return 'sanctioned_leave';
            }
            if (s === 'late') return 'late';
            return '';
        };

        const weightForStatus = (status) => {
            if (status === 'present') return 1;
            if (status === 'late') return 0.5;
            if (status === 'sanctioned_leave') return 1;
            if (status === 'absent') return 0;
            return 0;
        };

        const courseMap = {};
        let lowAttendanceCourse = null;

        filteredData.forEach((rec) => {
            const courseNameRaw =
                rec.Session__r?.Course__r?.Name ||
                rec.Session__r?.Course_Name__c ||
                rec.Session__r?.Name ||
                rec.courseName;
            const courseName = (courseNameRaw && String(courseNameRaw).trim()) || 'Unassigned Course';
        // ADD THIS 👇
    if (this.selectedCourseIds.length && !this.selectedCourseIds.includes(courseName)) {
        return;
    }

            if (!courseMap[courseName]) {
                courseMap[courseName] = {
                    courseName,
                    totalSessions: 0,
                    weightedPoints: 0,
                    presentCount: 0,
                    absentCount: 0,
                    leaveCount: 0,
                    lateCount: 0,
                    hasAbsent: false
                };
            }

            const course = courseMap[courseName];
            course.totalSessions++;

            const status = normalizeAttendance(rec.Attendance__c);
            if (status === 'present') course.presentCount++;
            else if (status === 'absent') {
                course.absentCount++;
                course.hasAbsent = true;
            }
            else if (status === 'sanctioned_leave') course.leaveCount++;
            else if (status === 'late') course.lateCount++;

            course.weightedPoints += weightForStatus(status);
        });

        this.records = Object.values(courseMap).map((item, index) => {
            const total = item.totalSessions;
            const sanctioned = item.leaveCount;
            let weighted = item.weightedPoints;

            if (item.hasAbsent && item.leaveCount > 0) {
                weighted = 0;
            }

            const coursePercentage = this.computeAttendancePercent(weighted, total);

            if (coursePercentage < 75 && !lowAttendanceCourse) {
                lowAttendanceCourse = item.courseName;
            }

            return {
                id:             `row-${index}`,
                courseName:     item.courseName,
                totalSessions:  total,
                weightedPoints: weighted,
                presentCount:   item.presentCount,
                absentCount:    item.absentCount,
                leaveCount:     sanctioned,
                lateCount:      item.lateCount,
                percentage:     coursePercentage
            };
        });

        this.warningMessage = lowAttendanceCourse
            ? `Below 75% attendance in ${lowAttendanceCourse}`
            : '';
    }  /*SE-1174*/
    

    get totalsRow() {
        return this.records.reduce((acc, rec) => {
            acc.totalSessions += rec.totalSessions || 0;
            acc.weightedPoints += rec.weightedPoints || 0;
            acc.presentCount += rec.presentCount || 0;
            acc.absentCount += rec.absentCount || 0;
            acc.leaveCount += rec.leaveCount || 0;
            acc.lateCount += rec.lateCount || 0;
            return acc;
        }, {
            totalSessions: 0,
            weightedPoints: 0,
            presentCount: 0,
            absentCount: 0,
            leaveCount: 0,
            lateCount: 0
        });
    }

    get selectedCourseChips() {
    return this.courseOptions.filter(c => this.selectedCourseIds.includes(c.value));
}

get unselectedCourseOptions() {
    return this.courseOptions.filter(c => !this.selectedCourseIds.includes(c.value));
}

get noMoreCourses() {
    return this.unselectedCourseOptions.length === 0;
}

    async loadUserName() {
        try {
            const result = await getUserInfo();
            this.accountId = result?.accountId || null;
            console.log('accountId::', this.accountId);
            // Add these lines
        this.termOptions = [...(result.termOptions || [])].sort((a, b) =>
            (a.label || '').localeCompare(b.label || '', undefined, { numeric: true })
        );

        this.selectedTermValue = result.currentTermId || '';

        console.log('accountId::', this.accountId);
        // NEW — courses the student is enrolled in
        this.courseOptions = [...(result.courseOptions || [])].sort((a, b) =>
            (a.label || '').localeCompare(b.label || '', undefined, { numeric: true })
        );
        } catch (error) {
            console.error(error);
        }
    }

    processAndSetData(rawData, filter) {
        if (!rawData || !rawData.length) {
            this.records = [];
            this.warningMessage = '';
            return;
        }

        const normalizeAttendance = (raw) => {
            const s = ((raw || '') + '').trim().toLowerCase();
            if (s === 'present' || s === 'p') return 'present';
            if (s === 'absent' || s === 'a') return 'absent';
            if (
                s === 'sanctioned leave' ||
                s === 'sanctioned' ||
                s === 'sl' ||
                s === 'leave' ||
                s === 'l' ||
                s === 'on leave'
            ) {
                return 'sanctioned_leave';
            }
            if (s === 'late') return 'late';
            return '';
        };

        const weightForStatus = (status) => {
            if (status === 'present') return 1;
            if (status === 'late') return 0.5;
            if (status === 'sanctioned_leave') return 1;
            if (status === 'absent') return 0;
            return 0;
        };

        const courseMap = {};
        const now = new Date();
        let lowAttendanceCourse = null;

        const isSameDay = (d1, d2) =>
            d1.getFullYear() === d2.getFullYear() &&
            d1.getMonth() === d2.getMonth() &&
            d1.getDate() === d2.getDate();

        const isSameWeek = (date) => {
            const firstDay = new Date(now);
            firstDay.setDate(now.getDate() - now.getDay());
            const lastDay = new Date(firstDay);
            lastDay.setDate(firstDay.getDate() + 6);
            return date >= firstDay && date <= lastDay;
        };

        const isSameMonth = (d1, d2) =>
            d1.getFullYear() === d2.getFullYear() &&
            d1.getMonth() === d2.getMonth();

        const isSameYear = (d1, d2) =>
            d1.getFullYear() === d2.getFullYear();

        rawData.forEach((rec) => {
            // Support multiple payload shapes from Apex serialization.
            const courseNameRaw =
                rec.Session__r?.Course__r?.Name ||
                rec.Session__r?.Course_Name__c ||
                rec.Session__r?.Name ||
                rec.courseName;
            const courseName = (courseNameRaw && String(courseNameRaw).trim()) || 'Unassigned Course';
            const sessionDate = rec.Session__r?.Session_Date__c;
            const startTime = rec.Session__r?.Start_Time__c;
            // NEW — filter by selected courses (skip if not selected)
    if (this.selectedCourseIds.length && !this.selectedCourseIds.includes(courseName)) {
        return;
    }


            // Use Session_Date__c when available; Start_Time__c can be Time-only and not parse as Date.
            let recordDate = null;
            if (sessionDate) {
                recordDate = new Date(`${sessionDate}T00:00:00`);
            } else if (startTime) {
                const parsed = new Date(startTime);
                if (!Number.isNaN(parsed.getTime())) {
                    recordDate = parsed;
                }
            }

            // If no parseable date exists, keep the row instead of filtering it out.
            let include = true;

            if (recordDate) {
                switch (filter) {
                    case 'day':   include = isSameDay(recordDate, now);   break;
                    case 'week':  include = isSameWeek(recordDate);       break;
                    case 'month': include = isSameMonth(recordDate, now); break;
                    case 'year':  include = isSameYear(recordDate, now);  break;
                    default:      include = true;
                }
            }

            if (!include) return;

            if (!courseMap[courseName]) {
                courseMap[courseName] = {
                    courseName,
                    totalSessions: 0,
                    weightedPoints: 0,
                    presentCount: 0,
                    absentCount: 0,
                    leaveCount: 0,
                    lateCount: 0,
                    hasAbsent: false
                };
            }

            const course = courseMap[courseName];
            course.totalSessions++;

            const status = normalizeAttendance(rec.Attendance__c);
            if (status === 'present') course.presentCount++;
            else if (status === 'absent') {
                course.absentCount++;
                course.hasAbsent = true;
            }
            else if (status === 'sanctioned_leave') course.leaveCount++;
            else if (status === 'late') course.lateCount++;

            course.weightedPoints += weightForStatus(status);
        });

        this.records = Object.values(courseMap).map((item, index) => {
            const total = item.totalSessions;
            const sanctioned = item.leaveCount;
            let weighted = item.weightedPoints;
            
            // If there is any absent session mixed with sanctioned leave, set attendance to 0
            if (item.hasAbsent && item.leaveCount > 0) {
                weighted = 0;
            }
            
            const coursePercentage = this.computeAttendancePercent(weighted, total);

            if (coursePercentage < 75 && !lowAttendanceCourse) {
                lowAttendanceCourse = item.courseName;
            }

            return {
                id:             `row-${index}`,
                courseName:     item.courseName,
                totalSessions:  total,
                weightedPoints: weighted,
                presentCount:   item.presentCount,
                absentCount:    item.absentCount,
                leaveCount:     sanctioned,
                lateCount:      item.lateCount,
                percentage:     coursePercentage
            };
        });

        console.log('Final this.records::', this.records);

        this.warningMessage = lowAttendanceCourse
            ? `Below 75% attendance in ${lowAttendanceCourse}`
            : '';
    }

    /**
     * @param {number} weightedSum - Present(1)+Late(0.5)+Sanctioned(1)+Absent(0) per course or overall
     * @param {number} totalSessions - all sessions in scope (denominator)
     */
    computeAttendancePercent(weightedSum, totalSessions) {
        if (!totalSessions) {
            return 0;
        }
        return Math.round((weightedSum * 100) / totalSessions);
    }
}
import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getPrograms from '@salesforce/apex/TimetableWizardController.getPrograms';
import getBatchesForProgram from '@salesforce/apex/TimetableWizardController.getBatchesForProgram';
import getBatchGroupsForBatch from '@salesforce/apex/TimetableWizardController.getBatchGroupsForBatch';
import getTermsForBatchGroup from '@salesforce/apex/TimetableWizardController.getTermsForBatchGroup';
import getDivisionsForTerms from '@salesforce/apex/TimetableWizardController.getDivisionsForTerms';
import getSessionEnrollments from '@salesforce/apex/SessionAttendanceController.getSessionEnrollments';
import getAttendanceOptions from '@salesforce/apex/SessionAttendanceController.getAttendanceOptions';
import updateSessionEnrollments from '@salesforce/apex/SessionAttendanceController.updateSessionEnrollments';
import getSessionOptions from '@salesforce/apex/SessionAttendanceController.getSessionOptions';
import getSessionSummary from '@salesforce/apex/SessionAttendanceController.getSessionSummary';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

/** Must match Session_Enrollment__c.Attendance__c API value */
const SANCTIONED_LEAVE = 'Sanctioned Leave';

export default class SessionAttendanceManager extends LightningElement {
    @api sessionId;

    @track rows = [];
    @track attendanceOptions = [];
    @track isLoading = false;
    @track errorMessage = '';
    @track selectedProgram = '';
    @track selectedBatch = '';
    @track selectedBatchGroup = '';
    @track selectedTerm = '';
    @track selectedDivision = '';
    @track selectedSessionDate = '';
    @track selectedSession = '';
    @track programOptions = [];
    @track batchOptions = [];
    @track batchGroupOptions = [];
    @track termOptions = [];
    @track divisionOptions = [];
    @track sessionOptions = [];
    @track sessionTitle = '';
    /** Session name line (from API, without course/date combo) */
    @track sessionNameLine = '';
    @track sessionCourseName = '';
    @track sessionCourseActivity = '';
    @track sessionFacultyName = '';
    /** Canonical session date from SessionSummary; used to enforce read-only for future sessions. */
    @track sessionSummaryDate = '';
    _didInit = false;
    _reloadToken = 0;

    originalById = {};

    /** Client-side filter on roll number and student name (Attendance Sheet search). */
    @track attendanceSearchText = '';
    @track selectedAttendanceFilter = 'All';
    /** Optional division context passed by timetable View Attendance URL. */
    prefillDivisionId = null;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        const fromState = pageRef && pageRef.state
            ? (pageRef.state.c__sessionId || pageRef.state.sessionId || pageRef.state.recordId)
            : null;
        const fromDivisionState = pageRef && pageRef.state
            ? (pageRef.state.c__divisionId || pageRef.state.divisionId)
            : null;
        this.prefillDivisionId = fromDivisionState ? String(fromDivisionState).trim() : null;
        if (!this.sessionId && fromState) {
            this.sessionId = fromState;
            this.selectedSession = fromState;
            if (!this._didInit) this.loadInitialData();
        }
    }

    connectedCallback() {
        if (!this._didInit) this.loadInitialData();
    }

    get hasRows() {
        return (this.rows || []).length > 0;
    }

    /** Rows visible in the table after search (same object references as this.rows). */
    get tableRows() {
         let list = [...this.rows];

    if (this.selectedAttendanceFilter !== 'All') {
        list = list.filter(
            row => row.attendance === this.selectedAttendanceFilter
        );
    }
        const q = (this.attendanceSearchText || '').trim().toLowerCase();
        //const list = this.rows || [];
        if (q) {
        list = list.filter(row => {
            const roll = (row.rollNumber || '').toLowerCase();
            const name = (row.studentName || '').toLowerCase();
            return roll.includes(q) || name.includes(q);
        });
    }
    return list;
    }

    get hasNoSearchMatches() {
        return (this.rows || []).length > 0 && this.tableRows.length === 0;
    }

    get filterProgramOptions() {
        return [{ label: 'All Programs', value: '' }, ...this.normalizeOptions(this.programOptions)];
    }

    get filterBatchOptions() {
        return [{ label: 'All Batches', value: '' }, ...this.normalizeOptions(this.batchOptions)];
    }

    get filterBatchGroupOptions() {
        return [{ label: 'All Batch Groups', value: '' }, ...this.normalizeOptions(this.batchGroupOptions)];
    }

    get filterTermOptions() {
        return [{ label: 'All Terms', value: '' }, ...this.normalizeOptions(this.termOptions)];
    }

    get filterDivisionOptions() {
        return [{ label: 'All Divisions', value: '' }, ...this.normalizeOptions(this.divisionOptions)];
    }

    get filterSessionOptions() {
        return [{ label: 'Select Session', value: '' }, ...this.normalizeOptions(this.sessionOptions)];
    }

    get sessionHeaderTitle() {
        if (this.sessionTitle) return this.sessionTitle;
        if (this.selectedSession) {
            const opt = (this.sessionOptions || []).find(o => o.value === this.selectedSession);
            return opt ? opt.label : 'Session';
        }
        return 'Session';
    }

    get showSessionMeta() {
        return !!(this.selectedSession || this.sessionId);
    }

    get sessionCourseReadonlyDisplay() {
        if (!this.showSessionMeta) {
            return '—';
        }
        const v = this.sessionCourseName;
        return v != null && String(v).trim() !== '' ? String(v).trim() : '—';
    }

    get sessionCourseActivityReadonlyDisplay() {
        if (!this.showSessionMeta) {
            return '—';
        }
        const v = this.sessionCourseActivity;
        return v != null && String(v).trim() !== '' ? String(v).trim() : '—';
    }

    get sessionFacultyReadonlyDisplay() {
        if (!this.showSessionMeta) {
            return '—';
        }
        const v = this.sessionFacultyName;
        return v != null && String(v).trim() !== '' ? String(v).trim() : '—';
    }

    get totalStudents() {
        return this.rows.length;
    }

    get totalPresent() {
        return this.rows.filter(r => r.attendance === 'Present').length;
    }

    get totalAbsent() {
        return this.rows.filter(r => r.attendance === 'Absent').length;
    }

    /** Attendance picklist value Late */
    get totalLate() {
        return this.rows.filter(r => r.attendance === 'Late').length;
    }

    /** Leave tile: count when attendance is Sanctioned Leave (Leave Type column may be blank). */
    get totalLeaveSanctioned() {
        return this.rows.filter(r => (r.attendance || '').trim() === SANCTIONED_LEAVE).length;
    }

    get isFutureSessionReadOnly() {
        const d = this.sessionSummaryDate ? String(this.sessionSummaryDate).trim() : '';
        if (!d) return false;
        const today = this.getTodayIsoDate();
        return d > today;
    }

    loadInitialData() {
        this._didInit = true;
        this.isLoading = true;
        Promise.all([getAttendanceOptions(), getPrograms()])
            .then(([attendanceOpts, programResult]) => {
                this.attendanceOptions = this.normalizeOptions(attendanceOpts);
                const programOptionsRaw = programResult && Array.isArray(programResult.options)
                    ? programResult.options
                    : [];
                this.programOptions = this.normalizeOptions(programOptionsRaw);
                if (this.selectedSession || this.sessionId) {
                    const sid = this.selectedSession || this.sessionId;
                    this.selectedSession = sid;
                    return this.prefillFiltersFromSession(sid)
                        .then(() => this.loadSessionOptions())
                        .then(() => this.loadData());
                }
                return this.loadSessionOptions();
            })
            .catch(err => {
                this.errorMessage = this.getErrorMessage(err);
                this.showToast('Error', this.errorMessage, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    prefillFiltersFromSession(sessionId) {
        return getSessionSummary({ sessionId, divisionId: this.toIdOrNull(this.prefillDivisionId) })
            .then(summary => {
                if (!summary) return;
                this.applySessionSummary(summary);
                this.selectedProgram = summary.programId || '';
                this.selectedBatch = summary.batchId || '';
                this.selectedBatchGroup = summary.batchGroupId || '';
                this.selectedTerm = summary.termId || '';
                this.selectedDivision = summary.divisionId || '';
                this.selectedSessionDate = summary.sessionDate || '';

                const tasks = [];
                if (this.selectedProgram) {
                    tasks.push(getBatchesForProgram({ programId: this.selectedProgram }).then(result => {
                        this.batchOptions = this.normalizeOptions(result);
                    }));
                }
                if (this.selectedBatch) {
                    tasks.push(getBatchGroupsForBatch({ batchId: this.selectedBatch }).then(result => {
                        this.batchGroupOptions = this.normalizeOptions(result);
                    }));
                }
                if (this.selectedBatchGroup) {
                    tasks.push(getTermsForBatchGroup({ batchGroupId: this.selectedBatchGroup }).then(result => {
                        this.termOptions = this.normalizeOptions(result);
                    }));
                }
                if (this.selectedTerm) {
                    tasks.push(getDivisionsForTerms({ termIds: [this.selectedTerm] }).then(result => {
                        this.divisionOptions = this.normalizeOptions(result);
                    }));
                }
                return Promise.all(tasks);
            });
    }

    loadSessionOptions() {
        return getSessionOptions({
            programId: this.selectedProgram || null,
            batchId: this.selectedBatch || null,
            batchGroupId: this.selectedBatchGroup || null,
            termId: this.selectedTerm || null,
            divisionId: this.selectedDivision || null,
            sessionDate: this.selectedSessionDate || null
        }).then(result => {
            const normalized = this.normalizeOptions(result);
            this.sessionOptions = normalized.map((opt) => ({
                ...opt,
                label: this.normalizeSessionOptionLabelDate(opt.label)
            }));
            const hasSelectedSession = this.selectedSession
                && this.sessionOptions.some(o => String(o.value) === String(this.selectedSession));
            if (!hasSelectedSession) {
                this.selectedSession = '';
                this.sessionId = null;
                this.clearSessionMeta();
                this.rows = [];
            }
        });
    }

    applySessionSummary(summary) {
        if (!summary) {
            return;
        }
        this.sessionTitle = this.formatSessionDisplayLabel(summary);
        this.sessionNameLine = summary.sessionTitle || '';
        this.sessionCourseName = summary.courseName || '';
        this.sessionCourseActivity = summary.courseActivityLabel || '';
        this.sessionFacultyName = summary.facultyNames || '';
        this.sessionSummaryDate = summary.sessionDate ? String(summary.sessionDate) : '';
    }

    clearSessionMeta() {
        this.sessionTitle = '';
        this.sessionNameLine = '';
        this.sessionCourseName = '';
        this.sessionCourseActivity = '';
        this.sessionFacultyName = '';
        this.sessionSummaryDate = '';
    }

    loadData() {
        const sid = this.selectedSession || this.sessionId;
        if (!sid) {
            this.rows = [];
            this.clearSessionMeta();
            return Promise.resolve();
        }
        this.isLoading = true;
        this.errorMessage = '';
        this._reloadToken = Date.now();

        return Promise.all([
            getSessionEnrollments({
                sessionId: sid,
                refreshToken: this._reloadToken,
                programId: this.toIdOrNull(this.selectedProgram),
                batchId: this.toIdOrNull(this.selectedBatch),
                batchGroupId: this.toIdOrNull(this.selectedBatchGroup),
                termId: this.toIdOrNull(this.selectedTerm),
                divisionId: this.toIdOrNull(this.selectedDivision)
            }),
            getSessionSummary({ sessionId: sid, divisionId: this.toIdOrNull(this.selectedDivision) })
        ])
            .then(([rows, summary]) => {
                this.applySessionSummary(summary);
                this.rows = (rows || []).map((r, idx) => {
                    const attendance = r.attendance || '';
                    return {
                        key: r.id || `row-${idx}`,
                        id: r.id,
                        attendance,
                        rollNumber: r.rollNumber || '',
                        registrationNumber: r.registrationNumber || '',
                        remark: r.remark || '',
                        inviteResponse: r.inviteResponse || '',
                        studentName: r.studentName || '',
                        termCode: r.termCode || '',
                        leaveType: r.leaveType || '',
                        attendanceIsSanctionedLeave: attendance === SANCTIONED_LEAVE,
                        divisionEnrollmentId: r.divisionEnrollmentId || '',
                        isDirty: false
                    };
                });
                this.originalById = {};
                this.rows.forEach(r => {
                    this.originalById[r.id] = {
                        attendance: r.attendance || '',
                        remark: r.remark || '',
                        leaveType: r.leaveType || ''
                    };
                });
            })
            .catch(err => {
                this.errorMessage = this.getErrorMessage(err);
                this.showToast('Error', this.errorMessage, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    /** Reconcile session + rows after session dropdown options refresh (e.g. filter change). */
    applyAfterSessionOptionsLoaded(previousSessionId) {
        const sid = String(previousSessionId || this.selectedSession || '').trim();
        const opts = this.sessionOptions || [];
        if (!sid || !opts.some(o => String(o.value) === String(sid))) {
            this.selectedSession = '';
            this.sessionId = null;
            this.clearSessionMeta();
            this.rows = [];
            this.attendanceSearchText = '';
            return Promise.resolve();
        }
        this.selectedSession = sid;
        this.sessionId = sid;
        return this.loadData();
    }

    toIdOrNull(value) {
        if (value == null || value === '') {
            return null;
        }
        const s = String(value).trim();
        return s === '' ? null : s;
    }

    handleAttendanceSearchChange(event) {
        this.attendanceSearchText = event.target.value != null ? String(event.target.value) : '';
    }
    handleAttendanceFilter(event) {
    this.selectedAttendanceFilter = event.currentTarget.dataset.status;
}

    handleProgramChange(event) {
        const previousSession = this.selectedSession;
        this.selectedProgram = event.detail.value || '';
        this.selectedBatch = '';
        this.selectedBatchGroup = '';
        this.selectedTerm = '';
        this.selectedDivision = '';
        this.batchOptions = [];
        this.batchGroupOptions = [];
        this.termOptions = [];
        this.divisionOptions = [];
        if (!this.selectedProgram) {
            this.isLoading = true;
            this.loadSessionOptions()
                .then(() => this.applyAfterSessionOptionsLoaded(previousSession))
                .catch(err => this.showToast('Error', this.getErrorMessage(err), 'error'))
                .finally(() => {
                    this.isLoading = false;
                });
            return;
        }
        this.isLoading = true;
        getBatchesForProgram({ programId: this.selectedProgram })
            .then(result => {
                this.batchOptions = this.normalizeOptions(result);
                return this.loadSessionOptions();
            })
            .then(() => this.applyAfterSessionOptionsLoaded(previousSession))
            .catch(err => this.showToast('Error', this.getErrorMessage(err), 'error'))
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleBatchChange(event) {
        const previousSession = this.selectedSession;
        this.selectedBatch = event.detail.value || '';
        this.selectedBatchGroup = '';
        this.selectedTerm = '';
        this.selectedDivision = '';
        this.batchGroupOptions = [];
        this.termOptions = [];
        this.divisionOptions = [];
        if (!this.selectedBatch) {
            this.isLoading = true;
            this.loadSessionOptions()
                .then(() => this.applyAfterSessionOptionsLoaded(previousSession))
                .catch(err => this.showToast('Error', this.getErrorMessage(err), 'error'))
                .finally(() => {
                    this.isLoading = false;
                });
            return;
        }
        this.isLoading = true;
        getBatchGroupsForBatch({ batchId: this.selectedBatch })
            .then(result => {
                this.batchGroupOptions = this.normalizeOptions(result);
                return this.loadSessionOptions();
            })
            .then(() => this.applyAfterSessionOptionsLoaded(previousSession))
            .catch(err => this.showToast('Error', this.getErrorMessage(err), 'error'))
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleBatchGroupChange(event) {
        const previousSession = this.selectedSession;
        this.selectedBatchGroup = event.detail.value || '';
        this.selectedTerm = '';
        this.selectedDivision = '';
        this.termOptions = [];
        this.divisionOptions = [];
        if (!this.selectedBatchGroup) {
            this.isLoading = true;
            this.loadSessionOptions()
                .then(() => this.applyAfterSessionOptionsLoaded(previousSession))
                .catch(err => this.showToast('Error', this.getErrorMessage(err), 'error'))
                .finally(() => {
                    this.isLoading = false;
                });
            return;
        }
        this.isLoading = true;
        getTermsForBatchGroup({ batchGroupId: this.selectedBatchGroup })
            .then(result => {
                this.termOptions = this.normalizeOptions(result);
                return this.loadSessionOptions();
            })
            .then(() => this.applyAfterSessionOptionsLoaded(previousSession))
            .catch(err => this.showToast('Error', this.getErrorMessage(err), 'error'))
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleTermChange(event) {
        const previousSession = this.selectedSession;
        this.selectedTerm = event.detail.value || '';
        this.selectedDivision = '';
        this.divisionOptions = [];
        if (!this.selectedTerm) {
            this.isLoading = true;
            this.loadSessionOptions()
                .then(() => this.applyAfterSessionOptionsLoaded(previousSession))
                .catch(err => this.showToast('Error', this.getErrorMessage(err), 'error'))
                .finally(() => {
                    this.isLoading = false;
                });
            return;
        }
        this.isLoading = true;
        getDivisionsForTerms({ termIds: [this.selectedTerm] })
            .then(result => {
                this.divisionOptions = this.normalizeOptions(result);
                return this.loadSessionOptions();
            })
            .then(() => this.applyAfterSessionOptionsLoaded(previousSession))
            .catch(err => this.showToast('Error', this.getErrorMessage(err), 'error'))
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleDivisionChange(event) {
        const previousSession = this.selectedSession;
        this.selectedDivision = event.detail.value || '';
        this.isLoading = true;
        this.loadSessionOptions()
            .then(() => this.applyAfterSessionOptionsLoaded(previousSession))
            .catch(err => this.showToast('Error', this.getErrorMessage(err), 'error'))
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSessionDateChange(event) {
        const previousSession = this.selectedSession;
        this.selectedSessionDate = event.detail.value || '';
        this.isLoading = true;
        this.loadSessionOptions()
            .then(() => this.applyAfterSessionOptionsLoaded(previousSession))
            .catch(err => this.showToast('Error', this.getErrorMessage(err), 'error'))
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSessionChange(event) {
        this.selectedSession = event.detail.value || '';
        this.sessionId = this.selectedSession || null;
        this.attendanceSearchText = '';
        this.selectedAttendanceFilter = 'All';
        this.clearSessionMeta();
        if (this.selectedSession) {
            const opt = (this.sessionOptions || []).find(o => o.value === this.selectedSession);
            this.sessionTitle = opt ? opt.label : '';
            this.loadData();
        } else {
            this.rows = [];
        }
    }

    handleAttendanceChange(event) {
        if (this.isFutureSessionReadOnly) {
            return;
        }
        const id = event.target.dataset.id;
        const value = event.detail.value || '';
        this.rows = this.rows.map(r => {
            if (r.id !== id) return r;
            const original = this.originalById[id] || { attendance: '', remark: '', leaveType: '' };
            let leaveType = r.leaveType;
            if (value !== SANCTIONED_LEAVE) {
                leaveType = '';
            } else if (!leaveType || !String(leaveType).trim()) {
                leaveType = original.leaveType || '';
            }
            const isDirty =
                value !== (original.attendance || '') ||
                (r.remark || '') !== (original.remark || '') ||
                (leaveType || '') !== (original.leaveType || '');
            return {
                ...r,
                attendance: value,
                leaveType,
                attendanceIsSanctionedLeave: value === SANCTIONED_LEAVE,
                isDirty
            };
        });
    }

    handleRemarkChange(event) {
        if (this.isFutureSessionReadOnly) {
            return;
        }
        const id = event.target.dataset.id;
        const value = event.detail.value || '';
        this.rows = this.rows.map(r => {
            if (r.id !== id) return r;
            const original = this.originalById[id] || { attendance: '', remark: '', leaveType: '' };
            return {
                ...r,
                remark: value,
                isDirty:
                    (r.attendance || '') !== (original.attendance || '') ||
                    value !== (original.remark || '') ||
                    (r.leaveType || '') !== (original.leaveType || '')
            };
        });
    }

    /** Newly set to Sanctioned Leave (was another value or blank): remark required */
    isSanctionedLeaveRemarkMissing(row) {
        if (!row) return false;
        const original = this.originalById[row.id] || {};
        const wasSanctioned = (original.attendance || '') === SANCTIONED_LEAVE;
        const nowSanctioned = (row.attendance || '') === SANCTIONED_LEAVE;
        if (wasSanctioned || !nowSanctioned) {
            return false;
        }
        const remark = row.remark != null ? String(row.remark).trim() : '';
        return remark === '';
    }

    handleSave() {
        if (this.isFutureSessionReadOnly) {
            this.showToast('Info', 'Attendance updates are disabled for future sessions.', 'info');
            return;
        }
        const dirtyRows = (this.rows || []).filter(r => r.isDirty);
        if (dirtyRows.length === 0) {
            this.showToast('Info', 'No changes to save.', 'info');
            return;
        }

        const missingRemark = dirtyRows.filter(r => this.isSanctionedLeaveRemarkMissing(r));
        if (missingRemark.length > 0) {
            this.showToast(
                'Error',
                'Remark is required when attendance is set to Sanctioned Leave.',
                'error'
            );
            return;
        }

        const payload = dirtyRows.map(r => {
            const att = r.attendance || null;
            const lt =
                att === SANCTIONED_LEAVE && r.leaveType && String(r.leaveType).trim()
                    ? String(r.leaveType).trim()
                    : null;
            return {
                id: r.id,
                attendance: att,
                remark: r.remark != null && r.remark !== '' ? r.remark : null,
                leaveType: lt
            };
        });

        this.isLoading = true;
        updateSessionEnrollments({ payloadJson: JSON.stringify(payload) })
            .then(() => {
                this.showToast('Success', 'Attendance updated successfully.', 'success');
                // Refresh twice (immediate + short delayed) to avoid any stale UI data after save.
                this.loadData();
                window.setTimeout(() => this.loadData(), 300);
            })
            .catch(err => {
                this.showToast('Error', this.getErrorMessage(err), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (error && error.body) {
            if (Array.isArray(error.body) && error.body.length > 0) {
                return error.body.map(e => e.message).join(', ');
            }
            if (error.body.message) {
                return error.body.message;
            }
        }
        if (error && error.message) return error.message;
        return 'An unexpected error occurred.';
    }

    getTodayIsoDate() {
        const d = new Date();
        const year = d.getFullYear();
        const month = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    normalizeOptions(input) {
        if (!Array.isArray(input)) return [];
        return input
            .filter(o => o)
            .map(o => ({
                label: o.label != null ? String(o.label) : '',
                value: o.value != null ? String(o.value) : ''
            }));
    }

    /** Matches Apex getSessionOptions label: Session Name / Course Name / Date [/ time range] */
    formatSessionDisplayLabel(summary) {
        if (!summary) return '';
        const name = summary.sessionTitle && String(summary.sessionTitle).trim()
            ? String(summary.sessionTitle).trim()
            : 'Session';
        const course = summary.courseName && String(summary.courseName).trim()
            ? String(summary.courseName).trim()
            : '—';
        const datePart = this.formatDateShortMonthYear(summary.sessionDate);
        let line = `${name} / ${course} / ${datePart}`;
        const tr = summary.sessionTimeRange != null ? String(summary.sessionTimeRange).trim() : '';
        if (tr) {
            line += ` / ${tr}`;
        }
        return line;
    }

    /** Date display format: DD-MMM-YYYY (e.g. 20-Apr-2026). */
    formatDateShortMonthYear(value) {
        if (!value) return '—';
        const s = String(value).trim();
        const iso = s.includes('T') ? s.split('T')[0] : s;
        const parts = iso.split('-');
        if (parts.length !== 3) return iso || '—';
        const year = parts[0];
        const monthNum = Number(parts[1]);
        const day = parts[2];
        const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const month = monthNum >= 1 && monthNum <= 12 ? monthNames[monthNum - 1] : parts[1];
        return `${day}-${month}-${year}`;
    }

    /** Converts only the date token in "Session / Course / Date [/ Time]" labels to DD-MMM-YYYY. */
    normalizeSessionOptionLabelDate(label) {
        if (label == null) return '';
        const text = String(label);
        const isoDatePattern = /\b(\d{4})-(\d{2})-(\d{2})\b/;
        const match = text.match(isoDatePattern);
        if (!match) {
            return text;
        }
        return text.replace(isoDatePattern, this.formatDateShortMonthYear(match[0]));
    }
}
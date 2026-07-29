import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import SheetJS from '@salesforce/resourceUrl/sheetJs';

import getPrograms from '@salesforce/apex/TimetableWizardController.getPrograms';
import getBatchesForProgram from '@salesforce/apex/TimetableWizardController.getBatchesForProgram';
import getBatchGroupsForBatch from '@salesforce/apex/TimetableWizardController.getBatchGroupsForBatch';
import getTermsForBatchGroup from '@salesforce/apex/TimetableWizardController.getTermsForBatchGroup';
import getDivisionsForTerms from '@salesforce/apex/TimetableWizardController.getDivisionsForTerms';
import getCoursesForDivision from '@salesforce/apex/TimetableWizardController.getCoursesForDivision';
import generateAttendanceReport from '@salesforce/apex/ConsolidatedAttendanceReportController.generateAttendanceReport';

export default class ConsolidatedAttendanceReport extends LightningElement {
    static ALL_DIVISIONS_VALUE = 'ALL';

    // Selected values
    @track selectedProgram;
    @track selectedBatch;
    @track selectedBatchGroup;
    @track selectedTerm;
    @track selectedDivision;
    @track selectedCourse;
    @track startDate;
    @track endDate;

    @track isLoading = false;

    // Dropdown options
    @track programOptions = [];
    @track batchOptions = [];
    @track batchGroupOptions = [];
    @track termOptions = [];
    @track divisionOptions = [];
    @track courseOptions = [];

    // Preview / report state
    @track showPreview = false;
    @track sessionColumns = [];
    @track previewStudents = [];
    reportResult = null; // raw apex result kept for excel export

    sheetJsLoaded = false;

    renderedCallback() {
        if (this.sheetJsLoaded) return;
        this.sheetJsLoaded = true;
        loadScript(this, SheetJS).catch(error => {
            console.error('Error loading SheetJS', error);
        });
    }

    connectedCallback() {
        this.loadPrograms();
    }

    // ---------- Getters to control disabled/visible state ----------
    get isProgramNotSelected() {
        return !this.selectedProgram;
    }
    get isBatchNotSelected() {
        return !this.selectedBatch;
    }
    get isBatchGroupNotSelected() {
        return !this.selectedBatchGroup;
    }
    get isTermNotSelected() {
        return !this.selectedTerm;
    }
    get isDivisionNotSelected() {
    // Course should be selectable whether a specific division OR "All Divisions" is chosen —
    // it should only stay disabled when NOTHING has been picked yet.
    return !this.selectedDivision;
    }
    get isCourseNotSelected() {
        return !this.selectedCourse;
    }
    get isStartDateNotSelected() {
        return !this.startDate;
    }
   get isReportButtonVisible() {
    const datesAreValid =
        !!this.startDate &&
        !!this.endDate &&
        this.startDate <= this.todayDate &&
        this.endDate <= this.todayDate;

    return !!(
        this.selectedProgram &&
        this.selectedBatch &&
        this.selectedBatchGroup &&
        this.selectedTerm &&
        this.selectedDivision &&
        this.selectedCourse &&
        datesAreValid
    );
}
    get hasNoData() {
        return !this.sessionColumns || this.sessionColumns.length === 0;
    }
    //--------Date Validation------
    get todayDate() {
    const d = new Date();
    const yyyy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
}

    // ---------- Load Programs ----------
    loadPrograms() {
        getPrograms()
            .then(result => {
                const options = (result && result.options) ? result.options : [];
                this.programOptions = options.map(o => ({ label: o.label, value: o.value }));

                const defaultId = (result && result.defaultProgramId) ? result.defaultProgramId : null;
                if (defaultId) {
                    this.selectedProgram = defaultId;
                    this.loadBatches(defaultId);
                }
            })
            .catch(error => console.error('Error loading programs:', error));
    }

    // ---------- Program → Batch ----------
    handleProgramChange(event) {
        this.selectedProgram = event.detail.value;
        this.resetFrom('batch');
        if (this.selectedProgram) {
            this.loadBatches(this.selectedProgram);
        }
    }

    loadBatches(programId) {
        getBatchesForProgram({ programId })
            .then(result => {
                const options = (result || []).map(o => ({
                    label: o.label,
                    value: o.value,
                    sessionDuration: o.sessionDuration != null ? Math.round(Number(o.sessionDuration)) : null,
                    allowMultiProgramBatch: o.allowMultiProgramBatch === true
                }));
                this.batchOptions = options;
                if (options.length === 1) {
                    this.selectedBatch = options[0].value;
                    this.loadBatchGroups(this.selectedBatch);
                }
            })
            .catch(error => console.error('Error loading batches:', error));
    }

    // ---------- Batch → Batch Group ----------
    handleBatchChange(event) {
        this.selectedBatch = event.detail.value;
        this.resetFrom('batchGroup');
        if (this.selectedBatch) {
            this.loadBatchGroups(this.selectedBatch);
        }
    }

    loadBatchGroups(batchId) {
        getBatchGroupsForBatch({ batchId })
            .then(result => {
                this.batchGroupOptions = (result || []).map(o => ({ label: o.label, value: o.value }));
            })
            .catch(error => console.error('Error loading batch groups:', error));
    }

    // ---------- Batch Group → Term ----------
    handleBatchGroupChange(event) {
        this.selectedBatchGroup = event.detail.value;
        this.resetFrom('term');
        if (this.selectedBatchGroup) {
            this.loadTerms(this.selectedBatchGroup);
        }
    }

    loadTerms(batchGroupId) {
        getTermsForBatchGroup({ batchGroupId })
            .then(result => {
                this.termOptions = (result || []).map(o => ({
                    label: o.label,
                    value: o.value,
                    termStartDate: o.termStartDate || null,
                    termEndDate: o.termEndDate || null
                }));
            })
            .catch(error => console.error('Error loading terms:', error));
    }

    // ---------- Term → Division ----------
    handleTermChange(event) {
        this.selectedTerm = event.detail.value;
        this.resetFrom('division');
        if (this.selectedTerm) {
            this.loadDivisions(this.selectedTerm);
        }
    }

    loadDivisions(termId) {
        getDivisionsForTerms({ termIds: [termId] })
            .then(result => {
                const fetched = (result || []).map(o => ({
                    label: o.label,
                    value: o.value,
                    divisionColor: (o.divisionColor && String(o.divisionColor).trim()) ? String(o.divisionColor).trim() : null
                }));
                this.divisionOptions = [
                    { label: 'All Divisions', value: this.constructor.ALL_DIVISIONS_VALUE },
                    ...fetched
                ];
            })
            .catch(error => console.error('Error loading divisions:', error));
    }

    // ---------- Division → Course ----------
    handleDivisionChange(event) {
    this.selectedDivision = event.detail.value;
    this.resetFrom('course');

    if (this.selectedDivision === this.constructor.ALL_DIVISIONS_VALUE) {
        this.loadCoursesForAllDivisions();
    } else if (this.selectedDivision) {
        this.loadCourses(this.selectedDivision);
    }
}

// NEW: merge courses from every division under the currently selected term
loadCoursesForAllDivisions() {
    const divisions = (this.divisionOptions || []).filter(
        d => d.value !== this.constructor.ALL_DIVISIONS_VALUE
    );
    if (divisions.length === 0) {
        this.courseOptions = [];
        return;
    }

    const promises = divisions.map(d =>
        getCoursesForDivision({ divisionId: d.value }).catch(() => [])
    );

    Promise.all(promises)
        .then(resultsArr => {
            const merged = new Map();
            resultsArr.forEach(list => {
                (list || []).forEach(o => {
                    // dedupe by combobox value ("courseName|learningCourseId") so the same
                    // course offered in multiple divisions only shows once
                    if (!merged.has(o.value)) {
                        merged.set(o.value, {
                            label: o.label,
                            value: o.value,
                            departmentName: o.departmentName || null
                        });
                    }
                });
            });
            this.courseOptions = Array.from(merged.values());
        })
        .catch(error => {
            console.error('Error loading courses for all divisions:', error);
            this.courseOptions = [];
        });
}

    loadCourses(divisionId) {
        getCoursesForDivision({ divisionId })
            .then(result => {
                this.courseOptions = (result || []).map(o => ({
                    label: o.label,
                    value: o.value,
                    departmentName: o.departmentName || null
                }));
            })
            .catch(error => console.error('Error loading courses:', error));
    }

    // ---------- Course ----------
    handleCourseChange(event) {
        this.selectedCourse = event.detail.value;
        // Course changed -> dates + preview are no longer valid, reset them
        this.startDate = null;
        this.endDate = null;
        this.hidePreview();
    }

    // ---------- Dates ----------
    handleStartDateChange(event) {
    const inputEl = event.target;
    if (!this.selectedCourse) {
        inputEl.setCustomValidity('Please select a Course first.');
        inputEl.reportValidity();
        return;
    }
    const newStartDate = event.detail.value;
    if (newStartDate && newStartDate > this.todayDate) {
        inputEl.setCustomValidity('Future dates are not allowed. Please select today\'s date or an earlier date.');
        inputEl.reportValidity();
        return;
    }
    inputEl.setCustomValidity('');
    inputEl.reportValidity();
    this.startDate = newStartDate;

    // If existing end date is now before the new start date, clear it
    if (this.endDate && this.startDate && this.endDate < this.startDate) {
        this.endDate = null;
    }
    this.hidePreview();
}

handleEndDateChange(event) {
    const inputEl = event.target;
    if (!this.startDate) {
        inputEl.setCustomValidity('Please select Start Date before selecting End Date.');
        inputEl.reportValidity();
        return;
    }
    const newEndDate = event.detail.value;
    if (newEndDate && newEndDate > this.todayDate) {
        inputEl.setCustomValidity('Future dates are not allowed. Please select today\'s date or an earlier date.');
        inputEl.reportValidity();
        return;
    }
    if (newEndDate && newEndDate < this.startDate) {
        inputEl.setCustomValidity('End Date cannot be earlier than Start Date.');
        inputEl.reportValidity();
        return;
    }
    inputEl.setCustomValidity('');
    inputEl.reportValidity();
    this.endDate = newEndDate;
    this.hidePreview();
}

    // ---------- Helpers ----------
    resetFrom(level) {
        if (level === 'batch') {
            this.selectedBatch = null;
            this.batchOptions = [];
        }
        if (level === 'batch' || level === 'batchGroup') {
            this.selectedBatchGroup = null;
            this.batchGroupOptions = [];
        }
        if (level === 'batch' || level === 'batchGroup' || level === 'term') {
            this.selectedTerm = null;
            this.termOptions = [];
        }
        if (level === 'batch' || level === 'batchGroup' || level === 'term' || level === 'division') {
            this.selectedDivision = null;
            this.divisionOptions = [];
        }
        if (level === 'batch' || level === 'batchGroup' || level === 'term' || level === 'division' || level === 'course') {
            this.selectedCourse = null;
            this.courseOptions = [];
        }
        // Any upstream change invalidates dates + preview
        this.startDate = null;
        this.endDate = null;
        this.hidePreview();
    }

    hidePreview() {
        this.showPreview = false;
        this.sessionColumns = [];
        this.previewStudents = [];
        this.reportResult = null;
    }

    @api
    getSelection() {
        return {
            programId: this.selectedProgram,
            batchId: this.selectedBatch,
            batchGroupId: this.selectedBatchGroup,
            termId: this.selectedTerm,
            divisionId: this.selectedDivision,
            courseId: this.selectedCourse,
            startDate: this.startDate,
            endDate: this.endDate
        };
    }

    handleReset() {
    this.selectedProgram = null;
    this.selectedBatch = null;
    this.selectedBatchGroup = null;
    this.selectedTerm = null;
    this.selectedDivision = null;
    this.selectedCourse = null;
    this.startDate = null;
    this.endDate = null;

    this.batchOptions = [];
    this.batchGroupOptions = [];
    this.termOptions = [];
    this.divisionOptions = [];
    this.courseOptions = [];

    this.hidePreview();
    this.clearDateValidationErrors();
    this.loadPrograms();
}

// Clears any lingering "future date" / "end before start" custom validity
// messages left on the date inputs from before Reset was clicked.
// NOTE: querying by [label="..."] does not work reliably in LWC because
// `label` is a component property, not a plain HTML attribute — that's why
// the error messages were surviving Reset before. Query by class instead.
clearDateValidationErrors() {
    const startInput = this.template.querySelector('.start-date-input');
    const endInput = this.template.querySelector('.end-date-input');
    if (startInput) {
        startInput.setCustomValidity('');
        startInput.reportValidity();
    }
    if (endInput) {
        endInput.setCustomValidity('');
        endInput.reportValidity();
    }
}

    // ---------- Show Report (preview) ----------
    async handleShowReport() {
    if (!this.isReportButtonVisible) {
        this.showToast('Missing filters', 'Please select all filters and both dates before generating the report.', 'error');
        return;
    }

    this.isLoading = true;
    try {
        const isAllDivisions = this.selectedDivision === this.constructor.ALL_DIVISIONS_VALUE;
        const divisionIdsParam = isAllDivisions
            ? (this.divisionOptions || [])
                  .filter(d => d.value !== this.constructor.ALL_DIVISIONS_VALUE)
                  .map(d => d.value)
            : null;

        const result = await generateAttendanceReport({
            programId: this.selectedProgram,
            batchId: this.selectedBatch,
            batchGroupId: this.selectedBatchGroup,
            termId: this.selectedTerm,
            divisionId: this.selectedDivision,
            divisionIds: divisionIdsParam,
            courseId: this.selectedCourse,
            startDateStr: this.startDate,
            endDateStr: this.endDate
        });

        this.reportResult = result;
        this.buildPreviewModel(result);
        this.showPreview = true;
    } catch (error) {
        console.error('Error generating report', error);
        this.showToast('Error', this.extractErrorMessage(error), 'error');
    } finally {
        this.isLoading = false;
    }
}

    buildPreviewModel(result) {
        const sessions = result.sessions || [];
        const students = result.students || [];

        this.sessionColumns = sessions.map(s => ({
            ...s,
            remarkHeaderKey: s.sessionId + '-remark-header',
            attHeaderKey: s.sessionId + '-att-header'
        }));

        this.previewStudents = students.map(stu => {
            const cells = this.sessionColumns.map(s => {
                const cell = stu.cellsBySessionId ? stu.cellsBySessionId[s.sessionId] : null;
                return {
                    key: (stu.rollNumber || stu.studentName) + '-' + s.sessionId,
                    remarkKey: (stu.rollNumber || stu.studentName) + '-' + s.sessionId + '-remark',
                    attendance: cell ? this.mapAttendanceCode(cell.attendance) : '',
                    remark: cell ? (cell.remark || '') : ''
                };
            });
            // NEW
return {
    key: stu.rollNumber || stu.studentName,
    rollNumber: stu.rollNumber,
    studentName: stu.studentName,
    cells,
    totalSessionsCovered: stu.totalSessionsCovered,
    presentCount: stu.presentCount,
    absentCount: stu.absentCount,
    lateCount: stu.lateCount,
    sanctionedLeaveCount: stu.sanctionedLeaveCount,
    absentPercent: stu.absentPercent != null
    ? Number(stu.absentPercent).toFixed(2)
    : '0.00'
};
        });
    }

    // ---------- Download Excel ----------
    handleDownloadExcel() {
        if (!this.reportResult) return;
        this.buildAndDownloadExcel(this.reportResult);
    }

   buildAndDownloadExcel(result) {
    const sessions = result.sessions || [];
    const students = result.students || [];

    const FIXED_COLS = 2;
    const COLS_PER_SESSION = 2;

    const aoa = [];

    const row0 = ['', ''];
    sessions.forEach(() => row0.push('Session', ''));
    aoa.push(row0);

    const row1 = ['Roll Number', 'Date'];
    sessions.forEach(s => row1.push(s.sessionDateStr, ''));
    aoa.push(row1);

    const row2 = ['', 'Session Start and End Time'];
    sessions.forEach(s => row2.push(s.timeRangeStr, 'Remarks'));
    aoa.push(row2);

    const row3 = ['', 'Session Name'];
    sessions.forEach(s => row3.push(s.sessionName || '', ''));
    aoa.push(row3);

    const rowDiv = ['', 'Division'];
    sessions.forEach(s => rowDiv.push(s.divisionNames || '', ''));
    aoa.push(rowDiv);

    const row4 = ['', 'Course'];
    sessions.forEach(s => row4.push(s.courseName || '', ''));
    aoa.push(row4);

    const row5 = ['', 'Faculty'];
    sessions.forEach(s => row5.push(s.facultyNames || '', ''));
    aoa.push(row5);

    // NEW
const row6 = ['Student Roll Number', 'Student Name'];
sessions.forEach(() => row6.push('Session Attendance', 'Session Attendance Remarks'));
// NEW
row6.push(
    'Total Sessions Covered',
    'Present',
    'Absent',
    'Late',
    'Sanctioned Leave',
    'Absent %'
);
aoa.push(row6);

students.forEach(stu => {
    const row = [stu.rollNumber || '', stu.studentName || ''];
    sessions.forEach(s => {
        const cell = stu.cellsBySessionId ? stu.cellsBySessionId[s.sessionId] : null;
        row.push(cell ? this.mapAttendanceCode(cell.attendance) : '');
        row.push(cell ? (cell.remark || '') : '');
    });
    
    row.push(
    stu.totalSessionsCovered != null ? stu.totalSessionsCovered : '',
    stu.presentCount != null ? stu.presentCount : '',
    stu.absentCount != null ? stu.absentCount : '',
    stu.lateCount != null ? stu.lateCount : '',
    stu.sanctionedLeaveCount != null ? stu.sanctionedLeaveCount : '',
    stu.absentPercent != null ? Number(stu.absentPercent) : ''
   );
    aoa.push(row);
});

    // eslint-disable-next-line no-undef
    const ws = XLSX.utils.aoa_to_sheet(aoa);

    const merges = [];
    sessions.forEach((s, i) => {
        const startCol = FIXED_COLS + i * COLS_PER_SESSION;
        merges.push({ s: { r: 0, c: startCol }, e: { r: 0, c: startCol + 1 } });
        merges.push({ s: { r: 1, c: startCol }, e: { r: 1, c: startCol + 1 } });
        merges.push({ s: { r: 3, c: startCol }, e: { r: 3, c: startCol + 1 } });
        merges.push({ s: { r: 4, c: startCol }, e: { r: 4, c: startCol + 1 } });
        merges.push({ s: { r: 5, c: startCol }, e: { r: 5, c: startCol + 1 } });
        merges.push({ s: { r: 6, c: startCol }, e: { r: 6, c: startCol + 1 } });
    });
    ws['!merges'] = merges;

    // NEW
const colWidths = [{ wch: 16 }, { wch: 24 }];
sessions.forEach(() => colWidths.push({ wch: 16 }, { wch: 16 }));
colWidths.push(
    { wch: 14 }, // Total Sessions Covered
    { wch: 10 }, // Present
    { wch: 10 }, // Absent
    { wch: 10 }, // Late
    { wch: 14 }, // Sanctioned Leave
    { wch: 12 }  // Attendance %
);
ws['!cols'] = colWidths;

    // eslint-disable-next-line no-undef
    const wb = XLSX.utils.book_new();
    // eslint-disable-next-line no-undef
    XLSX.utils.book_append_sheet(wb, ws, 'Attendance Report');
    // eslint-disable-next-line no-undef
    XLSX.writeFile(wb, 'Consolidated_Attendance_Report.xlsx');
}

    mapAttendanceCode(attendance) {
        if (!attendance) return '';
        const val = String(attendance).toLowerCase();
        if (val.startsWith('present')) return 'P';
        if (val.startsWith('absent')) return 'A';
        return attendance;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractErrorMessage(error) {
        if (!error) return 'Unknown error';
        if (Array.isArray(error.body)) return error.body.map(e => e.message).join(', ');
        if (error.body && error.body.message) return error.body.message;
        return error.message || 'Unknown error';
    }
}
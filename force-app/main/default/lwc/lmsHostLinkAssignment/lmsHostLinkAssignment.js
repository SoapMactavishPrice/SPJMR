import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import getPageData from '@salesforce/apex/LmsHostLinkAssignmentController.getPageData';
import saveLmsHostLinks from '@salesforce/apex/LmsHostLinkAssignmentController.saveLmsHostLinks';

const COHORT_FIELD_PATHS = [
    'ProgramCohort.Name',
    'ProgramCohort.StartDate',
    'ProgramCohort.EndDate',
    'ProgramCohort.Batch_Start_Date__c'
];

export default class LmsHostLinkAssignment extends LightningElement {
    @api recordId;
    isLoading = true;
    @track pageData;
    @track attendeeSections = [];
    batchId;
    _fetching;
    suppliedBatchName;
    suppliedRangeStartStr;
    suppliedRangeEndStr;

    @wire(CurrentPageReference)
    setPageRef(ref) {
        if (ref?.state?.recordId) {
            this.batchId = ref.state.recordId;
            this.load();
        } else if (this.recordId) {
            this.batchId = this.recordId;
            this.load();
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: COHORT_FIELD_PATHS })
    wiredCohort({ data }) {
        if (data && data.fields) {
            const f = data.fields;
            this.suppliedBatchName = this.fieldVal(f, 'Name', 'ProgramCohort.Name');
            const startRaw = this.fieldRaw(
                f,
                'ProgramCohort.Batch_Start_Date__c',
                'ProgramCohort.StartDate',
                'StartDate',
                'Batch_Start_Date__c'
            );
            const endRaw = this.fieldRaw(f, 'ProgramCohort.EndDate', 'EndDate');
            this.suppliedRangeStartStr = this.toYmd(startRaw);
            this.suppliedRangeEndStr = this.toYmd(endRaw);
        }
        if (this.batchId) {
            this.load();
        }
    }

    fieldVal(fields, ...keys) {
        for (const k of keys) {
            const b = this.tryFieldEntry(fields, k);
            if (b && b.value) {
                return b.value;
            }
        }
        return null;
    }

    fieldRaw(fields, ...keys) {
        for (const k of keys) {
            const b = this.tryFieldEntry(fields, k);
            if (b) {
                return b.value;
            }
        }
        return null;
    }

    tryFieldEntry(fields, key) {
        if (!fields) {
            return null;
        }
        const direct = fields[key];
        if (direct) {
            return direct;
        }
        const bySuffix = Object.keys(fields).find((x) => x === key || x.endsWith(`.${key}`));
        return bySuffix ? fields[bySuffix] : null;
    }

    toYmd(v) {
        if (v == null) {
            return null;
        }
        if (typeof v === 'string' && v.length >= 8) {
            return v.length >= 10 ? v.substring(0, 10) : v;
        }
        const d = new Date(v);
        if (Number.isNaN(d.getTime())) {
            return null;
        }
        return d.toISOString().slice(0, 10);
    }

    connectedCallback() {
        if (this.recordId) {
            this.batchId = this.recordId;
            if (!this._fetching) {
                this.load();
            }
        }
    }

    mapSections(sections) {
        return (sections || []).map((s) => ({
            ...s,
            selectedHostId: s.hostOptions?.find(o => o.isSelected)?.hostProgramCourseId || null,
            hasHostOptions: (s.hostOptions && s.hostOptions.length) > 0,
            hostOptions: (s.hostOptions || []).map((o) => ({ ...o }))
        }));
    }

    load() {
        if (!this.batchId || this._fetching) {
            if (!this.batchId) {
                this.isLoading = false;
                this.toast('Error', 'Missing batch context', 'error');
            }
            return;
        }
        this._fetching = true;
        this.isLoading = true;
        getPageData({
            batchId: this.batchId,
            batchName: this.suppliedBatchName || null,
            rangeStartStr: this.suppliedRangeStartStr || null,
            rangeEndStr: this.suppliedRangeEndStr || null
        })
            .then((data) => {
                this.pageData = data;
                this.attendeeSections = this.mapSections(data && data.attendeeSections);
                this.isLoading = false;
                this._fetching = false;
            })
            .catch((e) => {
                this.isLoading = false;
                this._fetching = false;
                this.toast('Error', this.reduceError(e), 'error');
            });
    }

    get attendeeBatchLabel() {
        const c = this.pageData && this.pageData.context;
        const n = c && c.batchName;
        if (n) {
            return n;
        }
        if (this.batchId) {
            return this.batchId;
        }
        return '—';
    }

   // ── helper: YYYY-MM-DD  →  DD/MM/YYYY ─────────────────────────────────────
fmtDmy(isoStr) {
    if (!isoStr || isoStr.length < 10) return isoStr || '';
    const [y, m, d] = isoStr.substring(0, 10).split('-');
    return `${d}/${m}/${y}`;
}

get dateRangeLabel() {
    const c = this.pageData && this.pageData.context;
    if (!c) {
        return '—';
    }
    if (c.rangeStart && c.rangeEnd) {
        return `${this.fmtDmy(c.rangeStart)} to ${this.fmtDmy(c.rangeEnd)}`;
    }
    if (c.rangeStart) {
        return `From ${this.fmtDmy(c.rangeStart)}`;
    }
    if (c.rangeEnd) {
        return `Until ${this.fmtDmy(c.rangeEnd)}`;
    }
    return 'No batch dates; all eligible host courses shown (where dates are missing)';
}
    get hasSections() {
        return this.attendeeSections && this.attendeeSections.length > 0;
    }

    get saveDisabled() {
        if (!this.hasSections) {
            return true;
        }
        return !this.attendeeSections.some((s) => s.selectedHostId);
    }

    get selectedCount() {
        if (!this.attendeeSections) {
            return 0;
        }
        return this.attendeeSections.filter((s) => s.selectedHostId).length;
    }

    handleHostRadio(event) {
        const el = event.currentTarget;
        const attendeeId = el && el.dataset ? el.dataset.attendeeid : null;
        const hostId = event.detail && event.detail.value != null ? event.detail.value : el && el.value;
        if (attendeeId == null || hostId == null || hostId === '') {
            return;
        }
        this.attendeeSections = this.attendeeSections.map((sec) => {
            if (String(sec.attendeeProgramCourseId) !== String(attendeeId)) {
                return sec;
            }
            return {
                ...sec,
                selectedHostId: hostId,
                hostOptions: (sec.hostOptions || []).map((o) => ({
                    ...o,
                    isSelected: String(o.hostProgramCourseId) === String(hostId)
                }))
            };
        });
    }

    handleSave() {
        const links = this.attendeeSections
            .filter((s) => s.selectedHostId)
            .map((s) => ({
                attendeeProgramCourseId: s.attendeeProgramCourseId,
                hostProgramCourseId: s.selectedHostId
            }));
        if (links.length === 0) {
            this.toast('Info', 'Select a host for at least one program course', 'info');
            return;
        }
        this.isLoading = true;
        saveLmsHostLinks({ links })
            .then(() => {
                this.toast('Success', 'LMS course updated for selected programme courses', 'success');
                this.isLoading = false;
                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch((e) => {
                this.isLoading = false;
                this.toast('Error', this.reduceError(e), 'error');
            });
    }

    reduceError(e) {
        if (e.body && e.body.message) {
            return e.body.message;
        }
        if (e.message) {
            return e.message;
        }
        return 'Unknown error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
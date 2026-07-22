import { LightningElement, track, api } from 'lwc';
import getInterviewMatrixPage
    from '@salesforce/apex/InterviewController.getInterviewMatrixPage';

export default class AdViewEvaluatedInterviewDetails extends LightningElement {

    /* ===============================
       STATE
       =============================== */

    @track headers = [];
    @track rows = [];

    loading = false;

    // pagination
    pageSize = 5;
    pageNumber = 1;
    totalPages = 0;
    disablePrevious = true;
    disableNext = true;

    /* ===============================
       API PROPS (REACTIVE)
       =============================== */

    _applicationIds = [];
    _roundId;

    /** 🔹 Application Slot Ids */
    @api
    get applicationIds() {
        return this._applicationIds;
    }
    set applicationIds(value) {
        this._applicationIds = Array.isArray(value) ? value : [];
        console.log('Received Ids are ',JSON.stringify(value))
        // reload ONLY when both inputs are ready
        if (this._roundId && this._applicationIds.length > 0) {
            
            this.pageNumber = 1;
            this.loadPage();
        }
    }

    /** 🔹 Round Id / Sequence */
    @api
    get roundId() {
        return this._roundId;
    }
    set roundId(value) {
        this._roundId = value;

        if (this._roundId && this._applicationIds.length > 0) {
            this.pageNumber = 1;
            this.loadPage();
        }
    }

    /* ===============================
       DATA LOAD
       =============================== */

    async loadPage() {
        // hard guard
        if (!this._roundId || this._applicationIds.length === 0) {
            this.rows = [];
            this.headers = [];
            return;
        }

        this.loading = true;

        try {
        
           console.log('Round is ',this._roundId)

const result = await getInterviewMatrixPage({
    applicationIds: this._applicationIds,
    roundId: this._roundId
});




            console.log('Interview Matrix Result', JSON.stringify(result));

            /* ---------- Headers ---------- */
            this.headers = (result.criteriaHeaders || []).map(h => ({
                label: h.label,
                key: h.key
            }));

            /* ---------- Rows ---------- */
            this.rows = (result.rows || []).map((row, rowIndex) => {

                const cells = this.headers.map(h => {
    if (h.key === 'TOTAL_SCORE') {
        return {
            key: `${rowIndex}-total`,
            value: row.totalScore ?? ''
        };
    }

    return {
        key: `${rowIndex}-${h.key}`,
        value:
            row.scores && row.scores[h.key] !== undefined
                ? row.scores[h.key]
                : ''
    };
});


                return {
    key: `${row.applicationNumber}-${row.evaluatedBy}`,
    applicationNumber: row.applicationNumber,
    applicantName: row.applicantName,
    roundName: row.roundName,     // ✅ NEW
    evaluatedBy: row.evaluatedBy,
    cells
};

            });

            /* ---------- Pagination ---------- */
            this.totalPages = Math.ceil(
                (result.totalRecords || 0) / this.pageSize
            );

            this.disablePrevious = this.pageNumber <= 1;
            this.disableNext = this.pageNumber >= this.totalPages;

        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading interview matrix', error);
            this.rows = [];
        } finally {
            this.loading = false;
        }
    }

    /* ===============================
       PAGINATION ACTIONS
       =============================== */

    handleNext() {
        if (this.disableNext) return;
        this.pageNumber++;
        this.loadPage();
    }

    handlePrevious() {
        if (this.disablePrevious) return;
        this.pageNumber--;
        this.loadPage();
    }
}
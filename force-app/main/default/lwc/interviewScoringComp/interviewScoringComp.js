import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getSlotBookingsBySlotMaster from '@salesforce/apex/InterviewController.getSlotBookingsBySlotMaster';
import getEvaluationId from '@salesforce/apex/InterviewController.getEvaluationId';
import getEvaluationCriteria from '@salesforce/apex/InterviewController.getEvaluationCriteria';
import upsertIndividualResults from '@salesforce/apex/InterviewController.upsertIndividualResults';
import finishInterview from '@salesforce/apex/InterviewController.finishInterview';
import checkInterviewStatus from '@salesforce/apex/InterviewController.checkInterviewStatus';

export default class InterviewScoringComp extends NavigationMixin(LightningElement) {

    @track slotMasterId    = '';
    @track _bookings       = [];
    @track bookingsLoading = true;
    @track bookingsError   = '';
    @track _stateMap       = {};
    @track showModal       = false;
    @track isSaving        = false;

    @wire(CurrentPageReference)
    getPageRef(ref) {
        if (ref?.attributes?.recordId) {
            this.slotMasterId = ref.attributes.recordId;
        }
    }

    @wire(getSlotBookingsBySlotMaster, { slotMasterId: '$slotMasterId' })
    wiredBookings({ data, error }) {
        this.bookingsLoading = false;
        if (data) {
            this._bookings = data;
            this.bookingsError = '';
            data.forEach(b => {
                if (!this._stateMap[b.id]) {
                    const s = this._emptyState();
                    s.applicationId = b.applicationId;
                    this._stateMap[b.id] = s;
                }
            });
        } else if (error) {
            this.bookingsError = error.body?.message || 'Error loading bookings.';
        }
    }

    _emptyState() {
        return { criteriaResults: [], scoreBuffer: [], evalId: null,
                 isFinished: false, calloutDone: false, applicationId: null };
    }

    _getState(bookingId) {
        if (!this._stateMap[bookingId]) this._stateMap[bookingId] = this._emptyState();
        return this._stateMap[bookingId];
    }

    _mutateState(bookingId, fn) {
        const updated = { ...this._getState(bookingId) };
        fn(updated);
        this._stateMap = { ...this._stateMap, [bookingId]: updated };
    }

    get isEmpty()       { return !this.bookingsLoading && this._bookings.length === 0; }
    get hasContent()    { return !this.bookingsLoading && this._bookings.length > 0; }
    get applicationId() { return this._bookings.length ? this._getState(this._bookings[0].id).applicationId : null; }

    get allFinished() {
        return this._bookings.length > 0 && this._bookings.every(b => this._getState(b.id).isFinished);
    }
    get isCompleteDisabled() { return this.isSaving || this.allFinished; }

    get applicantColumns() {
        return this._bookings.map(b => ({
            key          : b.id,
            scoreKey     : `${b.id}-score-hdr`,
            commentKey   : `${b.id}-comment-hdr`,
            bookingId    : b.id,
            applicantName: b.applicantName || 'Applicant',
            isFinished   : this._getState(b.id).isFinished
        }));
    }

    get criteriaRows() {
        let masterCriteria = [];
        for (const b of this._bookings) {
            const c = this._getState(b.id).criteriaResults;
            if (c.length) { masterCriteria = c; break; }
        }

        return masterCriteria.map(c => ({
            key         : c.Id,
            criteriaName: c.CriteriaName__c || c.Name || '',
            maxScore    : c.Maximum_Score__c,
            cells: this._bookings.map(b => {
                const state = this._getState(b.id);
                const match = state.criteriaResults.find(r => r.Id === c.Id) || {};
                const baseKey = `${b.id}-${c.Id}`;
                return {
                    key        : baseKey,
                    keyScore   : `${baseKey}-s`,
                    keyComment : `${baseKey}-c`,
                    bookingId  : b.id,
                    critId     : c.Id,
                    score      : match.score   ?? '',
                    comment    : match.comment ?? '',
                    isFinished : state.isFinished,
                    isLoading  : !state.calloutDone
                };
            })
        }));
    }

    get isDataLoading() {
        return this._bookings.length > 0 &&
               this._bookings.some(b => !this._getState(b.id).calloutDone);
    }

    async _loadScoringForBooking(bookingId) {
        if (this._getState(bookingId).calloutDone) return;
        this._mutateState(bookingId, s => { s.calloutDone = true; });
        try {
            const [status, result] = await Promise.all([
                checkInterviewStatus({ slotId: bookingId }),
                getEvaluationCriteria({ applicationSlotBookingId: bookingId })
            ]);
            const isFinished = status === 'Complete';
            let criteria     = result.EVAL_REMAINING || result.EVAL_ABSENT || [];
            const indResults = result.EVAL_COMPLETE  || [];
            criteria = criteria.map(c => {
                const m = indResults.find(i => i.Scoring_Template__c === c.Id);
                return { ...c, score: m?.Score__c ?? '', comment: m?.Comments__c ?? '' };
            });
            this._mutateState(bookingId, s => { s.isFinished = isFinished; s.criteriaResults = criteria; });
        } catch (err) {
            console.error('Error loading scoring', bookingId, err);
            this._mutateState(bookingId, s => { s.calloutDone = false; });
        }
    }

    handleScoreChange(event) {
        const bookingId = event.target.dataset.booking;
        const critId    = event.target.dataset.crit;
        const score     = Number(event.target.value);
        const maxScore  = this._getState(bookingId).criteriaResults.find(c => c.Id === critId)?.Maximum_Score__c ?? 10;

        if (Number.isNaN(score) || score < 1 || score > maxScore) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Invalid Score', message: `Score must be between 1 and ${maxScore}`, variant: 'error' }));
            return;
        }
        this._mutateState(bookingId, s => {
            const ex = s.scoreBuffer.find(i => i.CriteriaId === critId);
            if (ex) { ex.Score = score; } else { s.scoreBuffer = [...s.scoreBuffer, { CriteriaId: critId, Score: score }]; }
            s.criteriaResults = s.criteriaResults.map(c => c.Id === critId ? { ...c, score } : c);
        });
    }

    handleCommentChange(event) {
        const bookingId = event.target.dataset.booking;
        const critId    = event.target.dataset.crit;
        const comment   = event.target.value;
        this._mutateState(bookingId, s => {
            const ex = s.scoreBuffer.find(i => i.CriteriaId === critId);
            if (ex) { ex.Comment = comment; } else { s.scoreBuffer = [...s.scoreBuffer, { CriteriaId: critId, Comment: comment }]; }
            s.criteriaResults = s.criteriaResults.map(c => c.Id === critId ? { ...c, comment } : c);
        });
    }

    async handleSaveScore(event) {
        const bookingId = event.target.dataset.booking;
        const state     = this._getState(bookingId);
        if (state.isFinished) return;

        let evalId = state.evalId;
        if (!evalId) {
            evalId = await getEvaluationId({ slotId: bookingId });
            this._mutateState(bookingId, s => { s.evalId = evalId; });
        }

        const payload = this._getState(bookingId).criteriaResults
            .filter(c => c.score !== undefined && c.score !== null && c.score !== '')
            .map(c => ({ scoringTemplateId: c.Id, score: c.score, comment: c.comment || '' }));

        if (!payload.length) {
            this.dispatchEvent(new ShowToastEvent({ title: 'No Scores Entered', message: 'Please enter at least one score.', variant: 'warning' }));
            return;
        }

        try {
            await upsertIndividualResults({ evaluationId: evalId, payload: JSON.stringify(payload) });
            this._mutateState(bookingId, s => { s.scoreBuffer = []; });
            this.dispatchEvent(new ShowToastEvent({ title: 'Scores Saved', variant: 'success' }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error Saving Scores', message: err.body?.message || 'Unexpected error.', variant: 'error' }));
        }
    }

    handleFinish() {
        const unsaved = this._bookings.find(b => {
            const state = this._getState(b.id);
            return !state.isFinished && state.scoreBuffer.length > 0;
        });

        if (unsaved) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Unsaved Changes',
                message: `Please save the scores for "${unsaved.applicantName}" before completing the interview.`,
                variant: 'error',
                mode   : 'sticky'
            }));
            return;
        }

        this.showModal = true;
    }

    handleCancelFinish() { this.showModal = false; }

    async handleConfirmFinish() {
        this.showModal = false;
        this.isSaving  = true;
        try {
            for (const b of this._bookings) {
                if (this._getState(b.id).isFinished) continue;
                let evalId = this._getState(b.id).evalId;
                if (!evalId) {
                    evalId = await getEvaluationId({ slotId: b.id });
                    this._mutateState(b.id, s => { s.evalId = evalId; });
                }
                if (!evalId) continue;
                const result = await finishInterview({ evaluationId: evalId });
                if (result === 'Success') {
                    this._mutateState(b.id, s => { s.isFinished = true; });
                } else {
                    this.dispatchEvent(new ShowToastEvent({ title: `Could not complete for ${b.applicantName}`, message: result, variant: 'error' }));
                }
            }
            this.dispatchEvent(new ShowToastEvent({ title: 'Interview Completed', variant: 'success' }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error Completing Interview', message: err.body?.message || 'Unexpected error.', variant: 'error' }));
        } finally {
            this.isSaving = false;
        }
    }

    async renderedCallback() {
        for (const b of this._bookings) {
            await this._loadScoringForBooking(b.id);
        }
    }
}
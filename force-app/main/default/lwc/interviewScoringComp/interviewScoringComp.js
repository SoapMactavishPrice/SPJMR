import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getSlotBookingsBySlotMaster from '@salesforce/apex/InterviewController.getSlotBookingsBySlotMaster';
import getEvaluationId from '@salesforce/apex/InterviewController.getEvaluationId';
import getEvaluationCriteria from '@salesforce/apex/InterviewController.getEvaluationCriteria';
import upsertIndividualResults from '@salesforce/apex/InterviewController.upsertIndividualResults';
import finishInterview from '@salesforce/apex/InterviewController.finishInterview';
import getVFPageUrl from '@salesforce/apex/InterviewController.getVFPageUrl';
import checkInterviewStatus from '@salesforce/apex/InterviewController.checkInterviewStatus';
import CRITERIA_NAME from '@salesforce/schema/ScoringTemplate__c.Name';
import CRITERIA_DESC from '@salesforce/schema/ScoringTemplate__c.CriteriaName__c';
import CRITERIA_MAXSCORE from '@salesforce/schema/ScoringTemplate__c.Maximum_Score__c';

export default class InterviewScoringComp extends NavigationMixin(LightningElement) {

    @track slotMasterId = '';

    @track _bookings = [];
    @track activeBookingId = '';
    @track bookingsLoading = true;
    @track bookingsError = '';

    @track _stateMap = {};

    criteriaName    = CRITERIA_NAME;
    criteriaDesc    = CRITERIA_DESC;
    criteriaMaxScore = CRITERIA_MAXSCORE;

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
            if (data.length > 0) {
                this.activeBookingId = data[0].id;
                
                data.forEach(b => {
                    if (!this._stateMap[b.id]) {  
                        const state = this._emptyState();
                        state.applicationId = b.applicationId;
                        this._stateMap[b.id] = state;
                    }
                });
            }
        } else if (error) {
            this.bookingsError = error.body?.message || 'Error loading bookings.';
            this._bookings = [];
        }
    }

    _emptyState() {
        return {
            criteriaResults : [],
            indResults      : [],
            scoreBuffer     : [],
            evalId          : null,
            isFinished      : false,
            finishing       : false,
            calloutDone     : false,
            applicationId   : null
        };
    }

    _getActiveState() {
        if (!this._stateMap[this.activeBookingId]) {
            this._stateMap[this.activeBookingId] = this._emptyState();
        }
        return this._stateMap[this.activeBookingId];
    }

    _mutateActiveState(fn) {
        const current = this._getActiveState();
        const updated = { ...current };
        fn(updated);
        this._stateMap = { ...this._stateMap, [this.activeBookingId]: updated };
    }

    get isSingle()   { return this._bookings.length === 1; }
    get isMultiple() { return this._bookings.length > 1; }
    get isEmpty()    { return !this.bookingsLoading && this._bookings.length === 0; }

    get criteriaResults() { return this._getActiveState().criteriaResults; }
    get isFinished()      { return this._getActiveState().isFinished; }

    get isDisabled() {
        const s = this._getActiveState();
        if (s.isFinished) return true;
        if (s.finishing) return true;
        if (s.scoreBuffer.length > 0) return true;
        if (!s.criteriaResults.length) return true;
        return !s.criteriaResults.every(c => c.score !== undefined && c.score !== null && c.score !== '');
    }
    get applicationId()   { return this._getActiveState().applicationId; }

    get tabItems() {
        return this._bookings.map((b, idx) => ({
            id      : b.id,                       
            label   : b.applicantName || `Applicant ${idx + 1}`,
            liClass : `slds-tabs_default__item${b.id === this.activeBookingId ? ' slds-is-active' : ''}`
        }));
    }

    async handleTabClick(event) {
        const newId = event.currentTarget.dataset.id;
        if (newId === this.activeBookingId) return;
        this.activeBookingId = newId;
        await this._loadScoringForActiveBooking();
    }

    async _loadScoringForActiveBooking() {
        const state = this._getActiveState();
        if (state.calloutDone) return;

        const bookingId = this.activeBookingId;

        this._stateMap = {
            ...this._stateMap,
            [bookingId]: { ...this._stateMap[bookingId], calloutDone: true }
        };

        try {
            const [status, result] = await Promise.all([
                checkInterviewStatus({ slotId: bookingId }),
                getEvaluationCriteria({ applicationSlotBookingId: bookingId })
            ]);

            const isFinished = status === 'Complete';
            let criteria = result.EVAL_REMAINING || result.EVAL_ABSENT || [];
            const indResults = result.EVAL_COMPLETE || [];

            criteria = criteria.map(c => {
                const match = indResults.find(i => i.Scoring_Template__c === c.Id);
                return { ...c, score: match?.Score__c, comment: match?.Comments__c };
            });

            this._stateMap = {
                ...this._stateMap,
                [bookingId]: {
                    ...this._stateMap[bookingId],
                    isFinished,
                    criteriaResults: criteria,
                    indResults
                }
            };

        } catch (err) {
            console.error('Error loading scoring for booking', bookingId, err);
            
            this._stateMap = {
                ...this._stateMap,
                [bookingId]: { ...this._stateMap[bookingId], calloutDone: false }
            };
        }
    }

    handleScoreChange(event) {
        const critId = event.target.dataset.crit;
        const score  = Number(event.target.value);

        const state = this._getActiveState();
        const criterion = state.criteriaResults.find(c => c.Id === critId);
        const maxScore = criterion?.Maximum_Score__c ?? 10;

        if (Number.isNaN(score) || score < 1 || score > maxScore) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Invalid Score',
                message: `Score must be between 1 and ${maxScore}`,
                variant: 'error'
            }));
            return;
        }

        this._mutateActiveState(s => {
            const existing = s.scoreBuffer.find(i => i.CriteriaId === critId);
            if (existing) {
                existing.Score = score;
            } else {
                s.scoreBuffer = [...s.scoreBuffer, { CriteriaId: critId, Score: score }];
            }
            s.criteriaResults = s.criteriaResults.map(c =>
                c.Id === critId ? { ...c, score } : c
            );
            s.isDisabled = true;
        });
    }

    handleCommentChange(event) {
        const critId  = event.target.dataset.crit;
        const comment = event.target.value;

        this._mutateActiveState(s => {
            const existing = s.scoreBuffer.find(i => i.CriteriaId === critId);
            if (existing) {
                existing.Comment = comment;
            } else {
                s.scoreBuffer = [...s.scoreBuffer, { CriteriaId: critId, Comment: comment }];
            }
            s.criteriaResults = s.criteriaResults.map(c =>
                c.Id === critId ? { ...c, comment } : c
            );
            s.isDisabled = true;
        });
    }

    async handleSave() {
        const state     = this._getActiveState();
        const bookingId = this.activeBookingId;

        let evalId = state.evalId;
        if (!evalId) {
            evalId = await getEvaluationId({ slotId: bookingId });
            this._mutateActiveState(s => { s.evalId = evalId; });
        }

        if (!state.scoreBuffer.length) return;

        const dirtyIds = new Set(state.scoreBuffer.map(i => i.CriteriaId));

        const payload = state.criteriaResults
            .filter(c => dirtyIds.has(c.Id))
            .map(c => ({
                scoringTemplateId : c.Id,
                score             : c.score,
                comment           : c.comment
            }));

        try {
            await upsertIndividualResults({
                evaluationId : evalId,
                payload      : JSON.stringify(payload)
            });

            this.dispatchEvent(new ShowToastEvent({
                title   : 'Scores Saved',
                variant : 'success'
            }));

            this._mutateActiveState(s => {
                s.scoreBuffer = [];
            });

        } catch (err) {
            console.error('Error saving scores', err);
            this.dispatchEvent(new ShowToastEvent({
                title   : 'Error Saving Scores',
                message : err.body?.message || 'Unexpected error.',
                variant : 'error'
            }));
        }
    }

    async handleFinish() {
        this._mutateActiveState(s => { s.isDisabled = true; });

        let evalId = this._getActiveState().evalId;

        try {
            
            if (!evalId) {
                evalId = await getEvaluationId({ slotId: this.activeBookingId });
                this._mutateActiveState(s => { s.evalId = evalId; });
            }

            const result = await finishInterview({ evaluationId: evalId });

            if (result !== 'Success') {
                this._mutateActiveState(s => { s.isDisabled = false; });
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Could Not Complete Interview',
                    message: result || 'Unexpected error.',
                    variant: 'error'
                }));
                return;
            }

            this._mutateActiveState(s => { s.isFinished = true; });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Interview Completed',
                variant: 'success'
            }));

        } catch (err) {
            console.error('Error finishing interview', err);
            this._mutateActiveState(s => { s.isDisabled = false; });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error Completing Interview',
                message: err.body?.message || 'Unexpected error.',
                variant: 'error'
            }));
        }
    }

    async connectedCallback() {}

    async renderedCallback() {
        if (!this.activeBookingId) return;
        await this._loadScoringForActiveBooking();
    }

    handleViewApplication() {
        const appId = this.applicationId;
        if (!appId) return;

        getVFPageUrl({ applicationId: appId })
            .then(url => {
                if (url) window.open(url, '_blank');
            });
    }
}

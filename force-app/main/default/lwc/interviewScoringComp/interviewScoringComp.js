import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getSlotBookingsBySlotMaster from '@salesforce/apex/InterviewController.getSlotBookingsBySlotMaster';
import getEvaluationId from '@salesforce/apex/InterviewController.getEvaluationId';
import getEvaluationCriteria from '@salesforce/apex/InterviewController.getEvaluationCriteria';
import upsertIndividualResults from '@salesforce/apex/InterviewController.upsertIndividualResults';
import completeInterviewsBulk from '@salesforce/apex/InterviewController.completeInterviewsBulk';
import checkInterviewStatus from '@salesforce/apex/InterviewController.checkInterviewStatus';
import getScoringConfig from '@salesforce/apex/InterviewController.getScoringConfig';
import saveEvaluatorComment from '@salesforce/apex/InterviewController.saveEvaluatorComment';
import getEvaluatorComment from '@salesforce/apex/InterviewController.getEvaluatorComment';
import { publish, MessageContext } from 'lightning/messageService';
import INTERVIEW_MESSAGE_CHANNEL from '@salesforce/messageChannel/InterviewMessageChannel__c';

export default class InterviewScoringComp extends NavigationMixin(LightningElement) {

    @track slotMasterId      = '';
    @track _bookings         = [];
    @track bookingsLoading   = true;
    @track bookingsError     = '';
    @track _stateMap         = {};
    @track showModal         = false;
    @track isSaving          = false;

    @track showCriteriaComment = false;
    @track _configLoaded       = false;
    @track componentError      = '';
    autosaveTimerId = null;

    @wire(MessageContext)
    messageContext;

    @wire(CurrentPageReference)
    getPageRef(ref) {
        if (ref?.attributes?.recordId) {
            this.slotMasterId = ref.attributes.recordId;
        }
    }

    @wire(getSlotBookingsBySlotMaster, { slotMasterId: '$slotMasterId' })
    wiredBookings({ data, error }) {
        this.bookingsLoading = false;
        this.componentError = '';
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
            if (!this._configLoaded && data.length > 0) {
                this._configLoaded = true;
                const programCode = data[0].programCode || '';
                this._loadScoringConfig(programCode);
            }
        } else if (error) {
            this.bookingsError = error.body?.message || 'Error loading bookings.';
        }
    }

    async _loadScoringConfig(programCode) {
        try {
            const cfg = await getScoringConfig({ programCode });
            this.showCriteriaComment = cfg?.showCriteriaComment === true;
        } catch (err) {
            console.error('Error loading scoring config', err);
            this.showCriteriaComment = false;
        }
    }

    _emptyState() {
        return {
            criteriaResults  : [],
            scoreBuffer      : [],
            evalId           : null,
            isFinished       : false,
            calloutDone      : false,
            applicationId    : null,
            evaluatorComment : '',
            commentDirty     : false
        };
    }

    _getState(bookingId) {
        if (!this._stateMap[bookingId]) this._stateMap[bookingId] = this._emptyState();
        return this._stateMap[bookingId];
    }

    _getErrorMessage(err) {
        if (!err) return 'Unable to load scoring criteria.';
        const body = err.body || {};

        // Prefer explicit Apex exception message when present (AuraHandledException)
        if (body.exceptionMessage) return body.exceptionMessage;

        // Sometimes body.message is generic 'Script-thrown exception' while exceptionMessage contains the real text
        if (body.message && body.message !== 'Script-thrown exception') return body.message;

        // Support error.body.output.pageErrors (Lightning server-side shape)
        if (body.output && Array.isArray(body.output.pageErrors) && body.output.pageErrors.length) {
            return body.output.pageErrors.map(p => p.message).join('; ');
        }

        // If body is an array of errors
        if (Array.isArray(body) && body.length) {
            return body.map(b => b?.message || String(b)).join('; ');
        }

        // Fallback to top-level message
        if (err.message && err.message !== 'Script-thrown exception') return err.message;

        // Last resort: try to extract trailing part after colon
        if (typeof body.message === 'string' && body.message.includes(':')) {
            const parts = body.message.split(':');
            const tail = parts.slice(1).join(':').trim();
            if (tail) return tail;
        }

        return 'Unable to load scoring criteria.';
    }

    _mutateState(bookingId, fn) {
        const updated = { ...this._getState(bookingId) };
        fn(updated);
        this._stateMap = { ...this._stateMap, [bookingId]: updated };
    }

    get hasFatalError() { return Boolean(this.bookingsError || this.componentError); }
    get isEmpty()       { return !this.bookingsLoading && !this.hasFatalError && this._bookings.length === 0; }
    get hasContent()    { return !this.bookingsLoading && !this.hasFatalError && this._bookings.length > 0; }
    get applicationId() { return this._bookings.length ? this._getState(this._bookings[0].id).applicationId : null; }
    get displayErrorMessage() { return this.bookingsError || this.componentError || ''; }

    get allFinished() {
        return this._bookings.length > 0 &&
               this._bookings.every(b => this._getState(b.id).isFinished);
    }
    get isCompleteDisabled() { return this.isSaving || this.allFinished; }

    get applicantColumns() {
        return this._bookings.map(b => {
            const state = this._getState(b.id);
            let totalScore = 0;
            if (state.criteriaResults) {
                state.criteriaResults.forEach(c => {
                    const val = parseFloat(c.score);
                    if (!isNaN(val)) {
                        totalScore += val;
                    }
                });
            }
            totalScore = Math.round(totalScore * 100) / 100;

            return {
                key           : b.id,
                scoreKey      : `${b.id}-score-hdr`,
                commentKey    : `${b.id}-comment-hdr`,
                bookingId     : b.id,
                applicantName : b.applicantName || 'Applicant',
                isFinished    : state.isFinished,
                evalComment   : state.evaluatorComment,
                colSpan       : this.showCriteriaComment ? 2 : 1,
                totalScore    : totalScore
            };
        });
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
            criteriaDescription: c.CriteriaDescription__c || '',
            maxScore    : c.Maximum_Score__c,
            cells: this._bookings.map(b => {
                const state    = this._getState(b.id);
                const match    = state.criteriaResults.find(r => r.Id === c.Id) || {};
                const baseKey  = `${b.id}-${c.Id}`;
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
            const [status, result, existingComment] = await Promise.all([
                checkInterviewStatus({ slotId: bookingId }),
                getEvaluationCriteria({ applicationSlotBookingId: bookingId }),
                getEvaluatorComment({ slotId: bookingId })
            ]);

            const isFinished = status === 'Complete';
            let criteria     = result?.EVAL_REMAINING || result?.EVAL_ABSENT || [];
            const indResults = result?.EVAL_COMPLETE  || [];

            criteria = criteria.map(c => {
                const m = indResults.find(i => i.Scoring_Template__c === c.Id);
                return { ...c, score: m?.Score__c ?? '', comment: m?.Comments__c ?? '' };
            });

            if (!criteria.length) {
                this.componentError = 'No scoring templates are configured for this round. Scoring is unavailable.';
                this._mutateState(bookingId, s => {
                    s.isFinished       = isFinished;
                    s.criteriaResults  = [];
                    s.evaluatorComment = existingComment || '';
                    s.commentDirty     = false;
                });
                return;
            }

            this._mutateState(bookingId, s => {
                s.isFinished       = isFinished;
                s.criteriaResults  = criteria;
                s.evaluatorComment = existingComment || '';
                s.commentDirty     = false;
            });

        } catch (err) {
            console.error('Error loading scoring', bookingId, err);
            this.componentError = this._getErrorMessage(err);
            this._mutateState(bookingId, s => { s.calloutDone = true; });
        }
    }

    connectedCallback() {
        this.autosaveTimerId = window.setInterval(() => {
            this._autoSaveAll();
        }, 120000);
    }

    disconnectedCallback() {
        if (this.autosaveTimerId) {
            window.clearInterval(this.autosaveTimerId);
            this.autosaveTimerId = null;
        }
    }

    async _autoSaveAll() {
        if (!this._bookings || this._bookings.length === 0) return;

        for (const b of this._bookings) {
            try {
                const state = this._getState(b.id);
                if (state.isFinished) continue;

                const hasScores = state.criteriaResults
                    .some(c => c.score !== undefined && c.score !== null && c.score !== '');
                const hasComment = state.commentDirty;
                if (!hasScores && !hasComment) continue;

                let invalid = false;
                for (const c of state.criteriaResults) {
                    if (c.score === undefined || c.score === null || c.score === '') continue;
                    const val = Number(c.score);
                    const max = c.Maximum_Score__c ?? 0;
                    if (Number.isNaN(val) || val < 0 || val > max) {
                        invalid = true;
                        break;
                    }
                }
                if (invalid) {
                    console.warn('Auto-save skipped for booking due to invalid score', b.id);
                    continue;
                }

                try {
                    await this._saveBookingData(b.id);
                } catch (err) {
                    console.error('Auto-save error for booking', b.id, err);
                }
            } catch (err) {
                console.error('Error during auto-save loop', err);
            }
        }

        try {
            let payload = { action: 'refresh' };
            publish(this.messageContext, INTERVIEW_MESSAGE_CHANNEL, payload);
        } catch (err) {
            console.error('Error publishing refresh message after auto-save', err);
        }
    }

    handleScoreChange(event) {
        const bookingId = event.target.dataset.booking;
        const critId    = event.target.dataset.crit;
        const score     = Number(event.target.value);
        const maxScore  = this._getState(bookingId).criteriaResults
                              .find(c => c.Id === critId)?.Maximum_Score__c ?? 10;

        if (Number.isNaN(score) || score < 1 || score > maxScore) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Invalid Score', message: `Score must be between 1 and ${maxScore}`, variant: 'error'
            }));
            return;
        }
        this._mutateState(bookingId, s => {
            const ex = s.scoreBuffer.find(i => i.CriteriaId === critId);
            if (ex) { ex.Score = score; }
            else { s.scoreBuffer = [...s.scoreBuffer, { CriteriaId: critId, Score: score }]; }
            s.criteriaResults = s.criteriaResults.map(c =>
                c.Id === critId ? { ...c, score } : c
            );
        });
    }

    handleCommentChange(event) {
        const bookingId = event.target.dataset.booking;
        const critId    = event.target.dataset.crit;
        const comment   = event.target.value;
        this._mutateState(bookingId, s => {
            const ex = s.scoreBuffer.find(i => i.CriteriaId === critId);
            if (ex) { ex.Comment = comment; }
            else { s.scoreBuffer = [...s.scoreBuffer, { CriteriaId: critId, Comment: comment }]; }
            s.criteriaResults = s.criteriaResults.map(c =>
                c.Id === critId ? { ...c, comment } : c
            );
        });
    }

    handleEvaluatorCommentChange(event) {
        const bookingId = event.target.dataset.booking;
        const comment   = event.target.value;
        this._mutateState(bookingId, s => {
            s.evaluatorComment = comment;
            s.commentDirty     = true;
        });
    }

    async _saveBookingData(bookingId) {
        const state = this._getState(bookingId);
        if (state.isFinished) return;

        let evalId = state.evalId;
        if (!evalId) {
            evalId = await getEvaluationId({ slotId: bookingId });
            this._mutateState(bookingId, s => { s.evalId = evalId; });
        }

        const payload = this._getState(bookingId).criteriaResults
            .filter(c => c.score !== undefined && c.score !== null && c.score !== '')
            .map(c => ({ scoringTemplateId: c.Id, score: c.score, comment: c.comment || '' }));

        if (payload.length) {
            await upsertIndividualResults({
                evaluationId : evalId,
                payload      : JSON.stringify(payload)
            });
            this._mutateState(bookingId, s => { s.scoreBuffer = []; });
        }

        const currentComment = this._getState(bookingId).evaluatorComment;
        await saveEvaluatorComment({ evaluationId: evalId, comment: currentComment || '' });
        this._mutateState(bookingId, s => { s.commentDirty = false; });

        return evalId;
    }

    async handleSaveScore(event) {
        const bookingId = event.target.dataset.booking;
        const state     = this._getState(bookingId);
        if (state.isFinished) return;

        const hasScores = state.criteriaResults
            .some(c => c.score !== undefined && c.score !== null && c.score !== '');

        if (!hasScores && !state.evaluatorComment) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Nothing to Save', message: 'Please enter at least one score or a comment.', variant: 'warning'
            }));
            return;
        }

        try {
            await this._saveBookingData(bookingId);
            this.dispatchEvent(new ShowToastEvent({ title: 'Scores Saved', variant: 'success' }));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error Saving Scores', message: err.body?.message || 'Unexpected error.', variant: 'error'
            }));
        } finally {
            let payload = { action: 'refresh' };
            publish(this.messageContext, INTERVIEW_MESSAGE_CHANNEL, payload);
        }
    }

    handleFinish()       { this.showModal = true; }
    handleCancelFinish() { this.showModal = false; }

    async handleConfirmFinish() {
        this.showModal = false;
        this.isSaving  = true;
        try {
            const requests = this._buildBulkCompleteRequests();
            if (!requests.length) {
                this.dispatchEvent(new ShowToastEvent({ title: 'Interview Completed', variant: 'success' }));
                return;
            }

            const results = await completeInterviewsBulk({
                payload: JSON.stringify(requests)
            });

            const failures = [];
            this._bookings.forEach(b => {
                const result = results?.[b.id];
                if (result === 'Success' || result === 'Already Complete') {
                    this._mutateState(b.id, s => {
                        s.isFinished = true;
                        s.scoreBuffer = [];
                        s.commentDirty = false;
                    });
                } else if (result) {
                    failures.push(`${b.applicantName || 'Applicant'}: ${result}`);
                }
            });

            if (failures.length) {
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'Some Interviews Could Not Be Completed',
                    message: failures.join(' | '),
                    variant: 'error'
                }));
            } else {
                this.dispatchEvent(new ShowToastEvent({ title: 'Interview Completed', variant: 'success' }));
            }
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Error Completing Interview',
                message: err.body?.message || 'Unexpected error.',
                variant: 'error'
            }));
        } finally {
            this.isSaving = false;
            let payload = { action: 'refresh' };
            publish(this.messageContext, INTERVIEW_MESSAGE_CHANNEL, payload);
        }
    }

    _buildBulkCompleteRequests() {
        return this._bookings
            .filter(b => !this._getState(b.id).isFinished)
            .map(b => {
                const state = this._getState(b.id);
                const scores = state.criteriaResults
                    .filter(c => c.score !== undefined && c.score !== null && c.score !== '')
                    .map(c => ({
                        scoringTemplateId: c.Id,
                        score            : c.score,
                        comment          : c.comment || ''
                    }));

                return {
                    bookingId       : b.id,
                    evaluationId    : state.evalId,
                    evaluatorComment: state.evaluatorComment || '',
                    scores
                };
            });
    }

    async renderedCallback() {
        for (const b of this._bookings) {
            await this._loadScoringForBooking(b.id);
        }
    }
}
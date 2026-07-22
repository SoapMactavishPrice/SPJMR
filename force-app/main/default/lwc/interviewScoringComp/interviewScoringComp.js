import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getEvaluationId from '@salesforce/apex/InterviewController.getEvaluationId';
import getEvaluationCriteria from '@salesforce/apex/InterviewController.getEvaluationCriteria';
import upsertIndividualResults from '@salesforce/apex/InterviewController.upsertIndividualResults';
import finishInterview from '@salesforce/apex/InterviewController.finishInterview';
import getVFPageUrl from '@salesforce/apex/InterviewController.getVFPageUrl';
import checkInterviewStatus from '@salesforce/apex/InterviewController.checkInterviewStatus';
import applicationIdField from '@salesforce/schema/ApplicationSlotBooking__c.Application__c'
import CRITERIA_NAME from '@salesforce/schema/ScoringTemplate__c.Name';
import CRITERIA_DESC from '@salesforce/schema/ScoringTemplate__c.CriteriaName__c';
import CRITERIA_MAXSCORE from '@salesforce/schema/ScoringTemplate__c.Maximum_Score__c';

const FIELDS = [applicationIdField]
export default class InterviewScoringComp extends NavigationMixin(LightningElement) {

    @track recordId;
    @track criteriaResults = [];
    @track indResults = [];
    @track scoreBuffer = [];

    @track evalId;
    @track isFinished = false;
    @track isDisabled = true;
    
    criteriaName = CRITERIA_NAME;
    criteriaDesc = CRITERIA_DESC;
    criteriaMaxScore = CRITERIA_MAXSCORE;
    // criteriaComment = CRITERIA_COMMENT
    calloutDone = false;

    @wire(CurrentPageReference)
    getPageRef(ref) {
        if (ref?.attributes?.recordId) {
            this.recordId = ref.attributes.recordId;
        }
    }

    @wire(getRecord,{recordId:'$recordId',fields:FIELDS})
    wiredAccount({ error, data }) {
        if (data) {
            this.applicationId = getFieldValue(data, applicationIdField);
            console.log('Received App Id',this.applicationId)
        } else if (error) {
            console.error('Error fetching account:', error);
        }
    }

    handleCommentChange(event){
        const critId = event.target.dataset.crit;
        const comment = event.target.value;

        
        const existing = this.scoreBuffer.find(i => i.CriteriaId === critId);
        if (existing) {
            existing.Comment = comment;
        } else {
            this.scoreBuffer.push({ CriteriaId: critId, Comment:comment });
        }

        this.criteriaResults = this.criteriaResults.map(c =>
            c.Id === critId ? { ...c, comment } : c
        );
    }


    handleScoreChange(event) {
        const critId = event.target.dataset.crit;
        const score = Number(event.target.value);

        if (Number.isNaN(score) || score < 1 || score > 10) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Invalid Score',
                    message: 'Score must be between 1 and 10',
                    variant: 'error'
                })
            );
            return;
        }

        const existing = this.scoreBuffer.find(i => i.CriteriaId === critId);
        if (existing) {
            existing.Score = score;
        } else {
            this.scoreBuffer.push({ CriteriaId: critId, Score: score });
        }

        this.criteriaResults = this.criteriaResults.map(c =>
            c.Id === critId ? { ...c, score } : c
        );
    }

    async handleSave() {
        if (!this.evalId) {
            this.evalId = await getEvaluationId({ slotId: this.recordId });
        }

        if (!this.scoreBuffer.length) return;
        console.log('Params are ',JSON.stringify(this.scoreBuffer), this.evalId)
        const payload = this.scoreBuffer.map(i => ({
                scoringTemplateId: i.CriteriaId,
                score: i.Score,
                comment:i.Comment
            }))
        console.log('Payload is ',JSON.stringify(payload))
        await upsertIndividualResults({
            evaluationId: this.evalId,
            payload:JSON.stringify(payload) 
        }).then(()=>{
            this.dispatchEvent(
            new ShowToastEvent({
                title: 'Scores Saved',
                variant: 'success'
            })
        );

        this.scoreBuffer = [];
        this.isDisabled = false;
        })
        .catch((error)=>{console.log('Error Saving Scores ',JSON.stringify(error))})

        
    }

    async handleFinish() {
        this.isDisabled = true
        await finishInterview({ evaluationId: this.evalId })
        .then((result)=>{
            if(result != 'Success'){
                this.isDisabled = false
            }
        })
        this.isFinished = true;
        //this.isDisabled = true;
    }

    async connectedCallback() {
        const status = await checkInterviewStatus({ slotId: this.recordId });
        this.isFinished = status === 'Complete';
        console.log(status)
    }
 
    async renderedCallback() {
        if (this.calloutDone || !this.recordId) return;
        this.calloutDone = true;

        const result = await getEvaluationCriteria({
            applicationSlotBookingId: this.recordId
        });

        this.criteriaResults = result.EVAL_REMAINING || result.EVAL_ABSENT || [];
        this.indResults = result.EVAL_COMPLETE || [];

        this.criteriaResults = this.criteriaResults.map(c => {
            const match = this.indResults.find(i => i.Scoring_Template__c === c.Id);
            return { ...c, score: match?.Score__c,comment:match?.Comments__c };
        });

        console.log('Received ',result, ' crit Results are ',this.criteriaResults, ' indRes are ',this.indResults )
    }

    handleViewApplication() {
        if (!this.recordId) return;

        getVFPageUrl({ applicationId: this.applicationId })
            .then(url => {
                if (url) window.open(url, '_blank');
            });
    }
}
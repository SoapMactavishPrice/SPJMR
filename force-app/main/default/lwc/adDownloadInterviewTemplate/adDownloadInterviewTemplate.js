import { LightningElement,api,track,wire } from 'lwc';
import getShortlistedApplications from '@salesforce/apex/InterviewController.getShortlistedApplications';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInterviewRounds from '@salesforce/apex/InterviewController.getInterviewRounds'
import getScoringTemplates from '@salesforce/apex/InterviewController.getScoringTemplates'
import processInterview from '@salesforce/apex/InterviewController.processInterview'
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { NavigationMixin } from 'lightning/navigation';
import LightningConfirm from 'lightning/confirm';
import getlogStatus from '@salesforce/apex/InterviewController.getlogStatus'
import InteviewTemplateDownloadMessage from '@salesforce/label/c.InteviewTemplateDownloadMessage'
const columns = [ 
    { label: 'Application Number', fieldName: 'applicationNumber' },
    { label: 'Applicant Name', fieldName: 'applicantName' },
    { label: 'Applicant State', fieldName: 'applicantStateManagement' },
    {label:'Evaluation Score',fieldName:'evaluationScore'},
    {
        type: 'action',
        typeAttributes: {
            rowActions: [{ label: 'View Application', name: 'view' }]
        }
    }
];
export default class AdDownloadInterviewTemplate extends NavigationMixin(LightningElement) {
        fileName = ''
        csvString = ''
        columns = columns;
        timeoutId;
        wiredResult;
        logId='';
        @track selectedRound = '';
        isRoundSelected=false
        @track selectedApplications = [];
        warningMessage = 'Please ensure that all headers from the template are have not been changed.'
        @track allData = [];
        @track pagedData = [];
        @track selectedRows = [];
        roundInfo = [];
        placeholderRound = 'No Rounds Found'
        page = 1;
        pageSize = 10;
        totalPages = 0;
        rounds = []
        cacheRounds = []
        templates = []
        @wire(getInterviewRounds,{pgmCode:'GMP'})
        wiredRounds({error,data}){
            if(data){
                this.placeholderRound = 'Select a round'
                console.log('Found data ',JSON.stringify(data))
                this.cacheRounds = data
                this.rounds = data.map((option)=>{
                    return {label:option.Name, value:option.Id}
                })
            }
            else if(error){
                console.log('Error Fetching Rounds ',JSON.stringify(error))
                
            }
        }

        @wire(getShortlistedApplications)
        wiredApps(result) {
            this.wiredResult = result;
            if (result.data) {
                this.allData = result.data;
                this.totalPages = Math.ceil(this.allData.length / this.pageSize);
                this.page = 1;
                this.setPageData();
            }
        }

        @wire(getRelatedListRecords, {
        parentRecordId: '$selectedRound',
        relatedListId: 'ScoringTemplates__r', // Use the API name of the related list
        fields: ['ScoringTemplate__c.Id', 'ScoringTemplate__c.CriteriaName__c'] // Specify fields to retrieve
    })
    
    
        setPageData() {
            const start = (this.page - 1) * this.pageSize;
            const end = start + this.pageSize;
            this.pagedData = this.allData.slice(start, end);
        }
    
        nextPage() {
            if (this.page < this.totalPages) {
                this.page++;
                this.setPageData();
            }
        }
    
        previousPage() {
            if (this.page > 1) {
                this.page--;
                this.setPageData();
            }
        }
    
        get isFirstPage() {
            return this.page === 1;
        }
    
        get isLastPage() {
            return this.page === this.totalPages;
        }
    
        handleRowSelection(event) {
        const selected = event.detail.selectedRows;

        // Store Ids (required for datatable selection)
        this.selectedRows = selected.map(row => row.Id);

        // Find application numbers from cached data
        this.selectedApplications = selected
            .map(sel =>
                this.allData.find(row => row.Id === sel.Id)
            )
            .filter(Boolean);

        console.log('Row Ids are ', JSON.stringify(this.selectedRows));
        console.log('Application Numbers are ', JSON.stringify(this.selectedApplications));
}

        handleChange(event){
            this.selectedRound = event.detail.value
            if(!this.isRoundSelected) this.isRoundSelected = true
            console.log(this.selectedRound)
            getScoringTemplates({roundId:this.selectedRound})
            .then((result)=>{
                console.log('Result is ',JSON.stringify(result))
                if(result){
                    this.roundInfo = result.map((res,index)=>{
                        return{
                            ...res,
                            index:index+1
                        }
                    })
                }
                })
            .catch((error)=>{
                console.log('Error Getting Scoring Templates ',JSON.stringify(error))
            })
        }
        handleNavigateToRound(){
            if(this.selectedRound){
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: this.selectedRound,
                        objectApiName: 'RoundMaster__c',
                        actionName: 'view'
                    }
                });
            }
        }
       async handleUploadFinished(event){
            const file = event.detail.files[0]
        if (!file) return;

        this.fileName = file.name;
        const docId = file.documentId
        const selectedRoundSeq = this.cacheRounds.find(r => r.Id == this.selectedRound)?.RoundNumber__c
        if(docId){
            console.log('Params are ',docId,selectedRoundSeq,'GMP')
            await processInterview({docId:docId,pgm:'GMP'})
            .then((res)=>{
                this.logId = res
                console.log('Log Id is ', this.logId)
                if(res){
                    this.showToast('Validating Excel...','','info','dismissable')
                    this.checkStatus(res)
                }
                })
            .catch((error)=>{console.log('Error ',JSON.stringify(error))})
        }
    }

    checkStatus(logId){
         this.timeoutId = setTimeout(() => {
            this.fetchStatus();
        }, 3000);
    }

    fetchStatus(){
        getlogStatus({logId:this.logId})
        .then((res)=>{
            console.log('Current Status is ',JSON.stringify(res))
            if(res.Status__c == 'Success'){
                this.showToast('Processing Records','','success','dismissable')
            }
            else if(res.Status__c == 'Error'){
                this.showToast('Error Processing Records',res.Error_Message__c,'error','sticky')
            }
        })
        .catch((error)=>{console.log('Error Fetchting log Status ',JSON.stringify(error),error.stack)})
    }
        async handleDownload(){
            if(this.selectedRound && this.selectedApplications.length>0){
                let continueDownload = false
                await LightningConfirm.open({
                    message:InteviewTemplateDownloadMessage,
                    variant:'header',
                    label:'Continue?',
                    theme:'warning'
                })
                .then((res)=>{
                    continueDownload = res
                })
                if(!continueDownload) return 
                console.log('Rows are ',JSON.stringify(this.selectedRows))
                getScoringTemplates({roundId:this.selectedRound})
                .then((result)=>{
                    console.log('Result is ',JSON.stringify(result))
                    if(result){
                        this.templates = result
                        this.generateCsv()
                    }
                })
            }
                
            
        }

    generateCsv() {
    let doc = '';

    // ---- Header Row ----
    const headers = [
        'Application Number',
        'Applicant Name',
        'Programme',
        'Round',
        'Evaluated By'
    ];

    // Add Criteria + Comment columns
    this.templates.forEach(t => {
        headers.push(`${t.CriteriaName__c} (Max ${t.Maximum_Score__c})`);
headers.push(t.CriteriaName__c + ' Comment');
    });

    doc += headers.join(',') + '\n';

    // ---- Data Rows ----
    this.selectedApplications.forEach(appNumber => {
        const app = this.allData.find(
            row => row.applicationNumber === appNumber.applicationNumber
        );

        if (!app) return;

        const row = [
            `"${app.applicationNumber}"`,
            `"${app.applicantName}"`,
            `"GMP"`,
            `"${this.cacheRounds.find(r => r.Id === this.selectedRound)?.RoundNumber__c || ''}"`,
            `""`
        ];

        // Score + Comment per criteria
        this.templates.forEach(() => {
            row.push(`""`);
            row.push(`""`);
        });

        doc += row.join(',') + '\n';
    });

    // ---- Download (ONLY ONCE, AFTER LOOP) ----
    // ---- Download (LWS SAFE + UTF-8 SAFE) ----

    const bom = new Uint8Array([0xEF, 0xBB, 0xBF]);
    const blob = new Blob([bom,doc], {type: 'text/plain'});
    const dataUrl = URL.createObjectURL(blob);

    let downloadElement = document.createElement('a');
    downloadElement.href = dataUrl; 
    downloadElement.target = '_self'; 
    downloadElement.download = 'Interview_Template.csv'; 
    document.body.appendChild(downloadElement); 
    downloadElement.click();
    // FIX 1: Immediately remove the element from DOM after click
    document.body.removeChild(downloadElement); 

    // FIX 2: Release browser memory by revoking the Object URL
    URL.revokeObjectURL(dataUrl);
    }

    
        get disableDownload() {
            return this.selectedRows.length === 0;
        }
    
        handleRowAction(event) {
            if (event.detail.action.name === 'view') {
                window.open('/' + event.detail.row.Id, '_blank');
            }
        }
    
        showToast(title, message, variant,mode) {
            this.dispatchEvent(
                new ShowToastEvent({ title, message, variant ,mode})
            );
        }
}
import { LightningElement,wire,track } from 'lwc';
import getShortlistedApplicantsGMP from '@salesforce/apex/OfferLetterGenerator.getShortlistedApplicantsGMP';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import OfferBulkModal from 'c/offerBulkModal';
import generateOfferLetters from '@salesforce/apex/OfferLetterGenerator.generateOfferLetters'


const actions = [{label:'View Application', name:'viewApplication'}]

const columns = [
    {label:'Application Number',fieldName:'applicationNumber',type:'text'},
    {label:'Applicant Name',fieldName:'applicantName',type:'text'},
    {label:'Applicant State',fieldName:'applicantStateManagement',type:'text'},
    {label:'Evaluation Score',fieldName:'evaluationScore',type:'text'}, 
    {type:'action',typeAttributes:{rowActions:actions}}
]


export default class AdmissionConvertToStudentTable_GMP extends LightningElement {
    page = 1;
    items = []; 
    data = []; 
    isSelected = false;
    columns; 
    startingRecord = 1; 
    endingRecord = 0; 
    pageSize = 50; 
    totalRecountCount = 0; 
    totalPage = 0; 
    @track selectedRows = [];
    isNextDisable = false
    isPreviousDisable = false

   async generateOfferBulk(){
        const result = await OfferBulkModal.open({
        size: 'small',
        description: 'Bulk Offer Generation'
    });

    if (!result) return;

    const { offerDate, result: decision } = result;
    const applicationIds = [...this.selectedRows];
    console.log('result is ',JSON.stringify(result));
    // Call Apex here
    generateOfferLetters({
        applicationIds,
        offerDate,
        decision
    })
    .then(() => {
        this.showToast(
            'Offer letters generated successfully',
            'success',
            'Success'
        );
    })
    .catch(error => {
        this.showToast(
            error?.body?.message || 'Error generating offer letters',
            'error',
            'Error'
        );
    });
        
    }
  
    renderedCallback(){
            this.isSelected = this.selectedRows.length>0?true:false;      
    }

   updatePaginatedData() {
    const startIndex = (this.page - 1) * this.pageSize; 
    const endIndex = startIndex + this.pageSize; 
    this.paginatedData = this.data.slice(startIndex, endIndex);
  }

    @wire(getShortlistedApplicantsGMP)
    wiredGMPApplications({error,data}){
        if(data){
            this.items = data
            console.log('Data is ',JSON.stringify(data))
            this.totalRecountCount = data.length;
            this.totalPage = Math.ceil(this.totalRecountCount / this.pageSize);

            this.data = this.items.slice(0, this.pageSize);
            this.endingRecord = this.pageSize;
            this.columns = columns;
            this.isNextDisable = this.page >= this.totalPage
            this.isPreviousDisable = this.page <= 1
            this.error = undefined;
            console.log('Page is ',this.page, ' totalPage is ',this.totalPage);
           // console.log('data is ',this.data);
        }
        else if(error){
            this.error = error;
        }
        else if(error){
            this.error = error;
            this.data = undefined;
            this.showToast(this.error, 'Error', 'Error');
        }
    }
        previousHandler() {
        if (this.page > 1) {
            this.page = this.page - 1;
            this.displayRecordPerPage(this.page);
        }
    }

    nextHandler() {
        if ((this.page < this.totalPage) && this.page !== this.totalPage) {
            this.page = this.page + 1;
            this.displayRecordPerPage(this.page);
        }
    }


    handleRowAction(event){
        this.record = event.detail.row;
        const recordId = this.record.Id;
        console.log(JSON.stringify(this.record),' is the record ',this.record.Id)
        console.log('Action is ',event.detail.action.name)
         const actionName = event.detail.action.name;
         if(actionName == 'viewApplication'){
            let element = this.items.find((value)=>value.Id == recordId)
            if(element){
                console.log('Found element',element)
                window.open(element.applicationUrl,'_blank')
            }
         }
        
    }
    displayRecordPerPage(page) {

        this.startingRecord = ((page - 1) * this.pageSize);
        this.endingRecord = (this.pageSize * page);

        this.endingRecord = (this.endingRecord > this.totalRecountCount)
            ? this.totalRecountCount : this.endingRecord;

        this.data = this.items.slice(this.startingRecord, this.endingRecord);

        this.startingRecord = this.startingRecord + 1;
        this.template.querySelector('[data-id="datatable"]').selectedRows = this.selectedRows;
        this.isNextDisable = this.page >= this.totalPage
        this.isPreviousDisable = this.page <= 1
    }

    handleRowSelection(event) {
        let updatedItemsSet = new Set();
        let selectedItemsSet = new Set(this.selectedRows);
        let loadedItemsSet = new Set();

        this.data.map((ele) => {
            loadedItemsSet.add(ele.Id);
        });

        if (event.detail.selectedRows) {
            event.detail.selectedRows.map((ele) => {
                updatedItemsSet.add(ele.Id);
            });

            updatedItemsSet.forEach((id) => {
                if (!selectedItemsSet.has(id)) {
                    selectedItemsSet.add(id);
                }
            });
        }

        loadedItemsSet.forEach((id) => {
            if (selectedItemsSet.has(id) && !updatedItemsSet.has(id)) {
                selectedItemsSet.delete(id);
            }
        });

        this.selectedRows = [...selectedItemsSet];
        console.log('selectedRows==> ' + JSON.stringify(this.selectedRows));
    }

    showToast(message, variant, title) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable'
        });
        this.dispatchEvent(event);
        }
    }
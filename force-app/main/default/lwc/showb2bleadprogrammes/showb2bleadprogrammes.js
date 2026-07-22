import { LightningElement, api, wire,track } from 'lwc';
import returnLeadProgrammes from '@salesforce/apex/B2BLeadProcessController.returnLeadProgrammes'
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead'
import LEAD_SOURCE_FIELD from '@salesforce/schema/Lead.LeadSource'
import { refreshApex } from '@salesforce/apex';
const columns = [{ label: 'Contact Name',  fieldName: 'leadContactUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'leadContactName' },
            target: '_blank' 
        } },
    { label: 'Designation', fieldName: 'Designation' },
    { label: 'Is Primary Contact?', fieldName: 'isPrimaryContact' },
    { label: 'Programmes Applied', fieldName: 'programmeApplied', cellAttributes: {
            class: 'wrapText'
        },
        wrapText: true }]
export default class Showb2bleadprogrammes extends LightningElement {
    @api recordId;
    data = []
    recordTypeId;
    @track leadSourceOptions = []
    childLeadContacts = [];
    columns = columns;
    rowOffset = 0;
    showTable = true;
    wiredLeadContactsResult;
    leadSource = '';
    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    wiredObjectInfo({data}){
        if(data){
            this.recordTypeId =  Object.values(data.recordTypeInfos)
            .find(rt => rt.name === 'B2B')?.recordTypeId;
        }
    }
    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: LEAD_SOURCE_FIELD
    })
     wiredLeadSource({ data }) {
        if (data) {
            this.leadSourceOptions = data.values;
        }
    }
    @wire(returnLeadProgrammes,{
        recordId:'$recordId'
    })
    wiredLeadContacts(result){
        this.wiredLeadContactsResult = result;
         const { data, error } = result;
        if(error){
            console.log('Error Fetching Lead contacts')
        }
        else if(data){
            console.log('Fetched Contacts: ',JSON.stringify(data))
            this.data = data.map((item)=>{
                return{
                    ...item,
                    leadContactUrl: '/' + item.leadConId,
                    programmeApplied:item.programmeApplied?item.programmeApplied.join('\n'):''
                }
            })
        }
    }

     handleSuccess(event) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Lead Contact created successfully.',
                variant: 'success'
            })
        );
        refreshApex(this.wiredLeadContactsResult);
        this.showTable = true
    }


    handleError(event) {
        console.error(event.detail);
        this.showTable = true;
    }

    handleLeadConCreate(){
        this.showTable = false;
    }

    handleCancel() {
        this.template.querySelector('lightning-record-edit-form').reset();
        this.showTable = true;
    }
    handleSubmit(event) {
    event.preventDefault();

    const fields = event.detail.fields;
    fields.Lead__c = this.recordId;
    fields.Lead_Source__c = this.leadSource;

    this.template
        .querySelector('lightning-record-edit-form')
        .submit(fields);

    
}

    handleLeadSourceChange(event) {
    this.leadSource = event.detail.value;
}
     get showEventRemarks() {
        return this.leadSource === 'Events';
    }
}
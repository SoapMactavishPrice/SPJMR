import { LightningElement,track,wire } from 'lwc';
import LightningModal from "lightning/modal";
import retrieveUserInfo from '@salesforce/apex/AssignLeadHelper.retrieveUserInfo'
import retrievePrograms from '@salesforce/apex/AssignLeadHelper.retrievePrograms'
import createLead from '@salesforce/apex/AssignLeadHelper.createLead'
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import LightningToast from "lightning/toast";

export default class AssignLeads extends LightningModal {
    @track selectedProgram;
    @track selectedUser;
    @track programs;
    @track internalUsers;
    @track isLoading = true;
    @track leadId;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference){
        if(currentPageReference){
            this.leadId = currentPageReference.state.recordId;
            console.log('Og Record Id is ',this.leadId)
        }
    }

    handleProgramChange(event){
        this.selectedProgram = event.detail.value;
        console.log('Selected Progtram is',this.selectedProgram)
    }

    handleUserChange(event){
        this.selectedUser = event.detail.value;
        console.log('Selected User is',this.selectedUser)

    }

    closeModal(){
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleAssign(){
        if(this.selectedProgram && this.selectedUser && this.leadId){
           
            this.isLoading = true;
           await createLead({LeadRecordId:this.leadId,ProgramId:this.selectedProgram,UserId:this.selectedUser})
            .then(result=>{
                console.log('Result is ',result)
                Object.keys(result).find(key=>{
                    if(key === 'INSERTION_FAILED'){
                        this.showToast('Unexpected Error Occured',result[key],'error')
                        this.dispatchEvent(errorToast)
                        this.dispatchEvent(new CloseActionScreenEvent());
                    }
                })
                this.isLoading = false;
                const domainName = window.location.origin

                LightningToast.show({
                    label:'Lead Assigned. {0}',
                    labelLinks:[{
                        url:window.location.origin+'/'+result['LeadId'],
                        label:'View'
                    }],variant:'success',mode:'dismissable'
                })
                this.dispatchEvent(new CloseActionScreenEvent());
            })
                
        }
        else{
           this.showToast('Select Program and User before assigning','','error')
            this.dispatchEvent(validationToast)
    }
}

    showToast(title,message,variant){
        const toastEvent = new ShowToastEvent({
            title:title,
            message:message,
            variant:variant,
            mode:'dismissable'
        })
        this.dispatchEvent(toastEvent)
    }

    connectedCallback(){
        retrieveUserInfo()
        .then(result=>{
        console.log(Object.keys(result).length, 'is the number')
        const transformedArray1 = Object.keys(result).map((item)=>
            ({
            label: result[item],
            value: item
        }))
        this.internalUsers = transformedArray1;
        if(transformedArray1[0].value !== 'EMPTY_LIST'){
            this.selectedUser = transformedArray1[0].value;
        }
        })
        .catch(error=>{
            this.showToast('Unexpected Error Occured',error.message,'error')
            console.log('Error is ',error)
        })

        retrievePrograms({LeadId:this.leadId})
        .then(result=>{
            console.log('Result Programs are ',result)
            const transformedArray2 = Object.keys(result).map((item)=>({
                label:result[item],
                value:item
            }))
            this.programs = transformedArray2;
            if(transformedArray2[0].value !== 'EMPTY_LIST' ){
                this.selectedProgram = transformedArray2[0].value;
            }
            
            this.isLoading = false;
        })
        .catch(error=>{
            this.showToast('Unexpected Error Occured',error.message,'error')
            console.log('Error is ',error)
        })

        
    }

}
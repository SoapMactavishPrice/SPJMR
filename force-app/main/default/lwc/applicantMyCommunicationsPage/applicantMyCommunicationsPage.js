import { LightningElement,wire,api,track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import Id from '@salesforce/user/Id';
import EMAIL_FIELD from '@salesforce/schema/User.Email'
import returnEmails from '@salesforce/apex/applicantMyCommunicationController.returnEmails'
import MyCommunicationsEmailModal from 'c/myCommunicationsEmailModal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class ApplicantMyCommunicationsPage extends LightningElement {
    
    @api userEmail;
    @track body = [];
    @track isEmailFound = false;
    showToastEvent(title, message, mode){
        const toastEvent = new ShowToastEvent({
            title:title,
            message:message,
            mode:mode
        })
        this.dispatchEvent(toastEvent)
    }

    @wire(getRecord,{recordId:'$Id',fields:[EMAIL_FIELD]})
    wiredUserEmail({error,data}){
        if(data){
            this.userEmail = data.fields.Email.value;
        }
        else if(error){
            this.showToastEvent('Error',error,'error')
        }
    }

    async showMailContents(event){
        let id = event.currentTarget.dataset.id;
        const emailRecord = this.body.find((email)=>email.Id === id)
        const modalResult = await MyCommunicationsEmailModal.open({
            size:'small',
            payload:emailRecord
        })
    }
   

    @wire(returnEmails,{emailId:'$userEmail'})
    wiredEmailRecords({error,data}){
        console.log('Emails are ',JSON.stringify(data) ,' emailId  is '+this.userEmail, ' UserId ')
        if(data?.length>0){
            this.isEmailFound = true
            const mappedValues = data.map((email)=>{
                let dateValue = new Date(email.MessageDate)
                dateValue = dateValue?dateValue.toDateString().split(" ").slice(1).join(" "):null
                
                return{
                    Id:email.Id,
                    Subject:email.Subject,
                    Body: email.HtmlBody,
                    Time: new Date(email.MessageDate).toLocaleString([],{
                        hour:'2-digit',
                        minute:'2-digit',
                        hour12:true
                    }),
                    Date:dateValue
                }
            })
            this.body = mappedValues
        }else{
            this.isEmailFound = false
        }
        console.log('Body is '+this.body)
}

connectedCallback(){
    
    console.log('User Id ','recordId',' User Email ',this.userEmail)
}


    
}
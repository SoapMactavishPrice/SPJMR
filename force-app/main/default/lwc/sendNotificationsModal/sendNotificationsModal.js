import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import LightningConfirm from 'lightning/confirm';
import createNotifications from '@salesforce/apex/CommunicationsController.createNotifications'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'; 
export default class SendNotificationsModal extends LightningModal {
    @api setApplicationIds;
    subject='';
    message='';
    medium='';
     get options() {
        return [
            { label: 'Email', value: 'email' },
            { label: 'Website', value: 'website' },
            {label:'Email & Website',value:'both'}
        ];
    }
    

    handleChange(event){
        switch (event.target.name){
            case 'subject':
                this.subject = event.target.value
                break
            case 'message':
                this.message = event.target.value
                break
            case 'medium':
                this.medium = event.target.value;
                break
        }
    }

  async handleSend(){
        if(this.subject && this.message && this.medium){
                const result = await LightningConfirm.open({
                message: 'Are you sure you want to send this notification?',
                variant: 'headerless',
            });
            if(result){

                await createNotifications({message:this.message,subject:this.subject,medium:this.medium,listApplicationIds:this.setApplicationIds})
                .then((result)=>{
                    if(result=='Success'){
                        const toastEvent = new ShowToastEvent({
                            title:'Notifications Sent Successfully',
                            message:'',
                            variant:'success'
                            
                        })
                    this.dispatchEvent(toastEvent)
                    this.close()
                    }
                    else{
                        const toastEvent = new ShowToastEvent({
                            title:'Notifications could not be sent',
                            message:'',
                            variant:'error'
                    
                            })
                    this.dispatchEvent(toastEvent)
                    this.close()
                    }

                })
                .catch((error)=>{
                    const toastEvent = new ShowToastEvent({
                            title:'Notifications could not be sent',
                            message:'',
                            variant:'error'
                    
                            })
                    this.dispatchEvent(toastEvent)
                    console.log('Error while creating notifs ',JSON.stringify(error))
                    this.close()
                })
                
                
            }
           
                
            
        }
        else{
            const toastEvent = new ShowToastEvent({
                    title:'Please fill all values before proceeding',
                    message:'',
                    variant:'warning'
                })
                this.dispatchEvent(toastEvent)
                
        }
    }
    renderedCallback(){
        console.log('Application Ids are ', JSON.stringify(this.setApplicationIds));
    }
}
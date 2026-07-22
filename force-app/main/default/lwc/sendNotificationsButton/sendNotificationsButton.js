import { LightningElement,api } from 'lwc';
import SendNotificationsModal from 'c/sendNotificationsModal';
export default class SendNotificationsButton extends LightningElement {
    @api setApplicationIds;
    renderedCallback(){
        console.log('setApplicationIds',this.setApplicationIds);
    
    }
    handleSendNotifications(){
        
            SendNotificationsModal.open({
            label:'Send Notifications to Applicant',
            setApplicationIds:this.setApplicationIds
        });
        
        
    }
}
import { LightningElement, track } from 'lwc';
import getAllNotifications from '@salesforce/apex/CommunicationsController.getAllNotifications';
import markNotificationsRead from '@salesforce/apex/CommunicationsController.markNotificationsRead';

export default class ApShowNotifications extends LightningElement {
    @track notifications = [];
    @track loading = true;

    connectedCallback() {
        this.fetchNotifications();
    }

formatToIST(utcString) {
    if (!utcString) return '';

    const d = new Date(utcString);

   
    const formatter = new Intl.DateTimeFormat('en-IN', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        hour12: true,
        timeZone: 'Asia/Kolkata'
    });

    return formatter.format(d); 
}



    fetchNotifications() {
        getAllNotifications()
            .then(result => {
                this.notifications = result;

               
                const unreadIds = result
                    .filter(n => n.IsRead__c === false)
                    .map(n => n.Id);

                // this.notifications = this.notifications.map(item=>{
                //     return{
                //         ...item,CreatedDate:this.formatToIST(item.CreatedDate)
                //     }
                // })
                if (unreadIds.length > 0) {
                    markNotificationsRead({ notificationIds: unreadIds })
                        .then(() => {
                            console.log('Unread notifications were marked as read.');
                        })
                        .catch(error => {
                            console.error('Error marking as read:', error);
                        });
                }

                this.loading = false;
            })
            .catch(error => {
                console.error('Error fetching notifications:', error);
                this.loading = false;
            });
    }
}
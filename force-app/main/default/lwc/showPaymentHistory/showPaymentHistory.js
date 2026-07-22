import { LightningElement,wire,track } from 'lwc';
import getPaymentHistory from '@salesforce/apex/RazorpayPaymentHandler.getPaymentHistory';
export default class ShowPaymentHistory extends LightningElement {

    @track paymentData=[];
    @wire(getPaymentHistory)
    wiredPaymentHistory({error,data})
    {
        if(data){
             console.log('Received Payments:',data)
            this.paymentData = data.map((value,index)=>{
                return{
                    
                    number:index+1,
                    paymentId:value.paymentId?value.paymentId:'',
                    status:value.status?value.status=='created'?'Not paid':value.status=='paid'?'Paid':'':'',
                    amount:value.amount?value.amount:'',
                    receipt:value.Url?value.Url:'',
                    paymentType:value.paymentType,
                    isPaid:value.status=='paid'?true:false
                }
            })
        }
        else if(error){
            console.log('Could not fetch payment history ',JSON.stringify(error))
            console.error('Could not fetch payment history ',JSON.stringify(error))

        }
    }

    connectedCallback(){
        getPaymentHistory()
        .then((result)=>{
            console.log('Payment History is ',JSON.stringify(result))
        })
        .catch((error)=>{
            console.log('Error fetching payments '+JSON.stringify(error))
        })
    }

}
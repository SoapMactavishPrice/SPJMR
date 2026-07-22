import { LightningElement,api,track } from 'lwc';
import LightningAlert from 'lightning/alert';
import { NavigationMixin } from 'lightning/navigation';
import createOrder from '@salesforce/apex/RazorpayPaymentHandler.createOrder'
export default class RazorpayPaymentButton extends NavigationMixin(LightningElement) {

    @track isDisabled=false;
    _programCode;
    _isAcceptance;

    @api
    get programCode(){
        return this._programCode;
    } 

    
    set programCode(value){
       this._programCode = value
    }
    
    @api
    get isAcceptance(){
        return this._isAcceptance;
    } 

    
    set isAcceptance(value){
       this._isAcceptance = value?value:false
    }

    async paymentHandler() {
        try {
            console.log('Values are ', this._programCode, ' ', this._isAcceptance)
            if(this._isAcceptance && this._programCode){
                // console.log('Paying Acceptance Fees ',this._programCode, ' ',this._isSuccessAcceptanceFeesTest)
                 var returnMap = await createOrder({ ProgramCode: this._programCode,isAcceptance:this._isAcceptance });
                this.isDisabled = true
            console.log('Returned Values are',JSON.stringify(returnMap))
            var orderId = ''
            var amount = ''
            var payeeName = ''
            var payeeEmail = ''
            var paymentId = ''
            var url = ''
            //console.log('Vf Page URl is:', vfPageUrl);
            Object.keys(returnMap).find(key=>{
                switch(key){
                    case 'orderId':
                        orderId = returnMap[key];
                        break;
                    case 'amount':
                        amount = returnMap[key];
                        break;
                    case 'payee_name':
                        payeeName = returnMap[key];
                        break;
                    case 'payee_email':
                        payeeEmail = returnMap[key];
                        break;
                    case 'paymentId':
                        paymentId = returnMap[key];
                        break;
                    case 'url':
                        url = returnMap[key];
                        break;
                    
                        

                }
            }) 

            console.log('Values are ', orderId, amount, payeeName, payeeEmail,paymentId, ' ',url)
            this[NavigationMixin.GenerateUrl]({
            type: 'standard__webPage',
            attributes: {
                url: url 
            }
        }).then(generatedUrl => {
            window.open(generatedUrl);
            console.log('Firing Acceptance Success from razorpayPaymentButton')
            this.dispatchEvent(new CustomEvent('acceptancesuccess', {
    bubbles: true,
    composed: true
}));

        });

        console.log('Values are ', orderId, amount, payeeName, payeeEmail)
            }

        
            
            
        
        else if(this._programCode){
                var returnMap = await createOrder({ ProgramCode: this._programCode});
                this.isDisabled = true
            console.log('Returned Values are',JSON.stringify(returnMap))
            var orderId = ''
            var amount = ''
            var payeeName = ''
            var payeeEmail = ''
            var paymentId = ''
            var url = ''
            //console.log('Vf Page URl is:', vfPageUrl);
            Object.keys(returnMap).find(key=>{
                switch(key){
                    case 'orderId':
                        orderId = returnMap[key];
                        break;
                    case 'amount':
                        amount = returnMap[key];
                        break;
                    case 'payee_name':
                        payeeName = returnMap[key];
                        break;
                    case 'payee_email':
                        payeeEmail = returnMap[key];
                        break;
                    case 'paymentId':
                        paymentId = returnMap[key];
                        break;
                    case 'url':
                        url = returnMap[key];
                        break;
                    
                        

                }
            }) 

            console.log('Values are ', orderId, amount, payeeName, payeeEmail,paymentId)
            this[NavigationMixin.GenerateUrl]({
            type: 'standard__webPage',
            attributes: {
                url: url 
            }
        }).then(generatedUrl => {
            window.open(generatedUrl);
            this.dispatchEvent(new CustomEvent("applicationsuccess"));
        });

        console.log('Values are ', orderId, amount, payeeName, payeeEmail)
            }
            

           // window.location.assign(vfPageUrl)
        //     this[NavigationMixin.GenerateUrl]({
        //     type: 'standard__recordPage',
        //     attributes: {
        //         recordId: paymentId,
        //         objectApiName: 'Payment__c',
        //         actionName: 'view'            },
        // });
            
            
        } catch (error) {
            console.error('Payment error:', error);
            //alert('Payment initialization failed: ' + (error?.body?.message || error.message));
            await LightningAlert.open({
                message: 'Payment initialization failed:'+(error?.body?.message || error.message) ,
                theme: 'error', // a red theme intended for error states
                label: 'Payment Failed!', // this is the header text
            });
        }
    }
}
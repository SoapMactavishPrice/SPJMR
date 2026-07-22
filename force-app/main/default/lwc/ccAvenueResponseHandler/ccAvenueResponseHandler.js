import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import decryptResponse from '@salesforce/apex/CcavenuePaymentHandler.decryptResponse';
import getPaymentStatusByOrderId 
    from '@salesforce/apex/CcavenuePaymentHandler.getPaymentStatusByOrderId';
import handleCCAvenueResponse from '@salesforce/apex/CcavenuePaymentHandler.handleCCAvenueResponse';
export default class CcAvenueResponseHandler extends LightningElement {

    status = 'processing'; // processing | paid | failed | attempted
message = '';
transactionId = '';

get isProcessing() {
    return this.status === 'processing';
}

get isPaid() {
    return this.status === 'paid';
}

get isFailed() {
    return this.status === 'failed';
}

get isAttempted() {
    return this.status === 'attempted';
}

    @wire(CurrentPageReference)
handlePageRef(pageRef) {
    if (!pageRef) return;

    const encResp = pageRef.state?.encResp;

    if (!encResp) {
        this.status = 'failed';
        this.message = 'No payment response received.';
        return;
    }

    this.processPayment(encResp);
}

processPayment(encResp) {
    decryptResponse({ encResponse: encResp })
        .then((decrypted) => {

            const responseMap = this.parseResponse(decrypted);
            const orderId = responseMap.order_id;

            if (!orderId) {
                this.status = 'failed';
                this.message = 'Invalid payment response.';
                return;
            }

            return getPaymentStatusByOrderId({ orderId })
                .then((existingStatus) => {

                    if (existingStatus == 'paid') {
                        this.status = 'paid';
                        this.message = 'Your payment has been confirmed.';
                        this.transactionId = responseMap.tracking_id;
                        return;
                    }

                    return handleCCAvenueResponse({ decryptedResponse: decrypted })
                        .then((result) => {

                            if (result == 'already paid' || result == 'success' || result == 'paid') {
                                this.status = 'paid';
                                this.message = 'Your payment has been completed successfully.';
                                this.transactionId = responseMap.tracking_id;
                            } else if (result === 'failed') {
                                this.status = 'failed';
                                this.message = 'Your payment failed. Please try again.';
                            } else {
                                this.status = 'attempted';
                                this.message = 'Payment was not completed.';
                            }
                        });
                });
        })
        .catch((error) => {
            console.error(error);
            this.status = 'failed';
            this.message = 'Error processing payment.';
        });
}

//     connectedCallback() {

//     const encResp = this.currentPageReference?.state?.encResp;

//     if (!encResp) {
//         this.status = 'failed';
//         this.message = 'No payment response received.';
//         return;
//     }

//     decryptResponse({ encResponse: encResp })
//         .then((decrypted) => {

//             const responseMap = this.parseResponse(decrypted);
//             const orderId = responseMap.order_id;
//             console.log('Decrypted Resp '+decrypted)
//             if (!orderId) {
//                 this.status = 'failed';
//                 this.message = 'Invalid payment response.';
//                 return;
//             }

//             // 🔹 Step 1: Check Salesforce using orderId
//             getPaymentStatusByOrderId({ orderId: orderId })
//                 .then((existingStatus) => {

//                     if (existingStatus === 'paid') {
//                         this.status = 'paid';
//                         this.message = 'Your payment has been confirmed.';
//                         this.transactionId = responseMap.tracking_id;
//                         return;
//                     }

//                     console.log('Not Paid b4, going to update payment Record')
//                     handleCCAvenueResponse({ decryptedResponse: decrypted })
//                         .then((result) => {
//                             console.log('After payment Updation result is '+result)
//                             if(result == 'already paid'){
//                                 this.status = 'paid'
//                                 this.message = 'Your payment has already been completed successfully.';
//                                 this.transactionId = responseMap.tracking_id;
//                                 return
//                             }
//                             if(result == 'success'){
//                                 this.status = 'paid'
//                                 this.message = 'Your payment has been completed successfully.';
//                                 this.transactionId = responseMap.tracking_id;
//                                 return
//                             }
//                             else if(result=='failed'){
//                                 this.status = 'failed';
//                                 this.message = 'Your payment failed. Please try again.';
//                             }
//                             else{
//                                 //  getPaymentStatusByOrderId({ orderId: orderId })
//                                 // .then((updatedStatus) => {

//                                 //     this.status = updatedStatus || 'failed';

//                                 //      if (updatedStatus === 'failed') {
//                                 //         this.message = 'Your payment failed. Please try again.';
//                                 //     }
//                                 //     else if (updatedStatus === 'attempted') {
//                                 //         this.message = 'Payment was cancelled or interrupted.';
//                                 //     }
//                                 //     else {
//                                 //         this.status = 'failed';
//                                 //         this.message = 'Unable to verify payment.';
//                                 //     }

//                                 // });

//                             }
                               

                            
                            

//                         })
//                         .catch((error) => {
//                             console.error('Handle response error', error);
//                             this.status = 'failed';
//                             this.message = 'Error validating payment.';
//                         });

//                 })
//                 .catch((error) => {
//                     console.error('Status check error:', error);
//                     this.status = 'failed';
//                     this.message = 'Unable to verify payment status.';
//                 });

//         })
//         .catch((error) => {
//             console.error('Decryption error:', error);
//             this.status = 'failed';
//             this.message = 'Invalid payment response.';
//         });
// }

    // Parses "key1=val1&key2=val2" into { key1: val1, key2: val2 }
    parseResponse(responseString) {
        return responseString.split('&').reduce((map, pair) => {
            const [key, value] = pair.split('=');
            map[key] = value;
            return map;
        }, {});
    }
}
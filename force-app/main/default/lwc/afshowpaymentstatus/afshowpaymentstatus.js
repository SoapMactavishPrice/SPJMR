import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import generatePaymentReceipt from '@salesforce/apex/RazorpayPageController.generatePaymentReceipt';

import STATUS from '@salesforce/schema/Payment__c.Status__c';
import AMOUNT from '@salesforce/schema/Payment__c.Amount__c';
import ORDER_ID from '@salesforce/schema/Payment__c.Gateway_Order_Id__c';
import PAYMENT_ID from '@salesforce/schema/Payment__c.Razorpay_Payment_Id__c';

const FIELDS = [STATUS, AMOUNT, ORDER_ID, PAYMENT_ID];

export default class PaymentStatus extends LightningElement {

    recordId;
    payment;
    error;
    hasGenerated = false;

    @wire(CurrentPageReference)
    getStateParameters(pageRef) {
        if (pageRef) {
            this.recordId = pageRef.state?.id;
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this.payment = data;
            this.error = undefined;

            // 🔥 Generate receipt only once
            if (this.status === 'paid' && !this.hasGenerated) {
                this.hasGenerated = true;

                generatePaymentReceipt({
                    orderId: this.orderId,
                    paymentId: this.paymentId
                });
            }

        } else if (error) {
            this.error = error;
            this.payment = undefined;
            console.error(error);
        }
    }

    // 🔹 Getters
    get orderId() {
        return this.payment?.fields?.Gateway_Order_Id__c?.value;
    }

    get paymentId() {
        return this.payment?.fields?.Razorpay_Payment_Id__c?.value;
    }

    get amount() {
        return this.payment?.fields?.Amount__c?.value;
    }

    get status() {
        return this.payment?.fields?.Status__c?.value;
    }

    get isLoading() {
        return !this.payment && !this.error;
    }

    // ✅ Only allow PAID
    get isValidPayment() {
        return this.status === 'paid';
    }

    // ❌ Everything else → error
    get hasError() {
        return this.error || (this.payment && this.status !== 'paid');
    }
}
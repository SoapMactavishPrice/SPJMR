import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';

import STATUS from '@salesforce/schema/Payment__c.Status__c';
import ORDER_ID from '@salesforce/schema/Payment__c.Gateway_Order_Id__c';
import AMOUNT from '@salesforce/schema/Payment__c.Amount__c';

const FIELDS = [STATUS, ORDER_ID, AMOUNT];

export default class PaymentCancel extends LightningElement {

    recordId;
    payment;
    error;
    isUnauthorized = false;

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
            this.isUnauthorized = false;
        } else if (error) {
            this.error = error;
            this.payment = undefined;

            // 🔥 Detect access issue
            if (error?.body?.message?.includes('access')) {
                this.isUnauthorized = true;
            }

            console.error(error);
        }
    }

    // 🔹 Getters
    get orderId() {
        return this.payment?.fields?.Gateway_Order_Id__c?.value;
    }

    get amount() {
        return this.payment?.fields?.Amount__c?.value;
    }

    get status() {
        return this.payment?.fields?.Status__c?.value;
    }

    get isLoading() {
        return !this.payment && !this.error && !this.isUnauthorized;
    }

    get hasError() {
        return this.error && !this.isUnauthorized;
    }
}
import { LightningElement, api, wire, track } from 'lwc';
import getDocumentDetails from '@salesforce/apex/DocumentVerificationController.getDocumentDetails';
import updateReviewStatus from '@salesforce/apex/DocumentVerificationController.updateReviewStatus';

import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import DOCUMENT_DETAILS_OBJECT from '@salesforce/schema/Document_Details__c';
import STATUS_FIELD from '@salesforce/schema/Document_Details__c.Document_Review_Status__c';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AttachmentPreviewModal extends LightningElement {
    @api recordId; // Application_Verification__c Id

    @track docs = [];
    loading = true;
    statusOptions = [];

    // ----- Picklist for Review Status -----
    @wire(getObjectInfo, { objectApiName: DOCUMENT_DETAILS_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: STATUS_FIELD
    })
    wiredPicklist({ data, error }) {
        if (data) {
            this.statusOptions = data.values;
        } else if (error) {
            // optional: toast
            // console.error(error);
        }
    }

    // ----- Load documents -----
    @wire(getDocumentDetails, { verificationId: '$recordId' })
    wiredDocs({ data, error }) {
        if (data) {
            this.docs = data.map(d => {
                const files = (d.files || []).map(f => ({
                    ...f
                }));
                return {
                    ...d,
                    files
                };
            });
        } else if (error) {
            this.showToast('Error', 'Failed to load documents', 'error');
            // console.error(error);
            this.docs = [];
        }
        this.loading = false;
    }

    // ----- Status change -----
    handleStatusChange(event) {
        const docId = event.target.dataset.id;
        const newStatus = event.target.value;

        updateReviewStatus({ docId, status: newStatus })
            .then(() => {
                this.docs = this.docs.map(d => {
                    if (d.docId === docId) {
                        return { ...d, reviewStatus: newStatus };
                    }
                    return d;
                });
                this.showToast('Success', 'Review status updated', 'success');
            })
            .catch(() => {
                this.showToast('Error', 'Failed to update status', 'error');
            });
    }

    // ----- Toast helper -----
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
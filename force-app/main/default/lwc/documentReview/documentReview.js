import { LightningElement, api, wire, track } from 'lwc';
import getDocumentDetails from '@salesforce/apex/DocumentVerificationController.getDocumentDetails';
import updateReviewStatus from '@salesforce/apex/DocumentVerificationController.updateReviewStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';

import DOCUMENT_DETAILS_OBJECT from '@salesforce/schema/Document_Details__c';
import STATUS_FIELD from '@salesforce/schema/Document_Details__c.Document_Review_Status__c';

export default class DocumentReview extends LightningElement {

    @api recordId; // Application_Verification__c Id
    @track documents = [];
    loading = true;
    statusOptions = [];

    _typingTimer;

    /* ---------------- OBJECT INFO ---------------- */
    @wire(getObjectInfo, { objectApiName: DOCUMENT_DETAILS_OBJECT })
    objectInfo;

    /* ---------------- PICKLIST VALUES ---------------- */
    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: STATUS_FIELD
    })
    wiredPicklist({ data }) {
        if (data) {
            this.statusOptions = data.values;
        }
    }

    /* ---------------- GET DOCUMENT DETAILS ---------------- */
    @wire(getDocumentDetails, { verificationId: '$recordId' })
    wiredDocs({ data, error }) {
        if (data) {
            this.documents = data.map(doc => {

                const fileOptions = doc.files.map(file => ({
                    label: file.title,
                    value: JSON.stringify(file)
                }));

                let selectedFile = null;
                let showFileSelector = true;

                if (doc.files.length === 1) {
                    selectedFile = doc.files[0];
                    showFileSelector = false;
                }

                return {
                    id: doc.docId,
                    name: doc.name,                 // Document_Details__c.Name
                    status: doc.reviewStatus,
                    remarks: doc.remarks,
                    fileOptions,
                    selectedFile,
                    showFileSelector
                };
            });
        } else if (error) {
            this.showToast('Error', 'Failed to load documents', 'error');
            console.error(error);
        }
        this.loading = false;
    }

    /* ---------------- STATUS CHANGE ---------------- */
    handleStatusChange(event) {
        const docId = event.target.dataset.id;
        const newStatus = event.target.value;

        const doc = this.documents.find(d => d.id === docId);
        const remarks = doc ? doc.remarks : null;

        updateReviewStatus({ docId, status: newStatus, remarks })
            .then(() => {
                this.showToast('Success', 'Status updated successfully', 'success');
            })
            .catch(error => {
                console.error(error);
                this.showToast('Error', 'Failed to update status', 'error');
            });
    }

    /* ---------------- REMARKS (DEBOUNCE SAVE) ---------------- */
    handleRemarksTyping(event) {
        const docId = event.target.dataset.id;
        const newValue = event.target.value;

        // Auto expand textarea
        event.target.style.height = 'auto';
        event.target.style.height = event.target.scrollHeight + 'px';

        // Update local state
        this.documents = this.documents.map(d => {
            if (d.id === docId) {
                return { ...d, remarks: newValue };
            }
            return d;
        });

        // Debounce save
        clearTimeout(this._typingTimer);
        this._typingTimer = setTimeout(() => {
            const doc = this.documents.find(d => d.id === docId);

            updateReviewStatus({
                docId,
                status: doc.status,
                remarks: newValue
            })
                .then(() => {
                    this.showToast('Success', 'Remarks updated', 'success');
                })
                .catch(error => {
                    console.error(error);
                    this.showToast('Error', 'Failed to update remarks', 'error');
                });
        }, 800);
    }

    /* ---------------- FILE SELECT ---------------- */
    handleFileSelect(event) {
        const docId = event.target.dataset.id;
        const selectedFile = JSON.parse(event.detail.value);

        this.documents = this.documents.map(doc => {
            if (doc.id === docId) {
                return { ...doc, selectedFile };
            }
            return doc;
        });
    }

    /* ---------------- TOAST ---------------- */
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
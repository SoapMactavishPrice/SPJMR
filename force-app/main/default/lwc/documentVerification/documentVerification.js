import { LightningElement, api, wire, track } from 'lwc';
import getDocumentDetails from '@salesforce/apex/DocumentVerificationController.getDocumentDetails';
import updateReviewStatus from '@salesforce/apex/DocumentVerificationController.updateReviewStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class DocumentVerification extends LightningElement {
    @api recordId;

    @track docs = [];
    @track showModal = false;
    @track currentAttachments = [];
    currentDocId;

    wiredDocsResult; // 🔥 store the wire result for refreshApex

    get statusOptions() {
        return [
            { label: 'Pending', value: 'Pending' },
            { label: 'Approved', value: 'Approved' },
            { label: 'Rejected', value: 'Rejected' }
        ];
    }

    @wire(getDocumentDetails, { verificationId: '$recordId' })
    loadDocs(result) {
        this.wiredDocsResult = result; // 🔥 store for refreshing

        if (result.data) {
            this.docs = result.data;
        }
    }

    handleStatusChange(event) {
        const docId = event.target.dataset.id;
        const value = event.target.value;

        updateReviewStatus({ docId: docId, status: value })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Status Updated',
                        message: 'Document review status saved successfully',
                        variant: 'success'
                    })
                );

                // 🔄 AUTO REFRESH THE COMPONENT
                return refreshApex(this.wiredDocsResult);
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error'
                    })
                );
            });
    }

    openPreview(event) {
        const docId = event.target.dataset.id;
        const detail = this.docs.find(rec => rec.docId === docId);

        this.currentDocId = docId;
        this.currentAttachments = detail.attachments;
        this.showModal = true;
    }

    closeModal() {
        this.showModal = false;
    }
}
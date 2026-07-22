import { LightningElement, api } from 'lwc';
import generateFinalPdf from '@salesforce/apex/FinalPdfServerMerger.generateFinalPdf';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GenerateFinalPdf extends LightningElement {

    @api recordId;   // ✅ Salesforce injects this automatically for ScreenAction

    hasRun = false;

    async connectedCallback() {

        if (this.hasRun) return;
        this.hasRun = true;

        console.log('🔥 recordId from Salesforce = ', this.recordId);

        // ❗ HARD STOP if still missing
        if (!this.recordId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Configuration Error',
                    message: 'This button is not configured as a Record Action. Please re-add it.',
                    variant: 'error'
                })
            );

            setTimeout(() => {
                this.dispatchEvent(new CloseActionScreenEvent());
            }, 800);

            return;
        }

        try {
            // ==============================
            // CALL APEX
            // ==============================
            const contentVersionId = await generateFinalPdf({
                recordId: this.recordId
            });

            if (!contentVersionId) {
                throw new Error('No file returned from server');
            }

            // ==============================
            // DOWNLOAD
            // ==============================
            window.open(
                '/sfc/servlet.shepherd/version/download/' + contentVersionId,
                '_blank'
            );

            // ==============================
            // SUCCESS
            // ==============================
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Final PDF generated successfully.',
                    variant: 'success'
                })
            );

        } catch (e) {

            console.error('❌ PDF ERROR = ', e);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to generate PDF. Check debug logs.',
                    variant: 'error'
                })
            );

        } finally {
            setTimeout(() => {
                this.dispatchEvent(new CloseActionScreenEvent());
            }, 1000);
        }
    }
}
import { LightningElement, api } from 'lwc';
import pdfLib from '@salesforce/resourceUrl/pdf_lib';
import { loadScript } from 'lightning/platformResourceLoader';

import getVfPdfBase64 from '@salesforce/apex/VfPdfFetcher.getVfPdfBase64';
import getApplicationInfo from '@salesforce/apex/ApplicationNumberFetcher.getApplicationNumber';

import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GenerateFinalPdfWithoutDocuments extends LightningElement {

    @api recordId;

    libLoaded = false;
    hasRun = false;
    isLoading = true;

    async connectedCallback() {

        if (this.hasRun) {
            return;
        }
        this.hasRun = true;

        try {

            // ==============================
            // Load pdf-lib (same as working LWC)
            // ==============================

            if (!this.libLoaded) {
                await loadScript(this, pdfLib);
                this.libLoaded = true;
            }

            // ==============================
            // Get Application Info
            // ==============================

            const appInfo = await getApplicationInfo({
                recordId: this.recordId
            });

            let appNumber = appInfo?.appNumber || 'UNKNOWN';
            let programCode = appInfo?.programCode || 'GMP';

            const fileName =
                programCode === 'PGPM'
                    ? `PGPM_Application_${appNumber}.pdf`
                    : `GMP_Application_${appNumber}.pdf`;

            // ==============================
            // Create PDF Document
            // ==============================

            const { PDFDocument } = window.PDFLib;
            const mergedPdf = await PDFDocument.create();

            // ==============================
            // Load VF PDF ONLY
            // ==============================

            const vfBase64 = await getVfPdfBase64({
                recordId: this.recordId
            });

            const vfBytes = Uint8Array.from(
                atob(vfBase64),
                c => c.charCodeAt(0)
            );

            const vfPdf = await PDFDocument.load(vfBytes);

            const vfPages = await mergedPdf.copyPages(
                vfPdf,
                vfPdf.getPageIndices()
            );

            vfPages.forEach(page => mergedPdf.addPage(page));

            // ==============================
            // Save PDF
            // ==============================

            const finalBytes = await mergedPdf.save();

            const blob = new Blob(
                [finalBytes],
                {
                    type: 'application/pdf'
                }
            );

            const link = document.createElement('a');

            link.href = URL.createObjectURL(blob);
            link.download = fileName;

            link.click();

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'PDF downloaded successfully.',
                    variant: 'success'
                })
            );

        } catch (e) {

            console.error('FULL ERROR = ', e);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message:
                        e?.body?.message ||
                        e?.message ||
                        'Error generating PDF.',
                    variant: 'error'
                })
            );

        } finally {

            this.isLoading = false;

            setTimeout(() => {
                this.dispatchEvent(
                    new CloseActionScreenEvent()
                );
            }, 800);

        }
    }
}
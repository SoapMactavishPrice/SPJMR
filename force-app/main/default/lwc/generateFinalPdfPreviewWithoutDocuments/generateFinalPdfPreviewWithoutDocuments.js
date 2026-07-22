import { LightningElement, api } from 'lwc';
import pdfLib from '@salesforce/resourceUrl/pdf_lib';
import { loadScript } from 'lightning/platformResourceLoader';
import getVfPdfBase64 from '@salesforce/apex/VfPdfFetcher.getVfPdfBase64';

import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GenerateFinalPdfPreviewWithoutDocuments extends LightningElement {

    @api recordId;

    libLoaded = false;
    hasRun = false;
    isLoading = true;

    async connectedCallback() {

        // ==============================
        // OPEN LOADING PAGE
        // ==============================
        const vfLoadingUrl = '/apex/PdfGenerating';
        const previewWindow = window.open(vfLoadingUrl, '_blank');

        if (this.hasRun) {
            return;
        }

        this.hasRun = true;

        try {

            // ==============================
            // Load pdf-lib
            // ==============================
            if (!this.libLoaded) {
                await loadScript(this, pdfLib);
                this.libLoaded = true;
            }

            const { PDFDocument } = window.PDFLib;
            const mergedPdf = await PDFDocument.create();

            // ==============================
            // LOAD VF PDF ONLY
            // ==============================
            const vfBase64 = await getVfPdfBase64({
                recordId: this.recordId
            });

            if (!vfBase64) {
                throw new Error('VF PDF returned EMPTY data');
            }

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
            // SAVE & PREVIEW
            // ==============================

            const finalBytes = await mergedPdf.save();

            const blob = new Blob(
                [finalBytes],
                {
                    type: 'application/pdf'
                }
            );

            const blobUrl = URL.createObjectURL(blob);

            if (previewWindow) {
                previewWindow.location.href = blobUrl;
            }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'PDF opened successfully.',
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
                        'PDF preview failed.',
                    variant: 'error'
                })
            );

            try {
                if (previewWindow) {
                    previewWindow.close();
                }
            } catch (err) {}

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
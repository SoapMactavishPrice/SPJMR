import { LightningElement, api } from 'lwc';
import pdfLib from '@salesforce/resourceUrl/pdf_lib';
import { loadScript } from 'lightning/platformResourceLoader';

import getAllPdfFiles from '@salesforce/apex/FinalPdfFileFetcher.getAllPdfFiles';

import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GenerateFinalPdfPreviewDocumentsOnly extends LightningElement {

    @api recordId;

    libLoaded = false;
    hasRun = false;
    isLoading = true;

    async connectedCallback() {

        const vfLoadingUrl = '/apex/PdfGenerating';
        const previewWindow = window.open(vfLoadingUrl, '_blank');

        if (this.hasRun) {
            return;
        }

        this.hasRun = true;

        try {

            // ============================
            // Load pdf-lib
            // ============================

            if (!this.libLoaded) {
                await loadScript(this, pdfLib);
                this.libLoaded = true;
            }

            const { PDFDocument } = window.PDFLib;

            const mergedPdf = await PDFDocument.create();

            // ============================
            // LOAD ATTACHED DOCUMENTS ONLY
            // ============================

            const files = await getAllPdfFiles({
                recordId: this.recordId
            });

            if (files && files.length > 0) {

                const loadJobs = files.map(async (file) => {

                    if (!file.base64Data) {
                        return null;
                    }

                    try {

                        const bytes = Uint8Array.from(
                            atob(file.base64Data),
                            c => c.charCodeAt(0)
                        );

                        return await PDFDocument.load(bytes);

                    } catch (e) {

                        console.error(e);
                        return null;

                    }

                });

                const loadedFiles = await Promise.all(loadJobs);

                for (let pdf of loadedFiles) {

                    if (!pdf) {
                        continue;
                    }

                    const pages = await mergedPdf.copyPages(
                        pdf,
                        pdf.getPageIndices()
                    );

                    pages.forEach(page => mergedPdf.addPage(page));

                }

            }

            // ============================
            // SAVE & PREVIEW
            // ============================

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
                    message: 'Documents opened successfully.',
                    variant: 'success'
                })
            );

        } catch (e) {

            console.error('FULL ERROR = ', e);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: e?.body?.message || e?.message || 'Document preview failed.',
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
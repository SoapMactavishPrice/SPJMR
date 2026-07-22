import { LightningElement, api } from 'lwc';
import pdfLib from '@salesforce/resourceUrl/pdf_lib';
import { loadScript } from 'lightning/platformResourceLoader';
import getAllPdfFiles from '@salesforce/apex/FinalPdfFileFetcher.getAllPdfFiles';
import getVfPdfBase64 from '@salesforce/apex/VfPdfFetcher.getVfPdfBase64';

import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GenerateFinalPdfPreview extends LightningElement {

    @api recordId;

    libLoaded = false;
    hasRun = false;
    isLoading = true;

    async connectedCallback() {

        // ==============================
        // 🔥 OPEN VISUALFORCE LOADING PAGE (NOT BLANK)
        // ==============================
        const vfLoadingUrl = '/apex/PdfGenerating'; // <-- VF PAGE NAME
        const previewWindow = window.open(vfLoadingUrl, '_blank');

        // 🔒 Prevent double execution
        if (this.hasRun) {
            return;
        }
        this.hasRun = true;

        try {
            console.log('🚀 PDF generation started for recordId = ', this.recordId);

            // ==============================
            // 0️⃣ Load pdf-lib
            // ==============================
            if (!this.libLoaded) {
                await loadScript(this, pdfLib);
                this.libLoaded = true;
            }

            const { PDFDocument } = window.PDFLib;
            const mergedPdf = await PDFDocument.create();

            // ==============================
            // 1️⃣ LOAD VF PDF
            // ==============================
            const vfBase64 = await getVfPdfBase64({ recordId: this.recordId });

            if (!vfBase64) {
                throw new Error('VF PDF returned EMPTY data');
            }

            const vfBytes = Uint8Array.from(atob(vfBase64), c => c.charCodeAt(0));
            const vfPdf = await PDFDocument.load(vfBytes);

            const vfPages = await mergedPdf.copyPages(vfPdf, vfPdf.getPageIndices());
            vfPages.forEach(p => mergedPdf.addPage(p));

            // ==============================
            // 2️⃣ LOAD ATTACHMENTS
            // ==============================
            const files = await getAllPdfFiles({ recordId: this.recordId });

            if (files && files.length > 0) {
                const loadJobs = files.map(async (f) => {
                    if (!f.base64Data) return null;
                    try {
                        const bytes = Uint8Array.from(atob(f.base64Data), c => c.charCodeAt(0));
                        return await PDFDocument.load(bytes);
                    } catch (err) {
                        console.error('❌ Failed to load attachment PDF', err);
                        return null;
                    }
                });

                const loadedFiles = await Promise.all(loadJobs);

                for (let pdf of loadedFiles) {
                    if (!pdf) continue;
                    const pages = await mergedPdf.copyPages(pdf, pdf.getPageIndices());
                    pages.forEach(p => mergedPdf.addPage(p));
                }
            }

            // ==============================
            // 3️⃣ SAVE & SHOW PDF
            // ==============================
            const finalBytes = await mergedPdf.save();
            const blob = new Blob([finalBytes], { type: "application/pdf" });
            const blobUrl = URL.createObjectURL(blob);

            // 🔥 REDIRECT LOADING VF TAB TO PDF
            if (previewWindow) {
                previewWindow.location.href = blobUrl;
            }

            // ==============================
            // ✅ SUCCESS TOAST
            // ==============================
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'PDF opened in new tab.',
                    variant: 'success'
                })
            );

        } catch (e) {

            console.error('❌ ERROR = ', e);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: e?.body?.message || e?.message || 'PDF generation failed',
                    variant: 'error'
                })
            );

            // Close tab if failed
            try {
                if (previewWindow) previewWindow.close();
            } catch {}

        } finally {

            this.isLoading = false;

            setTimeout(() => {
                this.dispatchEvent(new CloseActionScreenEvent());
            }, 8000);
        }
    }
}
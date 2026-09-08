import { LightningElement, api } from 'lwc';
import pdfLib from '@salesforce/resourceUrl/pdf_lib';
import libPdf from '@salesforce/resourceUrl/libpdf';
import { loadScript } from 'lightning/platformResourceLoader';
import { generatePdf } from 'c/pdfHelper';

import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import { openInNewTab } from 'c/applicationFormService';

export default class ApPreviewPdfQuickActionModal extends LightningElement {
    @api recordId;
    isGenerating = true;
    isReady = false;
    previewUrl;
    libLoaded = false;
    hasRun = false;

    async connectedCallback() {
        if (this.hasRun) return;
        this.hasRun = true;
        try {
            if (!this.libLoaded) {
                await loadScript(this, pdfLib);
                await loadScript(this, libPdf);

                this.libLoaded = true;
            }

            const { PDFDocument } = window.PDFLib;
            const { PDF: LibPDF } = window.LibPDF;
            
            const bytes = await generatePdf({
                recordId: this.recordId,
                PDFDocument,
                LibPDF,
                includeApplicationForm: true,
                includeDocuments: true
            });
            
            this.previewUrl = URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' }));
            this.isGenerating = false;
            this.isReady = true;
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: e?.body?.message || e?.message || 'PDF generation failed',
                variant: 'error'
            }));
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }

    handleOpen() {
        openInNewTab(this.previewUrl);
        this.cleanup();
    }
    handleClose() {
        this.cleanup();
    }
    cleanup() {
        if (this.previewUrl) {
            URL.revokeObjectURL(this.previewUrl);
        }
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
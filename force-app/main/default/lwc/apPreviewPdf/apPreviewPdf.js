import { LightningElement, api } from 'lwc';
import pdfLib from '@salesforce/resourceUrl/pdf_lib';
import { loadScript } from 'lightning/platformResourceLoader';

import getApplicationNumber from '@salesforce/apex/ApplicationNumberFetcher.getApplicationNumber';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import libPdf from '@salesforce/resourceUrl/libpdf';
import { generatePdf } from 'c/pdfHelper';

import { openInNewTab } from 'c/applicationFormService';

export default class ApPreviewPdf extends LightningElement {

    _recordId;

    libLoaded = false;
    hasRun = false;
    isLoading = true;
    isDisabled = false;
    previewUrl = null;
    showFallbackPrompt = false;
    showLoadingToast = false;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        if (this._recordId !== value) {
            this._recordId = value;
            this.resetPreviewState();
        }
    }

    async handlePreview() {
        this.isDisabled = true;
        this.showLoadingToast = true;
        this.previewUrl = null;
        this.showFallbackPrompt = false;

        try {
            // ==============================
            // 0️⃣ Load pdf-lib
            // ==============================
            if (!this.libLoaded) {
                await loadScript(this, pdfLib);
                await loadScript(this, libPdf);

                this.libLoaded = true;
            }
            // ==============================
            // 🔹 Get Application Number for filename
            // ==============================
            let appNumber = await getApplicationNumber({ recordId: this.recordId });
            console.log('📄 Application Number = ', appNumber);

             if (!appNumber) {
            appNumber = 'UNKNOWN';
            }

            const { PDFDocument } = window.PDFLib;
            const { PDF: LibPDF } = window.LibPDF;


            const finalBytes = await generatePdf({
                recordId: this.recordId,
                PDFDocument,
                LibPDF,
                includeApplicationForm: true,
                includeDocuments: true
            });

            const blob = new Blob([finalBytes], { type: "application/pdf" });
            const url = URL.createObjectURL(blob);
            this.previewUrl = url;
            this.openPdf(url);

        } catch (e) {

            console.error(' FULL ERROR = ', e);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Error generating PDF. Please check console.',
                    variant: 'error'
                })
            );

        } finally {

            this.isLoading = false;
            this.isDisabled = false;
            this.showLoadingToast = false;
            if (!this.showFallbackPrompt) {
                setTimeout(() => {
                    this.dispatchEvent(new CloseActionScreenEvent());
                }, 800);
            }
        }
    }

    openPdf(blobUrl) {
        openInNewTab(blobUrl);

        this.previewUrl = blobUrl;

        // Keep the fallback available for long-running/blocked cases.
        this.showFallbackPrompt = true;

        window.setTimeout(() => URL.revokeObjectURL(blobUrl), 60000);
    }

    handleManualOpen() {
        if (!this.previewUrl) {
            return;
        }

        openInNewTab(this.previewUrl);

        this.showFallbackPrompt = false;
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleFallbackClose() {
        this.showFallbackPrompt = false;
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    resetPreviewState() {
        if (this.previewUrl) {
            URL.revokeObjectURL(this.previewUrl);
        }
        this.previewUrl = null;
        this.showFallbackPrompt = false;
        this.showLoadingToast = false;
        this.isDisabled = false;
    }
}
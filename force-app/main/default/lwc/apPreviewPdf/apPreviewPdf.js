import { LightningElement, api } from 'lwc';
import pdfLib from '@salesforce/resourceUrl/pdf_lib';
import { loadScript } from 'lightning/platformResourceLoader';
import getDocumentMetadata from '@salesforce/apex/FinalPdfFileFetcher.getDocumentMetadata';
import getPdfChunk from '@salesforce/apex/FinalPdfFileFetcher.getPdfChunk';
import getVfPdfBase64 from '@salesforce/apex/VfPdfFetcher.getVfPdfBase64';
import getApplicationNumber from '@salesforce/apex/ApplicationNumberFetcher.getApplicationNumber';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
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
            const mergedPdf = await PDFDocument.create();
         
            const vfBase64 = await getVfPdfBase64({ recordId: this.recordId });
            const vfBytes = Uint8Array.from(atob(vfBase64), c => c.charCodeAt(0));
            const vfPdf = await PDFDocument.load(vfBytes);

            const vfPages = await mergedPdf.copyPages(vfPdf, vfPdf.getPageIndices());
            vfPages.forEach(p => mergedPdf.addPage(p));

            const metadata = await getDocumentMetadata({
                recordId: this.recordId
            });

            const MAX_CHUNK_SIZE = 5000000;

            let chunks = [];
            let currentChunk = [];
            let currentSize = 0;

            for (const file of metadata) {

                if (
                    currentChunk.length > 0 &&
                    currentSize + file.contentSize > MAX_CHUNK_SIZE
                ) {
                    chunks.push(currentChunk);
                    currentChunk = [];
                    currentSize = 0;
                }

                currentChunk.push(file);
                currentSize += file.contentSize;
            }

            if (currentChunk.length > 0) {
                chunks.push(currentChunk);
            }

            console.log('Chunk length '+chunks.length);

            for (const chunk of chunks) {

                const versionIds = chunk.map(file => file.versionId);

                const pdfFiles = await getPdfChunk({
                    versionIds
                });

                const loadedFiles = await Promise.all(
                    pdfFiles
                        .filter(file => file.base64Data)
                        .map(async file => {
                            const bytes = Uint8Array.from(
                                atob(file.base64Data),
                                c => c.charCodeAt(0)
                            );

                            return PDFDocument.load(bytes);
                        })
                );

                for (const pdf of loadedFiles) {
                    const pages = await mergedPdf.copyPages(
                        pdf,
                        pdf.getPageIndices()
                    );
                    pages.forEach(page => mergedPdf.addPage(page));
                }
            }

            const finalBytes = await mergedPdf.save();

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
        const previewWindow = window.open(blobUrl, '_blank');

        if (!previewWindow) {
            this.showFallbackPrompt = true;
        }

        // Give the browser time to finish loading the blob in the new tab.
        window.setTimeout(() => URL.revokeObjectURL(blobUrl), 60000);
    }

    handleManualOpen() {
        if (!this.previewUrl) {
            return;
        }

        const previewWindow = window.open(this.previewUrl, '_blank');
        if (previewWindow) {
            this.showFallbackPrompt = false;
            this.dispatchEvent(new CloseActionScreenEvent());
        }
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
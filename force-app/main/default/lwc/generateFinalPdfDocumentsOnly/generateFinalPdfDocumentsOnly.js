import { LightningElement, api } from 'lwc';
import pdfLib from '@salesforce/resourceUrl/pdf_lib';
import { loadScript } from 'lightning/platformResourceLoader';

//import getAllPdfFiles from '@salesforce/apex/FinalPdfFileFetcher.getAllPdfFiles';
import getDocumentMetadata from '@salesforce/apex/FinalPdfFileFetcher.getDocumentMetadata';
import getPdfChunk from '@salesforce/apex/FinalPdfFileFetcher.getPdfChunk';
import getApplicationInfo from '@salesforce/apex/ApplicationNumberFetcher.getApplicationNumber';

import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GenerateFinalPdfDocumentsOnly extends LightningElement {

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

            // =====================================
            // Load pdf-lib
            // =====================================

            if (!this.libLoaded) {
                await loadScript(this, pdfLib);
                this.libLoaded = true;
            }

            // =====================================
            // Get Application Info
            // =====================================

            const appInfo = await getApplicationInfo({
                recordId: this.recordId
            });

            const appNumber = appInfo?.appNumber || 'UNKNOWN';
            const programCode = appInfo?.programCode || 'GMP';

            const fileName =
                programCode === 'PGPM'
                    ? `PGPM_Documents_${appNumber}.pdf`
                    : `GMP_Documents_${appNumber}.pdf`;

            // =====================================
            // Create PDF
            // =====================================

            const { PDFDocument } = window.PDFLib;

            const mergedPdf = await PDFDocument.create();

            // =====================================
            // Load Attached Documents ONLY
            // =====================================

           /* const files = await getAllPdfFiles({
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

            }*/
             // =====================================
// Load Attached Documents ONLY
// USING CHUNKS
// =====================================

const metadata = await getDocumentMetadata({
    recordId: this.recordId
});

const MAX_CHUNK_SIZE = 3000000;

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

// Release metadata array
metadata.length = 0;

// =====================================
// Load each chunk
// =====================================

for (const chunk of chunks) {

    const versionIds = chunk.map(file => file.versionId);

    const pdfFiles = await getPdfChunk({
        versionIds: versionIds
    });

    for (const pdfFile of pdfFiles) {

        if (!pdfFile.base64Data) {
            continue;
        }

        try {

            const pdf = await PDFDocument.load(

                Uint8Array.from(

                    atob(pdfFile.base64Data),

                    c => c.charCodeAt(0)

                )

            );

            const pages = await mergedPdf.copyPages(
                pdf,
                pdf.getPageIndices()
            );

            pages.forEach(page => mergedPdf.addPage(page));

        }
        catch (err) {

            console.error(
                'Error loading PDF:',
                pdfFile.fileName,
                err
            );

        }

    }

    // Release browser memory
    pdfFiles.length = 0;
    chunk.length = 0;

}
            // =====================================
            // Download
            // =====================================

            const finalBytes = await mergedPdf.save();
            mergedPdf.flush();
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
                    message: 'Documents downloaded successfully.',
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
                        'Document download failed.',
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
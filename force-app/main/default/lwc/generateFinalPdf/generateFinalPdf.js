import { LightningElement, api } from 'lwc';
import pdfLib from '@salesforce/resourceUrl/pdf_lib';
import { loadScript } from 'lightning/platformResourceLoader';
//import getAllPdfFiles from '@salesforce/apex/FinalPdfFileFetcher.getAllPdfFiles';
import getDocumentMetadata from '@salesforce/apex/FinalPdfFileFetcher.getDocumentMetadata';
import getPdfChunk from '@salesforce/apex/FinalPdfFileFetcher.getPdfChunk';
import getVfPdfBase64 from '@salesforce/apex/VfPdfFetcher.getVfPdfBase64';
//import getApplicationNumber from '@salesforce/apex/ApplicationNumberFetcher.getApplicationNumber';
import getApplicationInfo from '@salesforce/apex/ApplicationNumberFetcher.getApplicationNumber';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GenerateFinalPdf extends LightningElement {

    @api recordId;

    libLoaded = false;
    hasRun = false;     // 🔒 prevent double execution
    isLoading = true;   // 🔄 spinner control

    async connectedCallback() {

        // 🔒 HARD STOP: Salesforce sometimes mounts twice
        if (this.hasRun) {
            return;
        }
        this.hasRun = true;

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
           // let appNumber = await getApplicationNumber({ recordId: this.recordId });
           // console.log('📄 Application Number = ', appNumber);

            // if (!appNumber) {
           // appNumber = 'UNKNOWN';
           // }

            //const fileName = `GMP_Application_${appNumber}.pdf`;
            const appInfo = await getApplicationInfo({ recordId: this.recordId });

            let appNumber = appInfo?.appNumber || 'UNKNOWN';
            let programCode = appInfo?.programCode || 'GMP';

            console.log('📄 Application Number = ', appNumber);
            console.log('📄 Program Code = ', programCode);

            const fileName = programCode === 'PGPM' ? `PGPM_Application_${appNumber}.pdf`: `GMP_Application_${appNumber}.pdf`;

            const { PDFDocument } = window.PDFLib;
            const mergedPdf = await PDFDocument.create();

            // ==============================
            // 1️⃣ LOAD VF PDF
            // ==============================
            const vfBase64 = await getVfPdfBase64({ recordId: this.recordId });
            const vfBytes = Uint8Array.from(atob(vfBase64), c => c.charCodeAt(0));
            const vfPdf = await PDFDocument.load(vfBytes);

            const vfPages = await mergedPdf.copyPages(vfPdf, vfPdf.getPageIndices());
            vfPages.forEach(p => mergedPdf.addPage(p));

            // ==============================
            // 2️⃣ LOAD ATTACHMENTS (PARALLEL)
            // ==============================
           /* const files = await getAllPdfFiles({ recordId: this.recordId });

            const loadJobs = files.map(async (f) => {
            const bytes = Uint8Array.from(atob(f.base64Data), c => c.charCodeAt(0));
            const pdf = await PDFDocument.load(bytes);
            return pdf;
            });


            const loadedFiles = await Promise.all(loadJobs);

            // ==============================
            // 3️⃣ ADD FILES
            // ==============================
            for (let pdf of loadedFiles) {
            const pages = await mergedPdf.copyPages(pdf, pdf.getPageIndices());
            pages.forEach(p => mergedPdf.addPage(p));
            }
             */
            // ==============================
// 2️⃣ LOAD ATTACHMENTS USING CHUNKS
// ==============================

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

// ==============================
// 3️⃣ LOAD EACH CHUNK
// ==============================

for (const chunk of chunks) {

    const versionIds = chunk.map(file => file.versionId);

    const pdfFiles = await getPdfChunk({
        versionIds: versionIds
    });

    for (const pdfFile of pdfFiles) {

        if (!pdfFile.base64Data) {
            continue;
        }

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

}
            // ==============================
            // 4️⃣ SAVE & DOWNLOAD
            // ==============================
            const finalBytes = await mergedPdf.save();

            const blob = new Blob([finalBytes], { type: "application/pdf" });
            const link = document.createElement("a");
            link.href = URL.createObjectURL(blob);
            link.download = fileName;

            //link.download = "Final_Application.pdf";
            link.click();

            // ==============================
            // ✅ SUCCESS TOAST
            // ==============================
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'PDF downloaded successfully.',
                    variant: 'success'
                })
            );

        } catch (e) {

            console.error('❌ FULL ERROR = ', e);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Error generating PDF. Please check console.',
                    variant: 'error'
                })
            );

        } finally {

            // ==============================
            // 5️⃣ STOP SPINNER + CLOSE
            // ==============================
            this.isLoading = false;

            setTimeout(() => {
                this.dispatchEvent(new CloseActionScreenEvent());
            }, 800); // small delay so user sees toast
        }
    }
}
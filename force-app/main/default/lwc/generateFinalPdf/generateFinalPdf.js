import { LightningElement, api } from 'lwc';
import pdfLib from '@salesforce/resourceUrl/pdf_lib';
import { loadScript } from 'lightning/platformResourceLoader';

import libPdf from '@salesforce/resourceUrl/libpdf';
import { generatePdf } from 'c/pdfHelper';

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
                await loadScript(this, libPdf);
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
            const { PDF: LibPDF } = window.LibPDF;

            const finalBytes = await generatePdf({
                recordId: this.recordId,
                PDFDocument,
                LibPDF,
                includeApplicationForm: true,
                includeDocuments: true
            });

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
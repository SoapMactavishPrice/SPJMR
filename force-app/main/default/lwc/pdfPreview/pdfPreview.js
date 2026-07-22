import { LightningElement, api } from 'lwc';

export default class PdfPreview extends LightningElement {
    @api recordId;

    handleOpenPdf() {
        const pdfUrl = `/apex/GenerateProgramPDF?id=${this.recordId}`;
        window.open(pdfUrl, "_blank");
    }
}
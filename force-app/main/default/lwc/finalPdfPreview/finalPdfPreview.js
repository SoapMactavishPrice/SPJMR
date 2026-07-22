import { LightningElement } from 'lwc';

export default class FinalPdfPreview extends LightningElement {

    pdfUrl;

    connectedCallback() {
        const base64 = sessionStorage.getItem('MERGED_PDF_BASE64');

        if (base64) {
            this.pdfUrl = 'data:application/pdf;base64,' + base64;
        } else {
            alert('❌ No PDF data found for preview');
        }
    }
}
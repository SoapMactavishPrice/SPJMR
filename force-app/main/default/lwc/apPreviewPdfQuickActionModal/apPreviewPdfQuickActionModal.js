import { LightningElement, api } from 'lwc';
import pdfLib from '@salesforce/resourceUrl/pdf_lib';
import { loadScript } from 'lightning/platformResourceLoader';
//import getAllPdfFiles from '@salesforce/apex/FinalPdfFileFetcher.getAllPdfFiles';
import getDocumentMetadata from '@salesforce/apex/FinalPdfFileFetcher.getDocumentMetadata';
import getPdfChunk from '@salesforce/apex/FinalPdfFileFetcher.getPdfChunk';
import getVfPdfBase64 from '@salesforce/apex/VfPdfFetcher.getVfPdfBase64';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ApPreviewPdfQuickActionModal extends LightningElement {
 @api recordId;
 isGenerating=true;
 isReady=false;
 previewUrl;
 libLoaded=false;
 hasRun=false;

 async connectedCallback(){
   if(this.hasRun) return;
   this.hasRun=true;
   try{
     if(!this.libLoaded){
       await loadScript(this,pdfLib);
       this.libLoaded=true;
     }
     const {PDFDocument}=window.PDFLib;
     const merged=await PDFDocument.create();

     const vf=await getVfPdfBase64({recordId:this.recordId});
     const vfPdf=await PDFDocument.load(Uint8Array.from(atob(vf),c=>c.charCodeAt(0)));
     const vfPages=await merged.copyPages(vfPdf,vfPdf.getPageIndices());
     vfPages.forEach(p=>merged.addPage(p));

    // const files=await getAllPdfFiles({recordId:this.recordId});
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
     /*for(const f of files){
       if(!f.base64Data) continue;
       const pdf=await PDFDocument.load(Uint8Array.from(atob(f.base64Data),c=>c.charCodeAt(0)));
       const pages=await merged.copyPages(pdf,pdf.getPageIndices());
       pages.forEach(p=>merged.addPage(p));
     }*/
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

        const pages = await merged.copyPages(
            pdf,
            pdf.getPageIndices()
        );

        pages.forEach(page => merged.addPage(page));

    }

}
     const bytes=await merged.save();
     this.previewUrl=URL.createObjectURL(new Blob([bytes],{type:'application/pdf'}));
     this.isGenerating=false;
     this.isReady=true;
   }catch(e){
     this.dispatchEvent(new ShowToastEvent({
       title:'Error',
       message:e?.body?.message||e?.message||'PDF generation failed',
       variant:'error'
     }));
     this.dispatchEvent(new CloseActionScreenEvent());
   }
 }

 handleOpen(){
   window.open(this.previewUrl,'_blank');
   this.cleanup();
 }
 handleClose(){
   this.cleanup();
 }
 cleanup(){
   if(this.previewUrl){
     URL.revokeObjectURL(this.previewUrl);
   }
   this.dispatchEvent(new CloseActionScreenEvent());
 }
}